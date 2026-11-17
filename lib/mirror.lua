--[[
Tracker - one AMAN book pick, repeated on every other box.

The leader's talk to a Field Manual or Grounds Tome (0x01A) and the menu
answers behind it (0x05B) are recorded, and written to the channel file once
the menu closes. Each follower talks to its own copy of the book and sends the
same answers. First built for AMANTracker, from the book path of
DiscipleOfEris's NpcInteract for Windower.

A book is one event. Looking at a page is a 0x05B with byte 0x0E set, which
the server takes as an update and may answer with nothing. The pick is the
0x05B with that byte clear, which ends the event. So the byte is sent as the
leader's client set it, and the answers after the first go out on a timer:
no new menu packet arrives between them to wait for.

The answer is one 32-bit number. Page N is 2 + 16N in every zone at every
level, 0x80000000 is the repeat box, and 0x40000000 alone is backing out.
The packets are copied whole and only the target, zone, and menu id are
rewritten, so all of it carries over.

A follower's client never sees the book. Its answers go straight to the
server, so a menu the client opened would sit at its first question after
the server was done with it. The follower reads the book's menu packet and
blocks it, and blocks the server's page updates (0x05C), as NpcInteract does.

That means the follower never prints the book's text either. Two things the
text gave come another way:
  * A hunt in progress makes the server open a cancel prompt under the book's
    own event: parameters 0, 0, 3 where the book sends 0, page mask, cipher.
    The leader sends its first three, and a follower whose menu differs backs
    out of it.
  * A page pick carries the leader's parsed targets, and the follower's AMAN
    panel takes them once its pick goes through.
]]

local chat = require('chat')
local settingslib = require('settings')
local transport = require('lib.mirror_transport')
local regime = require('lib.regime')

local mirror = {}

local OUT_ACTION = 0x01A
local OUT_CHOICE = 0x05B
local IN_ZONE = { [0x00A] = true, [0x00B] = true }
local IN_EVENT_UPDATE = 0x05C
-- Where each incoming menu packet keeps the npc, its index, the zone, and the
-- menu id. Offsets count from the start of the packet, header included. Only
-- 0x034 carries parameters.
local IN_MENU = {
    [0x032] = { npc = 0x04, index = 0x08, zone = 0x0A, menu = 0x0C, size = 0x10 },
    [0x034] = { npc = 0x04, index = 0x28, zone = 0x2A, menu = 0x2C, size = 0x34, params = 0x08 },
}
-- The first three parameters: 0, page mask, cipher. The fourth is a key item
-- and the rest are the character's own tabs and regime, so they differ by box.
local PARAMS_COMPARED = 12

local ACTION_SIZE = 0x1C
local ACTION_TARGET = 0x04
local ACTION_INDEX = 0x08
local ACTION_CATEGORY = 0x0A
local TALK = 0

local CHOICE_SIZE = 0x14
local CHOICE_TARGET = 0x04
local CHOICE_OPTION = 0x08
local CHOICE_INDEX = 0x0C
local CHOICE_UPDATE = 0x0E
local CHOICE_ZONE = 0x10
local CHOICE_MENU = 0x12
local BACK_OUT = 0x40000000

local STATUS_IDLE = 0
local STATUS_EVENT = 4

local BOOKS = { ['Field Manual'] = true, ['Grounds Tome'] = true }
local BOOK_RANGE = 36 -- GetDistance is squared yalms; 6 yalms
local TICK = 0.05
local MENU_TIMEOUT = 5 -- for the book to open on a follower
local FIRST_DELAY = 0.15 -- between the menu arriving and the first answer
local STEP_DELAY = 0.3 -- between one answer and the next
local FINISH_TIMEOUT = 8 -- for the event to close after the last answer
local CAPTURE_TIMEOUT = 120
local MAX_STEPS = 40
local MAX_TARGETS = 8
local MAX_AGE = 20 -- seconds a follower trusts a record

local cfg = nil
local dump = false
local next_tick = 0
local sequence = 0

-- What the leader is recording, or nil.
local capture = nil
-- What a follower is replaying, or nil.
local replay = nil
-- The last menu packet this client received.
local menu = { id = 0, npc_id = 0, npc_index = 0 }

