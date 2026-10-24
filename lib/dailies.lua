--[[
Tracker - goblin dailies, Palalumin quests, and the Aether Traveler's week.

Dialogue is taken in Lower Jeuno (goblins), Lumoria (Palalumin), or Port
Jeuno (the Aether Traveler). Progress after that is a system line, a trade
packet, or a count of items in the inventory. The dailies reset at Japanese
midnight. The Aether Traveler's request lasts until midnight Monday there.
]]

local chat = require('chat')
local settingslib = require('settings')
local P = require('lib.daily_parse')
local trade = require('lib.trade')

local dailies = {}

dailies.order = P.GOBLIN_ORDER
dailies.pala_order = P.PALALUMIN_ORDER

local cfg
local recent_trade = false
-- The button sends to Palalumin whatever the player has targeted. A turn-in
-- to Beetrix leaves this alone.
local button_trade = false
local counts = nil
local item_ids = {}

local function save()
    settingslib.save()
end

function dailies.bind(saved)
    cfg = saved
    if type(cfg.dailies) ~= 'table' then
        cfg.dailies = {}
    end
    if type(cfg.palalumin_quests) ~= 'table' then
        cfg.palalumin_quests = {}
    end
end

function dailies.settings()
    return cfg
end

function dailies.begin_frame()
    counts = {}
end

-- His week is taken to end at 00:00 JST Monday. 1970-01-01 was a Thursday,
-- three days past a Monday.
local function week_deadline()
    local offset = tonumber(cfg.offset) or (60 * 60 * 9)
    local day = math.floor((os.time() + offset) / 86400)
    return (day - (day + 3) % 7 + 7) * 86400 - offset
end

-- A request heard in an earlier week is gone.
local function roll_week()
    local row = cfg.aether
    if row ~= nil and not (type(row) == 'table' and os.time() < (tonumber(row.deadline) or 0)) then
        cfg.aether = nil
        save()
    end
end

-- The day rolls at 00:00 JST. offset is seconds ahead of UTC (9 hours).
function dailies.roll_day()
    if cfg == nil then
        return false
    end
    roll_week()
    local offset = tonumber(cfg.offset) or (60 * 60 * 9)
    local now = os.time()
    local deadline = math.floor((now + offset) / 86400) * 86400 + 86400 - offset
    local version_ok = cfg.version == 1
    if version_ok and cfg.deadline == deadline then
        return false
    end
    cfg.dailies = {}
    cfg.palalumin_quests = {}
    cfg.palalumin_flagged = false
    cfg.goldilox_time = nil
    trade.cancel()
    cfg.version = 1
    cfg.deadline = deadline
    save()
    return true
end

local function lookup_item_id(item_name)
    if item_ids[item_name] ~= nil then
        return item_ids[item_name] or nil
    end
    local resources = AshitaCore:GetResourceManager()
    if not resources then
        return nil
    end
    for _, lang in ipairs({ 0, 1, 2, 3 }) do
        local ok, id = pcall(function()
            local item = resources:GetItemByName(item_name, lang)
            if item == nil then
                return nil
            end
            return item.Id
        end)
        if ok and type(id) == 'number' and id > 0 then
            item_ids[item_name] = id
            return id
        end
    end
    return nil
end

-- Inventory only (container 0), locked stacks included. Slot 0 is gil, so
-- the count runs from slot 1, as a trade does. Nil when the client cannot
-- answer yet.
function dailies.item_count(item_name)
    if type(item_name) ~= 'string' or item_name == '' then
        return nil
    end
    if counts and counts[item_name] ~= nil then
        local cached = counts[item_name]
        if cached == false then
            return nil
        end
        return cached
    end
    local item_id = lookup_item_id(item_name)
    if not item_id then
        if counts then
            counts[item_name] = false
        end
        return nil
    end
    local inventory = AshitaCore:GetMemoryManager():GetInventory()
    if not inventory then
        return nil
    end
    local last = 80
    local sized, limit = pcall(function()
        return inventory:GetContainerCountMax(0)
    end)
    if sized and type(limit) == 'number' and limit > 0 then
        last = limit
    end
    local total = 0
    for i = 1, last do
        local ok, count = pcall(function()
            local entry = inventory:GetContainerItem(0, i)
            if entry == nil or entry.Id ~= item_id then
                return 0
            end
            return entry.Count or 0
        end)
        if ok and type(count) == 'number' then
            total = total + count
        end
    end
    if counts then
        counts[item_name] = total
    end
    return total
end

local function target_name()
    local target = AshitaCore:GetMemoryManager():GetTarget()
    if target == nil then
        return nil
    end
    local idx
    if target:GetIsSubTargetActive() == 0 then
        idx = target:GetTargetIndex(0)
    else
        idx = target:GetTargetIndex(1)
    end
    local ent = GetEntity(idx)
    if ent == nil then
        return nil
    end
    return ent.Name
end

