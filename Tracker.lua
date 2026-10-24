--[[
Tracker
Goblin dailies, Palalumin quests, the Aether Traveler's week, and AMAN
training regimes.
Copyright (c) 2026 Seekey
https://github.com/seekey13/Tracker

Ashita v4. CatsEye XI only.
]]

addon.name = 'Tracker'
addon.author = 'Seekey'
addon.version = '1.0'
addon.desc = 'Keeps track of dailies and AMAN targets.  Exclusively for CatsEye XI.'
addon.link = 'https://github.com/seekey13/Tracker'

require('common')
local chat = require('chat')
local settings = require('settings')
local dailies = require('lib.dailies')
local regime = require('lib.regime')
local packets = require('lib.packets')
local parse = require('lib.daily_parse')
local ui = require('lib.ui')

local function printf(fmt, ...)
    print(chat.header(addon.name) .. chat.message(fmt:format(...)))
end

local defaults = T{
    opacity = 100,
    scale = 1,
    migrated = false,
    offset = 60 * 60 * 9,
    deadline = 0,
    version = 1,
    dailies = T{},
    palalumin_quests = T{},
    palalumin_flagged = false,
    is_active = false,
    enemies = T{},
    target_level_range = nil,
    training_area_zone = nil,
}

local DAILY_KEYS = {
    'offset', 'deadline', 'version', 'dailies', 'palalumin_quests', 'palalumin_flagged', 'goldilox_time',
}
local REGIME_KEYS = {
    'is_active', 'enemies', 'target_level_range', 'training_area_zone',
}

local function character_dir()
    local path = settings.settings_path() or ''
    return path:match('\\([^\\]+)\\?$')
end

local function read_settings(path)
    local probe = io.open(path, 'rb')
    if probe == nil then
        return nil
    end
    probe:close()
    local chunk = loadfile(path)
    if chunk == nil then
        return nil
    end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= 'table' then
        return nil
    end
    return data
end

local function unused(saved)
    if saved.is_active then
        return false
    end
    if saved.palalumin_flagged then
        return false
    end
    if type(saved.dailies) == 'table' then
        for _ in pairs(saved.dailies) do
            return false
        end
    end
    if type(saved.enemies) == 'table' and #saved.enemies > 0 then
        return false
    end
    return true
end

-- First launch copies the character's Goldilox-UI and AMANTracker files.
-- A later save sets migrated, so playing Tracker never gets overwritten.
local function migrate(saved)
    if saved.migrated or not unused(saved) then
        saved.migrated = true
        return
    end
    local dir = character_dir()
    if dir == nil or dir == '' or dir == 'defaults' then
        return
    end
    if AshitaCore == nil or AshitaCore.GetInstallPath == nil then
        return
    end
    local root = AshitaCore:GetInstallPath()
    local function take(addon_dir, keys)
        local data = read_settings(root .. '\\config\\addons\\' .. addon_dir .. '\\' .. dir .. '\\settings.lua')
        if type(data) ~= 'table' then
            return
        end
        for _, key in ipairs(keys) do
            if data[key] ~= nil then
                saved[key] = data[key]
            end
        end
    end
    take('Goldilox-UI', DAILY_KEYS)
    take('AMANTracker', REGIME_KEYS)
    saved.ui_mode = nil
    saved.migrated = true
    settings.save()
end

local function adopt(saved)
    if saved == nil then
        return
    end
    migrate(saved)
    dailies.bind(saved)
    local restored = regime.bind(saved)
    dailies.roll_day()
    if restored then
        ui.open()
        printf('Restored active hunt from saved data')
    end
end

settings.register('settings', 'tracker_settings', function(saved)
    if saved ~= nil then
        adopt(saved)
    end
end)
settings.load(defaults)

regime.set_on_confirm(function()
    ui.open()
end)