local function printf(fmt, ...)
    print(chat.header(addon.name) .. chat.message(('Mirror: ' .. fmt):format(...)))
end

local function rd16(s, off)
    local a, b = s:byte(off + 1, off + 2)
    if b == nil then
        return 0
    end
    return a + b * 256
end

local function rd32(s, off)
    local a, b, c, d = s:byte(off + 1, off + 4)
    if d == nil then
        return 0
    end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function put16(s, off, n)
    n = math.floor(n) % 65536
    return s:sub(1, off) .. string.char(n % 256, math.floor(n / 256)) .. s:sub(off + 3)
end

local function put32(s, off, n)
    n = math.floor(n) % 4294967296
    return s:sub(1, off) .. string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    ) .. s:sub(off + 5)
end

local function to_hex(s)
    return (s:gsub('.', function(c)
        return string.format('%02X', c:byte())
    end))
end

local function from_hex(h)
    if type(h) ~= 'string' or #h == 0 or #h % 2 ~= 0 or h:find('%X') then
        return nil
    end
    return (h:gsub('%x%x', function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

local function clean_name(name)
    if type(name) ~= 'string' then
        return ''
    end
    return (name:gsub('%z.*', ''):gsub('%s+$', ''))
end

local function entities()
    local ok, entity = pcall(function()
        return AshitaCore:GetMemoryManager():GetEntity()
    end)
    return ok and entity or nil
end

local function zone_id()
    local ok, zone = pcall(function()
        return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
    end)
    return ok and zone or 0
end

local function level()
    local ok, lv = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel()
    end)
    return ok and tonumber(lv) or 0
end

-- This character's server id, index, and name. Nil before login.
local function self_info()
    local ok, info = pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty()
        local index = party:GetMemberTargetIndex(0)
        if index == nil or index == 0 then
            return nil
        end
        return {
            id = party:GetMemberServerId(0) or 0,
            index = index,
            name = clean_name(party:GetMemberName(0)),
        }
    end)
    return ok and info or nil
end

-- 0 standing idle, 4 inside an npc event. Nil when it cannot be read.
local function status()
    local me = self_info()
    local entity = entities()
    if me == nil or entity == nil then
        return nil
    end
    local ok, value = pcall(entity.GetStatus, entity, me.index)
    return ok and tonumber(value) or nil
end

-- This client's own copy of the book: the nearest one drawn within 6 yalms.
-- The leader may be standing at a different manual in the same zone.
local function find_book(name)
    local entity = entities()
    if entity == nil then
        return nil
    end
    local best = nil
    pcall(function()
        for i = 0, 0x8FF do
            if clean_name(entity:GetName(i)) == name then
                local sid = entity:GetServerId(i)
                local flags = entity:GetRenderFlags0(i)
                local dist = entity:GetDistance(i)
                if sid ~= nil and sid ~= 0 and type(flags) == 'number' and bit.band(flags, 0x200) ~= 0
                    and type(dist) == 'number' and dist <= BOOK_RANGE
                    and (best == nil or dist < best.dist) then
                    best = { id = sid, index = i, dist = dist }
                end
            end
        end
    end)
    return best
end

-- Ashita writes the header, as it does for a trade.
local function send(id, packet)
    packet = string.rep('\0', 4) .. packet:sub(5)
    if dump then
        printf('inject 0x%03X %s', id, to_hex(packet))
    end
    local bytes = {}
    for i = 1, #packet do
        bytes[i] = packet:byte(i)
    end
    return pcall(function()
        AshitaCore:GetPacketManager():AddOutgoingPacket(id, bytes)
    end)
end

-- The menu's compared parameters, or '' for a menu that has none.
local function menu_params(e_id, packet)
    local layout = IN_MENU[e_id]
    if layout == nil or layout.params == nil then
        return ''
    end
    return packet:sub(layout.params + 1, layout.params + PARAMS_COMPARED)
end

