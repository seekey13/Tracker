--[[
Tracker - CatsEye daily text.

Goblins in Lower Jeuno and Palalumin in Lumoria announce the day's work in
NPC chat (mode 9). The Aether Traveler in Port Jeuno names the week's item
there too. Kill counts, turn-ins, and the Goldilox dice roll arrive
as system lines (mode 121). A /huh motion reply can arrive on any mode.
The patterns are the ones Goldilox matched against the live server.
]]

local P = {}

P.GOBLIN_ORDER = { 'Fishstix', 'Murdox', 'Mistrix', 'Saltlix', 'Beetrix' }
P.PALALUMIN_ORDER = { 'Find flux', 'Item request', 'Defeat mobs' }

P.ZONE_ALTAIEU = 33
P.ZONE_HUXZOI = 34
P.ZONE_RUHMET = 35
P.ZONE_LOWER_JEUNO = 245
P.ZONE_PORT_JEUNO = 246

P.AETHER_NPC = 'Aether Traveler'
P.AETHER_COUNT = 3
P.AETHER_FRAGMENT_ID = 2999

function P.is_lumoria(zone)
    return zone == P.ZONE_ALTAIEU or zone == P.ZONE_HUXZOI or zone == P.ZONE_RUHMET
end

function P.strip(s)
    s = tostring(s or '')
    s = s:gsub('\x1E.-\x1E', ''):gsub('\x1F.-\x1F', '')
    s = s:gsub('\30.', ''):gsub('\31.', '')
    return s
end

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

-- "You sense a secret chest is far in the North direction!" -> "Far North"
function P.chest_hint(text)
    local distance, direction = string.match(P.strip(text), 'You sense a secret chest is (.+) in the (.+) direction')
    if not distance or not direction then
        return nil
    end
    local titled = distance:sub(1, 1):upper() .. distance:sub(2):lower()
    return titled .. ' ' .. direction
end

local function apply_goblin(npc, data, prev)
    local message = data.message or ''
    if npc == 'Fishstix' then
        local zone = string.match(message, 'Go to (.-),')
        if zone then data.zone = zone end
    elseif npc == 'Murdox' then
        local count = string.match(message, 'kill (%d+)')
        local target = string.match(message, '%d+ (.+)!')
        local zone = string.match(message, 'Go to (.+) and')
        if count then data.count = count end
        if target then data.target = target end
        if zone then data.zone = zone end
        if prev and prev.remaining then
            data.remaining = prev.remaining
        end
    elseif npc == 'Mistrix' then
        local item = string.match(message, 'Craft me up %a+ signed (.+) and trade it to me!')
        if item then data.item = item end
    elseif npc == 'Saltlix' then
        local target = string.match(message, 'kill (.+)!')
        local zone = string.match(message, 'Go to (.+) and')
        if target then data.target = target end
        if zone then data.zone = zone end
    elseif npc == 'Beetrix' then
        local zone = string.match(message, 'Go to (.-),')
        local item = string.match(message, 'get %a+ (.+) and trade')
        if zone then data.zone = zone end
        if item then data.item = item end
    end
end

local GOBLINS = {}
for _, name in ipairs(P.GOBLIN_ORDER) do
    GOBLINS[name] = true
end

-- One Jeuno goblin line. `prev` is that goblin's row, so a repeat visit keeps
-- Murdox's remaining count. Returns npc, data or nil.
function P.read_goblin(text, prev)
    local clean = P.strip(text)
    if not clean:match('\n$') then
        clean = clean .. '\n'
    end
    local npc, message = string.match(clean, '.-(%a+).-:.-(%a+.*)\n')
    if message == nil or not GOBLINS[npc] then
        return nil
    end
    local data = { message = message }
    apply_goblin(npc, data, prev)
    return npc, data
end

-- Mode 121, in the order Goldilox tested them. First hit wins.
function P.read_system(text)
    local message = P.strip(text)
    local return_npc = string.match(message, 'please return to (%a+) to claim your reward')
    if return_npc then
        return { kind = 'return', npc = return_npc }
    end

    local complete_npc = string.match(message, '(%a+).*quest complete')
    if complete_npc and GOBLINS[complete_npc] then
        return { kind = 'complete', npc = complete_npc }
    end

    local kills, mob, zone = string.match(message, '(%d+) kills remain%..-%((.+) in (.+)%)')
    if kills then
        return { kind = 'murdox', kills = kills, mob = mob, zone = zone }
    end

    local pala_killed, pala_total, pala_target, pala_zone =
        string.match(message, 'Defeat Mobs (%d+)/(%d+) %((.+) in (.+)%)')
    if pala_killed then
        return {
            kind = 'pala_kills',
            killed = tonumber(pala_killed),
            total = tonumber(pala_total),
            target = pala_target,
            zone = pala_zone,
        }
    end

    if string.match(message, 'Quest Completed') then
        return { kind = 'quest_completed' }
    end

    if string.match(message, 'Dice roll!.*rolls.*%(.*%)') then
        return { kind = 'dice' }
    end

    return nil
