--[[
Tracker - one AMAN training regime.

The tome's chat lines build the target list. A death message only names the
mob; message 558, which follows it, is the server's own "Progress: N/M".
Deaths queue so one area attack that kills two targets still files each
progress number on the mob it belongs to.
]]

local chat = require('chat')
local settingslib = require('settings')
local parser = require('lib.parser')
local match = require('lib.match')

local regime = {}

-- A 558 follows its death message in the same burst. Longer than that, the
-- queued name belongs to someone else's kill.
local PENDING_TTL = 3

local MESSAGES = {
    START_PROMPT = "has been placed here by the Adventurers' Mutual Aid Network %(A%.M%.A%.N%.%)",
    TRAINING_START = 'The information on this page instructs you to defeat the following:',
    REGIME_CONFIRMED = 'New training regime registered!',
    REGIME_CANCELED = 'Training regime canceled%.',
}

local cfg
local on_confirm
local state = {
    is_active = false,
    is_parsing = false,
    enemies = {},
    target_level_range = nil,
    training_area_zone = nil,
    got_enemies = false,
    pending = {},
}
local debug_on = false

local function printf(fmt, ...)
    print(chat.header(addon.name) .. chat.message(fmt:format(...)))
end

local function save()
    if cfg == nil then
        return
    end
    cfg.is_active = state.is_active and true or false
    cfg.enemies = state.enemies
    cfg.target_level_range = state.target_level_range
    cfg.training_area_zone = state.training_area_zone
    cfg.ui_mode = nil
    settingslib.save()
end

local function wipe()
    state.is_active = false
    state.is_parsing = false
    state.enemies = {}
    state.target_level_range = nil
    state.training_area_zone = nil
    state.got_enemies = false
    state.pending = {}
    if cfg ~= nil then
        cfg.enemies = state.enemies
    end
    save()
end

-- A new tome page replaces whatever regime was saved, then parsing begins.
local function start_parsing()
    wipe()
    state.is_active = true
    state.is_parsing = true
end

local function take_level(text)
    local level = parser.parse_level_range(text)
    if not level then
        return false
    end
    state.target_level_range = level
    state.is_parsing = false
    return true
end

local function take_enemies(text)
    if state.got_enemies then
        return
    end
    state.got_enemies = true
    local enemies = parser.parse_enemies(text)
    for _, enemy in ipairs(enemies) do
        state.enemies[#state.enemies + 1] = enemy
    end
end

local function take_zone(text)
    if state.is_parsing or not state.target_level_range or state.training_area_zone then
        return false
    end
    local zone = parser.parse_training_area(text)
    if not zone then
        return false
    end
    state.training_area_zone = zone
    return true
end

local function confirm()
    local parts = {}
    for _, enemy in ipairs(state.enemies) do
        parts[#parts + 1] = string.format('%d %s', enemy.total or 0, enemy.name or '')
    end
    printf('Training regime confirmed!')
    printf('Active Training: %s in %s (Level %s)',
        #parts > 0 and table.concat(parts, ', ') or 'Unknown',
        state.training_area_zone or 'Unknown',
        state.target_level_range or 'Unknown')
    save()
    if on_confirm then
        on_confirm()
    end
end

local function prune(now)
    local pending = state.pending
    while pending[1] and (now - pending[1].at) > PENDING_TTL do
        table.remove(pending, 1)
    end
end

local HANDLERS = {
    { pattern = MESSAGES.START_PROMPT, needs_active = false, fn = function()
        state.is_active = true
    end },
    { pattern = MESSAGES.TRAINING_START, needs_active = true, fn = start_parsing },
    { pattern = MESSAGES.REGIME_CONFIRMED, needs_active = true, fn = confirm },
    { pattern = MESSAGES.REGIME_CANCELED, needs_active = true, fn = wipe },
}

function regime.set_on_confirm(fn)
    on_confirm = fn
end

function regime.bind(saved)
    cfg = saved
    state.is_active = saved.is_active and true or false
    if type(saved.enemies) ~= 'table' then
        saved.enemies = {}
    end
    state.enemies = saved.enemies
    state.target_level_range = saved.target_level_range
    state.training_area_zone = saved.training_area_zone
    state.is_parsing = false
    state.got_enemies = false
    state.pending = {}
    return state.is_active and #state.enemies > 0
end

function regime.view()
    return state
end

function regime.clear()
    wipe()
end

function regime.debugging()
    return debug_on
end

function regime.toggle_debug()
    debug_on = not debug_on
    return debug_on
end

function regime.on_text(raw, stripped)
    raw = raw or ''
    stripped = stripped or raw
    for _, spec in ipairs(HANDLERS) do
        if string.find(raw, spec.pattern) then
            if not spec.needs_active or state.is_active then
                spec.fn(stripped)
                return true
            end
        end
    end
    if not state.is_active then
        return false
    end
    if state.is_parsing then
        if take_level(stripped) then
            return true
        end
        take_enemies(stripped)
        return true
    end
    if take_zone(stripped) then
        return true
    end
    return false
end

function regime.on_defeat(target_name)
    if not state.is_active or not target_name then
        return
    end
    if not match.find(state.enemies, target_name) then
        return
    end
    local now = os.time()
    prune(now)
    state.pending[#state.pending + 1] = { name = target_name, at = now }
end

-- 558's numbers are absolute. They land on the oldest death still in the queue.
function regime.on_progress(current)
    if not state.is_active then
        return
    end
    prune(os.time())
    local defeat = table.remove(state.pending, 1)
    if not defeat then
        return
    end
    local enemy = match.find(state.enemies, defeat.name)
    if not enemy then
        return
    end
    enemy.killed = current
    save()
end

function regime.on_complete()
    if state.is_active then
        printf('Training regime completed!')
    end
end

function regime.on_reset()
    if not state.is_active then
        return
    end
    for _, enemy in ipairs(state.enemies) do
        enemy.killed = 0
    end
    state.pending = {}
    save()
end

-- Kills only count in the regime's zone. When the zone is unknown, keep
-- recording: dropping an engagement is worse than reading a few extra packets.
function regime.in_area()
    if not state.is_active then
        return false
    end
    if not state.training_area_zone then
        return true
    end
    local party = AshitaCore:GetMemoryManager():GetParty()
    local resources = AshitaCore:GetResourceManager()
    if not party or not resources then
        return true
    end
    local zone_name = resources:GetString('zones.names', party:GetMemberZone(0))
    return zone_name == nil or zone_name == state.training_area_zone
end

-- /tracker test. Prints one block per tracked row.
function regime.report_match(defeated, printf_fn)
    local say = printf_fn or printf
    if not state.is_active or #state.enemies == 0 then
        say('No active training regime to test against!')
        return
    end
    say('Testing "%s" against %d target(s)', defeated, #state.enemies)
    for i, enemy in ipairs(state.enemies) do
        local kind = match.kind(enemy, defeated)
        local progress = string.format('%d/%d', tonumber(enemy.killed) or 0, tonumber(enemy.total) or 0)
        if kind then
            say('[%d] %s (%s) %s - match: %s', i, enemy.name or '', enemy.match_type or 'legacy', progress, kind)
        else
            say('[%d] %s (%s) %s - no match', i, enemy.name or '', enemy.match_type or 'legacy', progress)
        end
    end
end

return regime
