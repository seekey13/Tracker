--[[
Tracker - one Palalumin turn-in.

The 0x036 body is the one XIIM tradeit builds and checks against the client's
own packets: a zero header (Ashita fills that in), the npc id, ten quantities,
ten slots, the npc index, and how many of those slots are real. A quest
turn-in is one of those packets, for the counts the quest asked for. A second
packet would trade again, and a whole stack would hand over more than asked.
]]

local P = require('lib.daily_parse')

local trade = {}

local NPC_NAME = 'Palalumin'
-- Where Palalumin stands in Hu'Xzoi: X and Y as mobdb shows them.
local NPC_X, NPC_Y = -8.61, -357.43
local TRADE_RANGE = 9 -- GetDistance is squared yalms; 3 yalms
local SEARCH_EVERY = 1 -- seconds between walks of every entity
local MAX_ENTRIES = 8 -- one trade window
local COOLDOWN = 3

-- The click that has not finished yet, or nil.
-- entries are the slots and counts chosen at the click.
local run = nil
local last_sent = nil
-- Palalumin's index from the last walk, and when that walk ran.
local known_index = nil
local searched_at = nil
-- Item ids by name. The button asks every frame, and a name search walks the
-- whole item table.
local item_ids = {}

local function zone_id()
    local ok, zone = pcall(function()
        return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
    end)
    if ok then
        return zone
    end
    return nil
end

-- True while the player is inside an NPC event. A trade sent then replaces
-- the one the NPC is already holding, so the send waits until status leaves 4.
local function in_event()
    local ok, status = pcall(function()
        local mm = AshitaCore:GetMemoryManager()
        return mm:GetEntity():GetStatus(mm:GetParty():GetMemberTargetIndex(0))
    end)
    return ok and status == 4
end

local function clean_name(name)
    if type(name) ~= 'string' then
        return ''
    end
    return (name:gsub('%z.*', ''):gsub('%s+$', ''))
end

-- True in Hu'Xzoi within 3 yalms of Palalumin's spot. Nothing looks for him
-- anywhere else, including the other Lumoria zones.
local function at_spot()
    if zone_id() ~= P.ZONE_HUXZOI then
        return false
    end
    local ok, x, y = pcall(function()
        local mm = AshitaCore:GetMemoryManager()
        local me = mm:GetParty():GetMemberTargetIndex(0)
        local entity = mm:GetEntity()
        return entity:GetLocalPositionX(me), entity:GetLocalPositionY(me)
    end)
    if not ok or type(x) ~= 'number' or type(y) ~= 'number' then
        return false
    end
    local dx, dy = x - NPC_X, y - NPC_Y
    return dx * dx + dy * dy <= TRADE_RANGE
end

-- Index and server id of Palalumin when this character stands at his spot
-- and he is within 3 yalms. The index the last walk found is checked each
-- frame. A walk of every entity runs only when that index is no longer him,
-- and at most once a second.
local function find_npc()
    if not at_spot() then
        return nil
    end
    local found_i, found_id
    local ok = pcall(function()
        local entity = AshitaCore:GetMemoryManager():GetEntity()
        if entity == nil or entity.GetName == nil then
            return
        end
        -- The server id when index i is a rendered Palalumin, else nil.
        local function live(i)
            if clean_name(entity:GetName(i)) ~= NPC_NAME then
                return nil
            end
            local sid = entity:GetServerId(i)
            local flags = entity:GetRenderFlags0(i)
            if sid == nil or sid == 0 or type(flags) ~= 'number' or bit.band(flags, 0x200) == 0 then
                return nil
            end
            return sid
        end
        local sid = known_index and live(known_index)
        if not sid then
            local now = os.clock()
            if searched_at ~= nil and now - searched_at < SEARCH_EVERY then
                return
            end
            searched_at = now
            known_index = nil
            for i = 0, 0x8FF do
                sid = live(i)
                if sid then
                    known_index = i
                    break
                end
            end
            if not sid then
                return
            end
        end
        local dist = entity:GetDistance(known_index)
        if type(dist) == 'number' and dist <= TRADE_RANGE then
            found_i = known_index
            found_id = sid
        end
    end)
    if not ok then
        return nil
    end
    return found_i, found_id