local function apply_system(event)
    if event.kind == 'return' then
        local row = cfg.dailies[event.npc]
        if row then
            row.status = 'return'
            save()
        end
        return
    end
    if event.kind == 'complete' then
        local row = cfg.dailies[event.npc]
        if row then
            row.status = 'complete'
            save()
        end
        return
    end
    if event.kind == 'murdox' then
        local row = cfg.dailies.Murdox
        if not row then
            return
        end
        row.remaining = event.kills
        if event.mob and not row.target then
            row.target = event.mob
        end
        if event.zone and not row.zone then
            row.zone = event.zone
        end
        save()
        return
    end
    if event.kind == 'pala_kills' then
        cfg.palalumin_flagged = true
        local row = cfg.palalumin_quests['Defeat mobs']
        if not row then
            row = { message = '' }
            cfg.palalumin_quests['Defeat mobs'] = row
        end
        row.killed = event.killed
        row.total = event.total
        row.target = event.target
        row.zone = event.zone
        save()
        return
    end
    if event.kind == 'quest_completed' then
        local name = target_name()
        if name == 'Lumorian Flux' then
            local row = cfg.palalumin_quests['Find flux']
            if row then
                row.completed = true
                save()
            end
        elseif name == 'Palalumin' or button_trade then
            local defeat = cfg.palalumin_quests['Defeat mobs']
            if defeat and not defeat.completed and defeat.killed and defeat.total and defeat.killed >= defeat.total then
                defeat.completed = true
                save()
            end
            if recent_trade then
                local item_req = cfg.palalumin_quests['Item request']
                if item_req and not item_req.completed then
                    item_req.completed = true
                    save()
                end
            end
        end
        recent_trade = false
        button_trade = false
        return
    end
    if event.kind == 'dice' then
        cfg.goldilox_time = cfg.deadline
        save()
    end
end

function dailies.on_trade()
    recent_trade = true
end

function dailies.on_text(e)
    if e == nil or e.injected or cfg == nil then
        return
    end
    dailies.roll_day()
    local raw = e.message or ''
    local clean = P.strip(raw)

    local hint = P.chest_hint(clean)
    if hint then
        if cfg.dailies.Fishstix then
            cfg.dailies.Fishstix.hint = hint
            save()
        end
        return
    end

    local channel = bit.band(e.mode or 0, 0xFF)
    if channel == 121 then
        local event = P.read_system(clean)
        if event then
            apply_system(event)
        end
        return
    end
    if channel ~= 9 then
        return
    end

    local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
    if zone == P.ZONE_LOWER_JEUNO then
        local npc, data = P.read_goblin(clean, nil)
        if npc == nil then
            return
        end
        -- A second visit must not forget how many Murdox kills are left.
        local prev = cfg.dailies[npc]
        if npc == 'Murdox' and prev and prev.remaining then
            data.remaining = prev.remaining
        end
        -- "Congratulations! You've completed my quest..." replaces the task
        -- line. Keep the zone and item, and show the row as finished.
        if type(data.message) == 'string' and data.message:lower():find('congratulat', 1, true) then
            data.status = 'complete'
            if prev then
                data.zone = data.zone or prev.zone
                data.item = data.item or prev.item
                data.target = data.target or prev.target
                data.count = data.count or prev.count
                data.hint = data.hint or prev.hint
                data.remaining = data.remaining or prev.remaining
            end
        end
        cfg.dailies[npc] = data
        save()
        return
    end

    if zone == P.ZONE_PORT_JEUNO then
        local named, single = P.read_aether(clean)
        if named == nil then
            return
        end
        -- The name as he wrote it when the client knows it, else the singular.
        local item = lookup_item_id(named) and named or single
        -- Hearing the special again after the turn-in leaves it done.
        local prev = cfg.aether
        if type(prev) == 'table' and prev.completed and prev.item == item then
            return
        end
        cfg.aether = { item = item, deadline = week_deadline() }
        save()
        return
    end

    if P.is_lumoria(zone) then
        local found = P.read_palalumin(clean, cfg.palalumin_quests)
        if not found then
            return
        end
        cfg.palalumin_flagged = true
        for name, row in pairs(found) do
            cfg.palalumin_quests[name] = row
        end
        save()
    end
end

-- A stored congratulations line is the same finish as "quest complete",
-- including rows saved before that line set a status.
function dailies.is_complete(row)
    if type(row) ~= 'table' then
        return false
    end
    if row.status == 'complete' then
        return true
    end
    local message = row.message
    return type(message) == 'string' and message:lower():find('congratulat', 1, true) ~= nil
end

-- Chat summary. Same words the Goldilox command printed.
local function goblin_status(npc, row)
    if row == nil then
        return nil
    end
    if dailies.is_complete(row) then
        return 'Complete!'
    end
    if row.status == 'return' then
        return 'Return to ' .. npc .. '.'
    end
    if npc == 'Fishstix' and row.zone then
        return 'Secret chest at ' .. row.zone
    end
    if npc == 'Murdox' and row.count and row.target and row.zone then
        local remaining = row.remaining or row.count
        return 'Kill ' .. remaining .. ' more ' .. row.target .. ' at ' .. row.zone
            .. ' (' .. row.count .. ' total)'
    end
    if npc == 'Mistrix' and row.item then
        return 'Trade a signed ' .. row.item
    end
    if npc == 'Saltlix' and row.target and row.zone then
        return 'Kill ' .. row.target .. ' at ' .. row.zone
    end
    if npc == 'Beetrix' and row.item and row.zone then
        return 'Trade ' .. row.item .. ' found at ' .. row.zone
    end
    return row.message