-- True when the answer picks a page: 2 + 16N for pages 1 to 10.
local function is_page_pick(raw)
    local option = rd32(raw, CHOICE_OPTION) % 0x80000000
    return option >= 18 and option <= 162 and (option - 2) % 16 == 0
end

-- Targets ride in one hex field: level, area, and rows of total, name, kind.
local function encode_page(page)
    if page == nil then
        return ''
    end
    local rows = {}
    for _, enemy in ipairs(page.enemies) do
        local row = { tonumber(enemy.total) or 0, enemy.name or '', enemy.match_type or 'exact' }
        rows[#rows + 1] = table.concat(row, '\29')
    end
    return to_hex(table.concat({ page.level or '', page.zone or '', table.concat(rows, '\30') }, '\31'))
end

-- Nil when the field is empty, false when it cannot be read.
local function decode_page(field)
    if field == '' then
        return nil
    end
    local text = from_hex(field)
    if text == nil then
        return false
    end
    local lv, area, rows = text:match('^([^\31]*)\31([^\31]*)\31([^\31]*)$')
    if lv == nil then
        return false
    end
    local page = { level = lv ~= '' and lv or nil, zone = area ~= '' and area or nil, enemies = {} }
    for row in (rows .. '\30'):gmatch('([^\30]*)\30') do
        local total, name, kind = row:match('^(%d+)\29([^\29]+)\29([^\29]+)$')
        if total == nil or (kind ~= 'exact' and kind ~= 'family') then
            return false
        end
        page.enemies[#page.enemies + 1] = { total = tonumber(total), name = name, match_type = kind }
    end
    if #page.enemies == 0 or #page.enemies > MAX_TARGETS then
        return false
    end
    return page
end

-- seq|time|leader|zone|level|leader id|book|text seen|menu params|targets|0x01A|0x05B|0x05B...
local function encode(record)
    local parts = {
        record.seq, record.time, (record.leader:gsub('[|\r\n]', ' ')), record.zone, record.level,
        record.self_id, record.book, record.confirmed and 1 or 0,
        record.params ~= '' and to_hex(record.params) or '', encode_page(record.page), to_hex(record.trigger),
    }
    for _, raw in ipairs(record.steps) do
        parts[#parts + 1] = to_hex(raw)
    end
    return table.concat(parts, '|')
end

local function decode(payload)
    local parts = {}
    for part in (payload .. '|'):gmatch('(.-)|') do
        parts[#parts + 1] = part
    end
    if #parts < 12 then
        return nil, 'too few fields'
    end
    local record = {
        seq = tonumber(parts[1]),
        time = tonumber(parts[2]),
        leader = parts[3],
        zone = tonumber(parts[4]),
        level = tonumber(parts[5]),
        self_id = tonumber(parts[6]),
        book = parts[7],
        confirmed = parts[8] == '1',
        params = parts[9] ~= '' and from_hex(parts[9]) or '',
        page = decode_page(parts[10]),
        trigger = from_hex(parts[11]),
        steps = {},
    }
    if not (record.seq and record.time and record.zone and record.level and record.self_id) then
        return nil, 'a number is missing'
    end
    if not BOOKS[record.book] then
        return nil, 'not a book'
    end
    if record.params == nil or (record.params ~= '' and #record.params ~= PARAMS_COMPARED) then
        return nil, 'bad menu parameters'
    end
    if record.page == false then
        return nil, 'bad targets'
    end
    if record.trigger == nil or #record.trigger < ACTION_SIZE then
        return nil, 'bad talk packet'
    end
    for i = 12, #parts do
        local raw = from_hex(parts[i])
        if raw == nil or #raw < CHOICE_SIZE then
            return nil, 'bad answer packet'
        end
        record.steps[#record.steps + 1] = raw
    end
    if #record.steps > MAX_STEPS then
        return nil, 'too many answers'
    end
    return record
end

local function is_leader()
    return cfg ~= nil and cfg.enabled == true and cfg.role == 'leader'
end

local function is_follower()
    return cfg ~= nil and cfg.enabled == true and cfg.role == 'follower'
end

-- The leader's targets when this visit showed a page and picked it.
local function picked_page(done)
    if not is_page_pick(done.steps[#done.steps]) or regime.parses() == done.parses then
        return nil
    end
    local view = regime.view()
    if not view.is_active or type(view.enemies) ~= 'table' or #view.enemies == 0
        or #view.enemies > MAX_TARGETS then
        return nil
    end
    return { level = view.target_level_range, zone = view.training_area_zone, enemies = view.enemies }
end

-- The leader's menu closed. Write the record when it was a pick at a book.
local function finish_capture()
    local done = capture
    capture = nil
    if done == nil or #done.steps == 0 then
        return
    end
    if rd32(done.steps[#done.steps], CHOICE_OPTION) == BACK_OUT then
        if dump then
            printf('backed out of the %s. Nothing to mirror.', done.book)
        end
        return
    end
    if cfg.strict and not done.confirmed then
        printf('the %s never printed its A.M.A.N. line, so nothing was mirrored. '
            .. '"/tracker mirror strict off" drops that check.', done.book)
        return
    end
    local me = self_info()
    sequence = sequence + 1
    local page = picked_page(done)
    local sent = transport.publish(encode({
        seq = sequence,
        time = os.time(),
        leader = me and me.name or '',
        zone = done.zone,
        level = level(),
        self_id = me and me.id or 0,
        book = done.book,
        confirmed = done.confirmed,
        params = done.params or '',
        page = page,
        trigger = done.trigger,
        steps = done.steps,
    }))
    if sent then
        printf('sent %d answer%s from the %s%s.', #done.steps, #done.steps == 1 and '' or 's', done.book,
            page and ' with its targets' or '')
    else
        printf('could not write the channel file (%s).', transport.last_error() or 'unknown error')
    end
end

-- "Back out of this menu", as the client sends it. Ends the event without
-- picking anything.
local function back_out_packet()
    return string.rep('\0', 4)
        .. put32('\0\0\0\0', 0, menu.npc_id)
        .. put32('\0\0\0\0', 0, BACK_OUT)
        .. put16('\0\0', 0, menu.npc_index)
        .. '\0\0'
        .. put16('\0\0', 0, zone_id())
        .. put16('\0\0', 0, menu.id)
end

-- Stop a replay. The client never saw the book, so an event still open on
-- the server is backed out of whatever the client's status reads.
local function abort(fmt, ...)
    if replay == nil then
        return
    end
    local open = replay.open
    printf('stopped at answer %d of %d: ' .. fmt, replay.index, #replay.steps, ...)
    replay = nil
    if open and menu.npc_id ~= 0 then
        send(OUT_CHOICE, back_out_packet())
    end
end

local function start_replay(record)
    local me = self_info()
    if me == nil or record.leader == me.name then
        return
    end
    if (cfg.only or '') ~= '' and record.leader:lower() ~= cfg.only:lower() then
        return
    end
    local age = os.time() - record.time
    if age > MAX_AGE then
        printf('ignored a pick from %s made %d seconds ago.', record.leader, age)
        return
    end
    if replay ~= nil then
        printf('still on the last pick. Ignored a new one from %s.', record.leader)
        return
    end
    if zone_id() ~= record.zone then
        printf('%s picked a page in another zone.', record.leader)
        return
    end
    local now_status = status()
    if now_status ~= STATUS_IDLE then
        printf('busy (status %s). Did not follow %s.', tostring(now_status), record.leader)
        return
    end
    local book = find_book(record.book)
    if book == nil then
        printf('no %s within 6 yalms. Did not follow %s.', record.book, record.leader)
        return
    end
    local mine = level()
    if mine ~= record.level then
        printf('%s is level %d and this character is level %d. '
            .. 'The same page registers, but kills count only inside its level range.',
            record.leader, record.level, mine)
    end
    replay = {
        state = 'pending',
        record = record,
        steps = record.steps,
        index = 1,
        leader = record.leader,
        book = book,
        trigger = put16(put32(record.trigger, ACTION_TARGET, book.id), ACTION_INDEX, book.index),
        -- Book menus received and blocked since the talk went out.
        menus = 0,
        -- True while the server holds an event this client never saw.
        open = false,
        params = '',
        -- Boxes start a little apart instead of all in one frame.
        at = os.clock() + (me.id % 5) * 0.1,
    }
    printf('following %s: %d answer%s at the %s.', record.leader, #record.steps,
        #record.steps == 1 and '' or 's', record.book)
end

-- The leader's answer, pointed at this client's event.
local function own_choice(raw)
    local me = self_info()
    local record = replay.record
    -- Some menus address the player instead of the npc.
    if me ~= nil and record.self_id ~= 0 and rd32(raw, CHOICE_TARGET) == record.self_id then
        raw = put16(put32(raw, CHOICE_TARGET, me.id), CHOICE_INDEX, me.index)
    elseif menu.npc_id ~= 0 then
        raw = put16(put32(raw, CHOICE_TARGET, menu.npc_id), CHOICE_INDEX, menu.npc_index)
    else
        raw = put16(put32(raw, CHOICE_TARGET, replay.book.id), CHOICE_INDEX, replay.book.index)
    end
    raw = put16(raw, CHOICE_ZONE, zone_id())
    if menu.id ~= 0 then
        raw = put16(raw, CHOICE_MENU, menu.id)
    end
    return raw
end

-- A different menu id is a different menu. The leader's answers mean
-- something else there, so none are sent.
local function same_menu()
    local expected = rd16(replay.steps[replay.index], CHOICE_MENU)
    if expected ~= 0 and menu.id ~= 0 and menu.id ~= expected then
        abort('this menu is %d and %s answered menu %d.', menu.id, replay.leader, expected)
        return false
    end
    return true
end

-- A hunt in progress opens a cancel prompt under the book's own menu id.
-- Its parameters are not the book's, so strict backs out of it.
local function same_params()
    local theirs = replay.record.params
    if not cfg.strict or theirs == '' or replay.params == '' or replay.params == theirs then
        return true
    end
    abort('the %s opened a different menu than %s\'s did. A hunt in progress opens one.',
        replay.record.book, replay.leader)
    return false
end

local function step_replay(now)
    if replay.state == 'pending' then
        if now < replay.at then
            return
        end
        replay.state = 'wait_menu'
        replay.deadline = now + MENU_TIMEOUT
        send(OUT_ACTION, replay.trigger)
    elseif replay.state == 'wait_menu' then
        if replay.menus > 0 then
            if same_menu() and same_params() then
                replay.state = 'answer'
                replay.at = now + FIRST_DELAY
            end
        elseif now > replay.deadline then
            abort('the book never opened.')
        end
    elseif replay.state == 'answer' then
        if now < replay.at or not same_menu() then
            return
        end
        local raw = replay.steps[replay.index]
        send(OUT_CHOICE, own_choice(raw))
        -- An update leaves the event open. Anything else ends it.
        replay.open = raw:byte(CHOICE_UPDATE + 1) ~= 0
        if replay.index < #replay.steps then
            replay.index = replay.index + 1
            replay.at = now + STEP_DELAY
        else
            replay.state = 'finish'
            replay.mark = replay.menus
            replay.deadline = now + FINISH_TIMEOUT
        end
    elseif replay.state == 'finish' then
        if replay.menus > replay.mark then
            abort('another menu opened after the last answer %s gave.', replay.leader)
        elseif status() == STATUS_IDLE then
            local page = replay.record.page
            printf('followed %s.', replay.leader)
            replay = nil
            if page ~= nil then
                regime.adopt(page)
            end
        elseif now > replay.deadline then
            abort('the menu never closed.')
        end
    end
end

--- Take the character's saved mirror settings. Called again on each login.
function mirror.bind(saved)
    if type(saved.mirror) ~= 'table' then
        saved.mirror = T{}
    end
    cfg = saved.mirror
    if cfg.enabled == nil then
        cfg.enabled = false
    end
    if cfg.role ~= 'follower' then
        cfg.role = 'leader'
    end
    if cfg.strict == nil then
        cfg.strict = true
    end
    cfg.only = type(cfg.only) == 'string' and cfg.only or ''
    capture = nil
    replay = nil
    transport.prime()
end

--- The book's "placed here by the A.M.A.N." line was printed. Only the
--- leader sees it: a follower's book never opens on its screen.
function mirror.on_tome_text()
    if capture ~= nil then
        capture.confirmed = true
    end
end

--- Outgoing packets: the leader's own talk and answers. Injected packets are
--- skipped, so a follower never sends on what it replayed.
function mirror.on_packet_out(e)
    if e.injected or e.blocked or not is_leader() then
        return
    end
    if e.id ~= OUT_ACTION and e.id ~= OUT_CHOICE then
        return
    end
    local packet = e.data_modified or e.data
    if type(packet) ~= 'string' then
        return
    end
    if type(e.size) == 'number' then
        packet = packet:sub(1, e.size)
    end
    if e.id == OUT_ACTION then
        -- Only a talk is recorded. A trade or an attack is never mirrored.
        if #packet < ACTION_SIZE or rd16(packet, ACTION_CATEGORY) ~= TALK then
            return
        end
        capture = nil
        local index = rd16(packet, ACTION_INDEX)
        local entity = entities()
        local ok, name = pcall(function()
            return clean_name(entity:GetName(index))
        end)
        if not ok or not BOOKS[name] then
            return
        end
        capture = {
            at = os.clock(),
            book = name,
            target = rd32(packet, ACTION_TARGET),
            zone = zone_id(),
            trigger = packet,
            steps = {},
            confirmed = false,
            in_event = false,
            params = nil,
            parses = regime.parses(),
        }
        if dump then
            printf('talk to the %s (id %d, index %d) %s', name, capture.target, index, to_hex(packet))
        end
    elseif capture ~= nil and #packet >= CHOICE_SIZE then
        if #capture.steps >= MAX_STEPS then
            printf('more than %d answers in one visit. Nothing will be mirrored.', MAX_STEPS)
            capture = nil
            return
        end
        capture.steps[#capture.steps + 1] = packet
        if dump then
            printf('answer %d option 0x%08X menu %d %s', #capture.steps, rd32(packet, CHOICE_OPTION),
                rd16(packet, CHOICE_MENU), to_hex(packet))
        end
    end
end

--- Incoming packets: the menu this client was just sent, and zoning. A
--- follower's book menu and page updates are blocked here.
function mirror.on_packet_in(e)
    if cfg == nil or not cfg.enabled then
        return
    end
    local layout = IN_MENU[e.id]
    if layout ~= nil then
        local packet = e.data_modified or e.data
        if type(packet) ~= 'string' or #packet < layout.size then
            return
        end
        menu.npc_id = rd32(packet, layout.npc)
        menu.npc_index = rd16(packet, layout.index)
        menu.id = rd16(packet, layout.menu)
        local params = menu_params(e.id, packet)
        if dump then
            printf('menu 0x%03X npc %d index %d zone %d menu %d params %s', e.id, menu.npc_id, menu.npc_index,
                rd16(packet, layout.zone), menu.id, params ~= '' and to_hex(params) or 'none')
        end
        if capture ~= nil and capture.params == nil and menu.npc_id == capture.target then
            capture.params = params
        end
        if replay ~= nil and replay.state ~= 'pending' and menu.npc_id == replay.book.id then
            e.blocked = true
            replay.menus = replay.menus + 1
            replay.open = true
            replay.params = params
        end
    elseif e.id == IN_EVENT_UPDATE then
        if replay ~= nil and replay.state ~= 'pending' then
            e.blocked = true
        end
    elseif IN_ZONE[e.id] then
        if replay ~= nil then
            printf('zoned while following %s. Stopped.', replay.leader)
        end
        replay = nil
        capture = nil
        menu.id, menu.npc_id, menu.npc_index = 0, 0, 0
    end
end

--- Each frame: close out the leader's recording, or read the channel and
--- move a follower's replay along.
function mirror.tick()
    if cfg == nil or not cfg.enabled then
        return
    end
    local now = os.clock()
    if now < next_tick then
        return
    end
    next_tick = now + TICK
    if is_leader() then
        if capture ~= nil then
            local now_status = status()
            if now_status == STATUS_EVENT then
                capture.in_event = true
            elseif capture.in_event and now_status == STATUS_IDLE then
                finish_capture()
            elseif now - capture.at > CAPTURE_TIMEOUT then
                capture = nil
            end
        end
        return
    end
    if not is_follower() then
        return
    end
    local payload = transport.poll()
    if payload ~= nil then
        local record, why = decode(payload)
        if record ~= nil then
            start_replay(record)
        else
            printf('ignored a record it could not read (%s).', why)
        end
    end
    if replay ~= nil then
        step_replay(now)
    end
end

local function report()
    printf('%s, %s, strict %s, following %s', cfg.enabled and 'on' or 'off', cfg.role,
        cfg.strict and 'on' or 'off', cfg.only ~= '' and cfg.only or 'any leader')
    printf('channel %s', transport.path())
    if transport.last_error() then
        printf('last write failed: %s', transport.last_error())
    end
    if replay ~= nil then
        printf('following %s, answer %d of %d (%s)', replay.leader, replay.index, #replay.steps, replay.state)
    end
end

local function help()
    printf('pick an AMAN page on one box and the others pick it too.')
    printf('  /tracker mirror               Show status')
    printf('  /tracker mirror on|off        Turn it on for this character. Off by default')
    printf('  /tracker mirror leader        Send this character\'s picks. Never follow')
    printf('  /tracker mirror follower      Follow the leader\'s picks. Never send')
    printf('  /tracker mirror only <name>   Follow only <name>. "any" follows every leader')
    printf('  /tracker mirror strict on|off Check it is the book\'s own menu on both boxes. On by default')
    printf('  /tracker mirror stop          Stop following the current pick')
    printf('  /tracker mirror dump          Toggle packet logging')
end

local function on_off(value, current)
    value = string.lower(value or '')
    if value == 'on' then
        return true
    elseif value == 'off' then
        return false
    end
    return not current
end

--- 'off', 'leader', or 'follower': what the window's setting shows.
function mirror.mode()
    if cfg == nil or not cfg.enabled then
        return 'off'
    end
    return cfg.role
end

--- Set all of it at once, and save. 'off' keeps the role for next time.
function mirror.set_mode(mode)
    if cfg == nil or (mode ~= 'off' and mode ~= 'leader' and mode ~= 'follower') then
        return false
    end
    if mode == mirror.mode() then
        return true
    end
    cfg.enabled = mode ~= 'off'
    if cfg.enabled then
        cfg.role = mode
        transport.prime()
    end
    capture = nil
    replay = nil
    settingslib.save()
    return true
end

--- /tracker mirror. The subcommand is args[3].
function mirror.command(args)
    if cfg == nil then
        printf('settings are not loaded yet.')
        return
    end
    local sub = string.lower(args[3] or '')
    if sub == '' or sub == 'status' then
        report()
    elseif sub == 'on' or sub == 'off' then
        cfg.enabled = sub == 'on'
        capture = nil
        replay = nil
        if cfg.enabled then
            transport.prime()
        end
        settingslib.save()
        printf('%s (%s).', cfg.enabled and 'on' or 'off', cfg.role)
    elseif sub == 'leader' or sub == 'follower' then
        cfg.role = sub
        capture = nil
        replay = nil
        transport.prime()
        settingslib.save()
        if sub == 'leader' then
            printf('leader. This character sends its picks and never follows.')
        else
            printf('follower. This character follows picks and never sends.')
        end
    elseif sub == 'only' then
        local name = args[4] or ''
        cfg.only = (name == '' or name:lower() == 'any') and '' or name
        settingslib.save()
        printf('following %s.', cfg.only ~= '' and ('only ' .. cfg.only) or 'any leader')
    elseif sub == 'strict' then
        cfg.strict = on_off(args[4], cfg.strict)
        settingslib.save()
        printf('strict %s.', cfg.strict and 'on' or 'off')
    elseif sub == 'stop' then
        if replay == nil then
            printf('nothing to stop.')
        else
            abort('stopped by command.')
        end
    elseif sub == 'dump' then
        dump = not dump
        printf('packet logging %s.', dump and 'on' or 'off')
    else
        help()
    end
end

return mirror