end

local function pala_fields(name, objective, completed)
    local data = { message = objective }
    if completed or objective:lower() == 'completed' then
        data.completed = true
    end
    -- Find flux and the item list keep the raw objective, including "Completed".
    -- Defeat mobs skips the count parse once the row is already done.
    if name == 'Find flux' then
        data.zone = objective
    elseif name == 'Item request' then
        data.items = objective
    elseif name == 'Defeat mobs' and not data.completed then
        local target, zone, killed, total = string.match(objective, '(.+) %((.+)%) (%d+)/(%d+)')
        data.target = target
        data.zone = zone
        data.killed = tonumber(killed)
        data.total = tonumber(total)
    end
    return data
end

local PALA_NAMES = {}
for _, name in ipairs(P.PALALUMIN_ORDER) do
    PALA_NAMES[name] = true
end

-- Every objective in one Palalumin menu. A later line in the same menu does
-- not reopen a row an earlier line already marked completed. `previous` is
-- the stored quests, so a second pattern cannot undo a finished one.
-- Returns a name -> row map (possibly empty), or nil when the text has no
-- Palalumin objective. An empty map still means the menu was recognised, so
-- the caller can flag the day without rewriting a completed row.
function P.read_palalumin(text, previous)
    local clean = P.strip(text)
    local found = {}
    local saw = false
    previous = type(previous) == 'table' and previous or {}

    local function consider(quest, objective, is_completed)
        if type(quest) ~= 'string' or type(objective) ~= 'string' then
            return
        end
        quest = trim(quest)
        objective = trim(objective)
        if quest == '' or objective == '' or not PALA_NAMES[quest] then
            return
        end
        -- Count the menu even when this line is not allowed to reopen a row.
        saw = true
        local prev = previous[quest] or found[quest]
        if prev and prev.completed and not is_completed then
            return
        end
        found[quest] = pala_fields(quest, objective, is_completed)
    end

    local function scan(pattern, is_completed)
        local start_at = 1
        while true do
            local first, last, quest, objective = string.find(clean, pattern, start_at)
            if not first then
                break
            end
            consider(quest, objective, is_completed)
            start_at = last + 1
        end
    end

    -- Shift-JIS diamonds the FFXI client prints, then the UTF-8 ones.
    scan('\129\159%s+(.-):%s*([^\r\n]+)', true)
    scan('\129\158%s+(.-):%s*([^\r\n]+)', false)
    scan('\226\151\134%s+(.-):%s*([^\r\n]+)', true)
    scan('\226\151\135%s+(.-):%s*([^\r\n]+)', false)

    for _, quest_name in ipairs(P.PALALUMIN_ORDER) do
        if not found[quest_name] then
            -- A diamond menu must not let a bare "Name: objective" inside some
            -- other line replace a quest the diamonds left stored.
            local already = saw and previous[quest_name]
            if not already then
                local objective = string.match(clean, quest_name .. '%s*:%s*([^\r\n]+)')
                if objective then
                    consider(quest_name, objective, trim(objective):lower() == 'completed')
                end
            end
        end
    end

    if not saw then
        return nil
    end
    return found
end

-- "Phuabo Organ x10" -> name, count. A bare name counts as one.
function P.item_need(text)
    local name, count = tostring(text or ''):match('^(.+)%s+x(%d+)$')
    if name and count then
        return trim(name), tonumber(count)
    end
    return trim(text), 1
end

local function title(s)
    return (s:gsub('(%a)([%w\']*)', function(first, rest)
        return first:upper() .. rest
    end))
end

-- "dragon bones" -> "dragon bone". Only the last word is plural.
local function singular(phrase)
    local head, last = phrase:match('^(.-)(%S+)$')
    if last == nil then
        return phrase
    end
    local lower = last:lower()
    if lower:match('[^aeiou]ies$') then
        last = last:sub(1, -4) .. 'y'
    elseif lower:match('[sxz]es$') or lower:match('[cs]hes$') then
        last = last:sub(1, -3)
    elseif lower:match('[^s]s$') then
        last = last:sub(1, -2)
    end
    return head .. last
end

-- "Aether Traveler : Yes... This week I require three dragon bones. Bring
-- them to me and you shall have the fragments." He always asks for three.
-- Returns the item as written and its singular, each in title case, or nil.
function P.read_aether(text)
    local wanted = string.match(P.strip(text), P.AETHER_NPC .. '%s*:.-This week I require (.-)%.%s+Bring')
    if wanted == nil then
        return nil
    end
    wanted = trim(wanted)
    wanted = wanted:match('^%d+%s+(.+)$') or wanted:match('^[Tt]hree%s+(.+)$') or wanted
    if wanted == '' then
        return nil
    end
    return title(wanted), title(singular(wanted))
end

return P