end

local function pala_status(name, row)
    if row == nil or row.completed then
        return nil
    end
    if name == 'Find flux' and row.zone then
        return 'Find flux in ' .. row.zone
    end
    if name == 'Item request' and row.items then
        return 'Trade ' .. row.items
    end
    if name == 'Defeat mobs' and row.total and row.killed and row.target and row.zone then
        return 'Kill ' .. (row.total - row.killed) .. ' more ' .. row.target .. ' at ' .. row.zone
            .. ' (' .. row.total .. ' total)'
    end
    return row.message
end

function dailies.goblin_line(npc, row)
    return goblin_status(npc, row)
end

function dailies.pala_line(name, row)
    return pala_status(name, row)
end

-- nil hides the button. 'ready' can be clicked. 'wait' and 'blocked' are
-- gray, and 'blocked' also returns why the owned items cannot go.
function dailies.trade_button(npc, items)
    return trade.button(npc, items)
end

-- The row a turn-in to npc is for, while it is still open.
local function open_request(npc)
    if cfg == nil then
        return nil
    end
    if npc == 'Palalumin' then
        local row = cfg.palalumin_quests and cfg.palalumin_quests['Item request']
        if type(row) == 'table' and not row.completed then
            return row
        end
    elseif npc == 'Beetrix' then
        local row = cfg.dailies and cfg.dailies.Beetrix
        if type(row) == 'table' and not dailies.is_complete(row) then
            return row
        end
    elseif npc == P.AETHER_NPC then
        local row = cfg.aether
        if type(row) == 'table' and not row.completed then
            return row
        end
    end
    return nil
end

function dailies.trade_start(npc, items)
    if not open_request(npc) then
        return false
    end
    return trade.start(npc, items)
end

-- One attempt per frame. Once the npc keeps the items, the request is
-- complete and its row leaves the panel. A turn-in sent to Palalumin also
-- arms the flag a hand-traded 0x036 does, so "Quest Completed" can still
-- close the row. A click does not target Palalumin, so that line counts with
-- anything targeted.
function dailies.trade_update()
    local result, npc = trade.update()
    if result == 'sent' and npc == 'Palalumin' then
        recent_trade = true
        button_trade = true
    elseif result == 'traded' then
        local row = open_request(npc)
        if row then
            if npc == 'Beetrix' then
                row.status = 'complete'
            else
                row.completed = true
            end
            save()
        end
    end
end

local function report_palalumin()
    if not cfg.palalumin_flagged then
        return
    end
    local flagged = 0
    local known = 0
    local rows = cfg.palalumin_quests or {}
    for _, name in ipairs(P.PALALUMIN_ORDER) do
        local row = rows[name]
        if row then
            known = known + 1
        end
        if row and not row.completed then
            flagged = flagged + 1
            if flagged == 1 then
                print(chat.header(addon.name) .. 'Palalumin quests:')
            end
            local line = pala_status(name, row)
            if line then
                print(chat.header(addon.name) .. '\129\158 ' .. P.strip(line))
            end
        end
    end
    if flagged == 0 and known < #P.PALALUMIN_ORDER then
        print(chat.header(addon.name) .. 'Palalumin quests active.')
    end
end

function dailies.report()
    if cfg == nil then
        return
    end
    dailies.roll_day()
    local completed = 0
    for _, npc in ipairs(P.GOBLIN_ORDER) do
        local row = cfg.dailies[npc]
        local preamble = chat.header(addon.name) .. npc .. ': '
        if row == nil then
            print(preamble .. chat.color1(68, 'Not talked to today.'))
        elseif dailies.is_complete(row) then
            print(preamble .. chat.color1(72, 'Complete!'))
            completed = completed + 1
        elseif row.status == 'return' then
            print(preamble .. chat.color1(2, 'Return to ' .. npc .. '.'))
        else
            local line = goblin_status(npc, row)
            if line then
                print(preamble .. P.strip(line))
            end
        end
    end
    if completed > 0 then
        local preamble = chat.header(addon.name) .. 'Goldilox: '
        if cfg.goldilox_time == cfg.deadline then
            print(preamble .. chat.color1(72, 'Complete!'))
        else
            print(preamble .. chat.color1(68, 'Reward not collected.'))
        end
    end
    report_palalumin()
    local aether = cfg.aether
    if type(aether) == 'table' and not aether.completed then
        print(chat.header(addon.name) .. P.AETHER_NPC .. ': Trade ' .. tostring(aether.item) .. ' x' .. P.AETHER_COUNT)
    end
end

return dailies