end

local function lookup_id(item_name)
    if item_ids[item_name] then
        return item_ids[item_name]
    end
    local ok, resources = pcall(function()
        return AshitaCore:GetResourceManager()
    end)
    if not ok or resources == nil or resources.GetItemByName == nil then
        return nil
    end
    for _, lang in ipairs({ 0, 1, 2, 3 }) do
        local found, id = pcall(function()
            local item = resources:GetItemByName(item_name, lang)
            if item == nil then
                return nil
            end
            return item.Id
        end)
        if found and type(id) == 'number' and id > 0 then
            item_ids[item_name] = id
            return id
        end
    end
    return nil
end

-- `{name, needed}` rows become item ids. One unresolved name drops the trade:
-- guessing would put the wrong thing in the packet.
local function resolve(needs)
    if type(needs) ~= 'table' then
        return nil
    end
    local wanted = {}
    local index_by_id = {}
    for _, item in ipairs(needs) do
        local name = type(item.name) == 'string' and item.name:match('^%s*(.-)%s*$') or ''
        local count = tonumber(item.needed or item.count) or 0
        if name ~= '' and count > 0 then
            local id = lookup_id(name)
            if not id then
                return nil
            end
            local at = index_by_id[id]
            if at then
                wanted[at].count = wanted[at].count + count
            else
                wanted[#wanted + 1] = { id = id, count = count }
                index_by_id[id] = #wanted
            end
        end
    end
    if #wanted == 0 then
        return nil
    end
    return wanted
end

local function inventory()
    local ok, inv = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    if not ok then
        return nil
    end
    return inv
end

-- Slots that add up to each requested count and no more. Locked stacks are
-- left alone, and this path never splits a trade. When the items are owned
-- but cannot go, the second value says why: 'locked' when locked stacks make
-- up the rest, 'stacks' when they fill more than one trade window.
local function pick(needs)
    local wanted = resolve(needs)
    if not wanted then
        return nil
    end
    local inv = inventory()
    if inv == nil or inv.GetContainerItem == nil then
        return nil
    end
    local max_slot = 0
    local counted, limit = pcall(function()
        return inv:GetContainerCountMax(0)
    end)
    if counted and type(limit) == 'number' then
        max_slot = limit
    end
    local remaining, locked = {}, {}
    for i, row in ipairs(wanted) do
        remaining[i] = row.count
        locked[i] = 0
    end
    local entries = {}
    for slot = 1, max_slot do
        local read_ok, item = pcall(inv.GetContainerItem, inv, 0, slot)
        if read_ok and item and item.Id ~= nil and item.Id ~= 0 then
            for i, row in ipairs(wanted) do
                if item.Id == row.id then
                    local have = tonumber(item.Count) or 0
                    if item.Flags ~= 0 then
                        locked[i] = locked[i] + have
                    elseif remaining[i] > 0 and have > 0 then
                        local take = math.min(have, remaining[i])
                        entries[#entries + 1] = { slot = slot, id = row.id, count = take }
                        remaining[i] = remaining[i] - take
                    end
                    break
                end
            end
        end
    end
    local short = false
    for i, left in ipairs(remaining) do
        if left > locked[i] then
            return nil
        end
        short = short or left > 0
    end
    if short then
        return nil, 'locked'
    end
    if #entries > MAX_ENTRIES then
        return nil, 'stacks'
    end
    if #entries == 0 then
        return nil
    end
    return entries
end

-- The snapshot still has to be those items. A stack that shrank is not sent
-- short, and a stack that grew is not sent in full. before is the stack as
-- sent, so taken() can tell whether Palalumin kept it.
local function confirm(entries)
    local inv = inventory()
    if inv == nil or inv.GetContainerItem == nil then
        return nil
    end
    local live = {}
    for _, entry in ipairs(entries) do
        local read_ok, item = pcall(inv.GetContainerItem, inv, 0, entry.slot)
        local have = read_ok and item and tonumber(item.Count) or 0
        if not read_ok or item == nil or item.Id ~= entry.id or item.Flags ~= 0
            or have < entry.count then
            return nil
        end
        live[#live + 1] = { slot = entry.slot, id = entry.id, count = entry.count, before = have }
    end
    return live
end

-- True when every sent stack is down by what was sent: Palalumin kept the
-- items. False when one is not, as when he hands them back. Nil when the
-- inventory cannot be read.
local function taken(live)
    local inv = inventory()
    if inv == nil or inv.GetContainerItem == nil then
        return nil
    end
    for _, entry in ipairs(live) do
        local read_ok, item = pcall(inv.GetContainerItem, inv, 0, entry.slot)
        if not read_ok then
            return nil
        end
        local now = 0
        if item and item.Id == entry.id then
            now = tonumber(item.Count) or 0
        end
        if now > entry.before - entry.count then
            return false
        end
    end
    return true
end

local function u32(n)
    n = math.floor(tonumber(n) or 0) % 4294967296
    return string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    )
end

local function u16(n)
    n = math.floor(tonumber(n) or 0) % 65536
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u8(n)
    return string.char(math.floor(tonumber(n) or 0) % 256)
end

--- 64-byte 0x036 body. `entries` is `{slot, count}` in trade-window order.
function trade.build_trade(npc_id, npc_index, entries)
    local parts = { u32(0), u32(npc_id) }
    for i = 1, 10 do
        parts[#parts + 1] = u32(entries[i] and entries[i].count or 0)
    end
    for i = 1, 10 do
        parts[#parts + 1] = u8(entries[i] and entries[i].slot or 0)
    end
    parts[#parts + 1] = u16(npc_index)
    parts[#parts + 1] = u8(#entries)
    parts[#parts + 1] = u8(0)
    parts[#parts + 1] = u8(0)
    parts[#parts + 1] = u8(0)
    return table.concat(parts)
end

local function to_bytes(packet)
    if type(packet) == 'string' and type(packet.totable) == 'function' then
        return packet:totable()
    end
    local out = {}
    for i = 1, #packet do
        out[i] = packet:byte(i)
    end
    return out
end

local function cooling_down(now)
    return last_sent ~= nil and (now - last_sent) < COOLDOWN
end

--- nil when the button stays off the row. 'ready' or 'wait' when it is shown.
--- 'blocked' is gray too, and pick's reason comes with it.
function trade.button(needs)
    if run ~= nil then
        return 'wait'
    end
    if not find_npc() then
        return nil
    end
    local entries, why = pick(needs)
    if not entries then
        if why then
            return 'blocked', why
        end
        return nil
    end
    if cooling_down(os.clock()) then
        return 'wait'
    end
    return 'ready'
end

--- Queue the one turn-in. False when a trade is already waiting, cooling
--- down, or the slots cannot make exactly this request.
function trade.start(needs)
    if run ~= nil or cooling_down(os.clock()) then
        return false
    end
    if not find_npc() then
        return false
    end
    local entries = pick(needs)
    if not entries then
        return false
    end
    run = { entries = entries, sent = false }
    return true
end

function trade.cancel()
    run = nil
end

--- Send the queued trade once it is safe to. 'sent' on the frame it is sent.
--- 'traded' on the frame the wait after it ends, when Palalumin kept the
--- items. False otherwise.
function trade.update()
    if run == nil then
        return false
    end
    local zone = zone_id()
    if zone ~= nil and zone ~= P.ZONE_HUXZOI then
        run = nil
        return false
    end
    if run.sent then
        if in_event() then
            return false
        end
        if os.clock() < run.deadline then
            return false
        end
        local kept = taken(run.live)
        run = nil
        if kept then
            return 'traded'
        end
        return false
    end
    if in_event() then
        return false
    end
    local now = os.clock()
    local index, sid = find_npc()
    local live = index and confirm(run.entries) or nil
    if not index or not live then
        if zone == nil then
            return false
        end
        run = nil
        return false
    end

    local previous = last_sent
    run.sent = true
    run.live = live
    last_sent = now
    run.deadline = now + COOLDOWN
    local packet = to_bytes(trade.build_trade(sid, index, live))
    local sent_ok = pcall(function()
        AshitaCore:GetPacketManager():AddOutgoingPacket(0x36, packet)
    end)
    if not sent_ok then
        run = nil
        last_sent = previous
        return false
    end
    return 'sent'
end

return trade