packets.init({
    on_defeat = function(name)
        regime.on_defeat(name)
    end,
    on_progress = function(current)
        regime.on_progress(current)
    end,
    on_regime_complete = function()
        regime.on_complete()
    end,
    on_regime_reset = function()
        regime.on_reset()
    end,
    should_record_engagements = function()
        return regime.in_area()
    end,
    on_debug = function(fmt, ...)
        if regime.debugging() then
            printf(fmt, ...)
        end
    end,
})

local function plain(message)
    message = message or ''
    -- Ashita's string:strip_colors() drops one byte after 0x1E, 0x1F, or 0x7F.
    -- That is the strip the AMAN tome parser was written against.
    if type(message) == 'string' then
        local ok, stripped = pcall(function()
            return message:strip_colors()
        end)
        if ok and type(stripped) == 'string' then
            return stripped
        end
    end
    return parse.strip(message)
end

local function help()
    printf('Tracker commands:')
    printf('  /tracker             Show this help')
    printf('  /tracker ui          Show or hide the window')
    printf('  /tracker dailies     Print goblin, Palalumin, and Aether Traveler status')
    printf('  /tracker clear       Clear the AMAN regime')
    printf('  /tracker debug       Toggle death-packet logging')
    printf('  /tracker test <name> Test an enemy name against the regime')
    printf('Hold Shift to drag. The frame fades until the mouse is over the window. The cog scales it. The x closes it.')
    printf('/at, /goldilox and /dailies still work.')
end

local function on_command(args)
    local cmd = string.lower(args[1] or '')
    local sub = string.lower(args[2] or '')
    if cmd ~= '/tracker' and cmd ~= '/at' and cmd ~= '/goldilox' and cmd ~= '/dailies' then
        return false
    end
    if cmd == '/goldilox' or cmd == '/dailies' then
        if sub == 'ui' then
            ui.toggle()
            printf('UI %s', ui.visible() and 'opened' or 'closed')
        else
            dailies.report()
        end
        return true
    end
    if sub == '' or sub == 'help' then
        help()
    elseif sub == 'ui' then
        ui.toggle()
        printf('UI %s', ui.visible() and 'opened' or 'closed')
    elseif sub == 'clear' then
        regime.clear()
        printf('Training data cleared and saved.')
    elseif sub == 'debug' then
        local on = regime.toggle_debug()
        printf('Death packet logging %s', on and 'enabled' or 'disabled')
    elseif sub == 'test' then
        if args[3] == nil or args[3] == '' then
            printf('Usage: /tracker test <enemy name>')
        else
            regime.report_match(table.concat(args, ' ', 3), printf)
        end
    elseif sub == 'dailies' then
        dailies.report()
    else
        help()
    end
    return true
end

ashita.events.register('load', 'tracker_load', function()
    ui.bake()
end)

ashita.events.register('text_in', 'tracker_text_in', function(e)
    if e.injected then
        return
    end
    dailies.on_text(e)
    regime.on_text(e.message, plain(e.message))
end)

ashita.events.register('packet_in', 'tracker_packet_in', function(e)
    packets.handle_incoming_packet(e)
end)

ashita.events.register('packet_out', 'tracker_packet_out', function(e)
    if e.id == 0x0036 then
        dailies.on_trade()
    end
end)

ashita.events.register('command', 'tracker_command', function(e)
    local args = e.command:args()
    if args == nil or #args == 0 then
        return
    end
    if on_command(args) then
        e.blocked = true
    end
end)

ashita.events.register('d3d_present', 'tracker_present', function()
    dailies.roll_day()
    ui.render()
    dailies.trade_update()
end)

ashita.events.register('key', 'tracker_key', function(e)
    if e.wparam == 0x10 then
        ui.shift_held = not (bit.band(e.lparam, bit.lshift(0x8000, 0x10)) == bit.lshift(0x8000, 0x10))
    end
end)

ashita.events.register('unload', 'tracker_unload', function()
    settings.save()
end)

return {
    on_command = on_command,
}
