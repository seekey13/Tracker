--[[
Host checks for Tracker. Ashita does not load this file.
Run: luajit tests\run.lua
     luajit tests\run.lua migrate
]]

local source = (arg and arg[0]) or ''
local root = source:match('^(.*)[\\/]tests[\\/]run%.lua$')
if root == nil or root == '' then
    root = 'R:\\CatsEyeXI\\catseyexi-client\\Vanacore\\addons\\ashita\\Tracker'
end
package.path = root .. '\\?.lua;' .. package.path

local say = print
local fails, checks = 0, 0
local lines = {}

local function fail(msg)
    fails = fails + 1
    io.stderr:write('FAIL ' .. msg .. '\n')
end

local function eq(actual, expected, msg)
    checks = checks + 1
    if actual ~= expected then
        fail(msg .. ' (got ' .. tostring(actual) .. ', expected ' .. tostring(expected) .. ')')
    end
end

local function truthy(value, msg)
    checks = checks + 1
    if not value then
        fail(msg .. ' (got ' .. tostring(value) .. ')')
    end
end

local function finish()
    if fails > 0 then
        say(fails .. ' failed, ' .. checks .. ' checks')
        os.exit(1)
    end
    say('ok ' .. checks .. ' checks')
    os.exit(0)
end

function print(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[i] = tostring(select(i, ...))
    end
    lines[#lines + 1] = table.concat(parts, '\t')
end

local function printed(fragment)
    for _, line in ipairs(lines) do
        if line:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

bit = require('bit')
addon = {}
T = function(t)
    return t or {}
end

local world = {
    zone = 245,
    level = 75,
    target = nil,
    zone_name = 'Garlaige Citadel',
}

function GetEntity()
    if world.target then
        return { Name = world.target }
    end
    return nil
end

AshitaCore = {
    GetInstallPath = function()
        return world.install or 'R:\\CatsEyeXI\\catseyexi-client\\Vanacore'
    end,
    GetMemoryManager = function()
        return {
            GetPlayer = function()
                return {
                    GetMainJobLevel = function()
                        return world.level
                    end,
                }
            end,
            GetParty = function()
                return {
                    GetMemberZone = function()
                        return world.zone
                    end,
                }
            end,
            GetTarget = function()
                return {
                    GetIsSubTargetActive = function()
                        return 0
                    end,
                    GetTargetIndex = function()
                        return 1
                    end,
                }
            end,
            GetInventory = function()
                return nil
            end,
            GetEntity = function()
                return nil
            end,
        }
    end,
    GetResourceManager = function()
        return {
            GetItemByName = function()
                return nil
            end,
            GetString = function()
                return world.zone_name
            end,
        }
    end,
    GetChatManager = function()
        return {
            QueueCommand = function() end,
        }
    end,
}

local settings_path = 'R:\\CatsEyeXI\\catseyexi-client\\Vanacore\\config\\addons\\Tracker\\defaults\\'
local listeners = {}
local saves = 0

local settings = {
    settings_path = function()
        return settings_path
    end,
    register = function(_, _, fn)
        listeners[#listeners + 1] = fn
    end,
    load = function(defaults)
        local saved = {}
        for key, value in pairs(defaults) do
            saved[key] = value
        end
        for _, fn in ipairs(listeners) do
            fn(saved)
        end
        return saved
    end,
    save = function()
        saves = saves + 1
    end,
}

local chat = {
    header = function(name)
        return '[' .. tostring(name) .. '] '
    end,
    message = function(text)
        return text
    end,
    color1 = function(_, text)
        return text
    end,
}

local buttons, texts, drawn = {}, {}, {}
local style_colors, dummies, rects = {}, {}, {}
local title_alpha = nil
local began = 0
local slider_mode = 'idle'
local slider_id = nil

local draw_list = {
    AddLine = function() end,
    AddRect = function() end,
    AddRectFilled = function(_, _, _, col)
        rects[#rects + 1] = col
    end,
    AddTriangleFilled = function() end,
    ChannelsSplit = function() end,
    ChannelsSetCurrent = function() end,
    ChannelsMerge = function() end,
    AddText = function(_, _, col, str)
        if str == 'Tracker' and type(col) == 'number' then
            title_alpha = math.floor(col / 16777216)
        end
        if type(str) == 'string' and #str > 1 then
            drawn[#drawn + 1] = str
        end
    end,
}

local imgui = {
    GetIO = function()
        return { DisplaySize = { y = 1440 } }
    end,
    GetFont = function()
        return {}
    end,
    CalcTextSize = function(str)
        return #tostring(str or '') * 7, 13
    end,
    GetCursorScreenPos = function()
        return 40, 50
    end,
    SetCursorScreenPos = function() end,
    Dummy = function(size)
        dummies[#dummies + 1] = size
    end,
    SameLine = function() end,
    BeginGroup = function() end,
    EndGroup = function() end,
    Spacing = function() end,
    TextColored = function(_, text)
        texts[#texts + 1] = text
    end,
    TextUnformatted = function() end,
    InvisibleButton = function(id)
        buttons[#buttons + 1] = id
    end,
    IsItemHovered = function()
        return false
    end,
    IsItemClicked = function()
        return false
    end,
    IsWindowHovered = function()
        return world.hover and true or false
    end,
    GetItemRectMin = function()
        return 40, 50
    end,
    GetItemRectMax = function()
        return 180, 70
    end,
    GetWindowDrawList = function()
        return draw_list
    end,
    GetBackgroundDrawList = function()
        return draw_list
    end,
    PushStyleColor = function(_, color)
        style_colors[#style_colors + 1] = color
    end,
    PopStyleColor = function() end,
    PushStyleVar = function() end,
    PopStyleVar = function() end,
    PushFont = function() end,
    PopFont = function() end,
    BeginTooltip = function()
        return false
    end,
    EndTooltip = function() end,
    SetNextWindowSizeConstraints = function() end,
    SetNextItemWidth = function() end,
    AlignTextToFramePadding = function() end,
    SliderInt = function(id, buf)
        slider_id = id
        if slider_mode == 'set25' then
            buf[1] = 25
            return true
        end
        return false
    end,
    Begin = function()
        began = began + 1
        return true
    end,
    End = function() end,
    GetWindowPos = function()
        return 99, 99
    end,
    GetWindowSize = function()
        return 220, 180
    end,
    AddFontFromFileTTF = function()
        return {}
    end,
}

local handlers = {}
ashita = {
    events = {
        register = function(name, _, fn)
            handlers[name] = fn
        end,
    },
}

package.preload.common = function()
    return {}
end
package.preload.chat = function()
    return chat
end
package.preload.settings = function()
    return settings
end
package.preload.imgui = function()
    return imgui
end

IMGUI_VERSION_NUM = 19223
FLT_MAX = 1e38
ImGuiSliderFlags_AlwaysClamp = 1
ImDrawFlags_RoundCornersLeft = 1
ImDrawCornerFlags_Left = 1
for _, name in ipairs({
    'ImGuiWindowFlags_AlwaysAutoResize', 'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize',
    'ImGuiWindowFlags_NoScrollbar', 'ImGuiWindowFlags_NoScrollWithMouse', 'ImGuiWindowFlags_NoCollapse',
    'ImGuiWindowFlags_NoNavInputs', 'ImGuiWindowFlags_NoMove',
    'ImGuiCol_Text', 'ImGuiCol_TextDisabled', 'ImGuiCol_WindowBg', 'ImGuiCol_ChildBg', 'ImGuiCol_PopupBg',
    'ImGuiCol_Border', 'ImGuiCol_Separator', 'ImGuiCol_ScrollbarBg', 'ImGuiCol_ScrollbarGrab',
    'ImGuiCol_ScrollbarGrabHovered', 'ImGuiCol_ScrollbarGrabActive', 'ImGuiCol_FrameBg',
    'ImGuiCol_FrameBgHovered', 'ImGuiCol_FrameBgActive', 'ImGuiCol_SliderGrab', 'ImGuiCol_SliderGrabActive',
    'ImGuiStyleVar_WindowPadding', 'ImGuiStyleVar_WindowRounding', 'ImGuiStyleVar_WindowBorderSize',
    'ImGuiStyleVar_FrameRounding', 'ImGuiStyleVar_PopupRounding', 'ImGuiStyleVar_PopupBorderSize',
    'ImGuiStyleVar_ItemSpacing', 'ImGuiStyleVar_ScrollbarSize', 'ImGuiStyleVar_ScrollbarRounding',
}) do
    _G[name] = 1
end

local function command(args)
    local event = {
        command = { args = function() return args end },
        blocked = false,
    }
    handlers.command(event)
    return event
end

local function text_in(message, mode, injected)
    handlers.text_in({
        message = message,
        mode = mode or 0,
        injected = injected or false,
    })
end

local function has_text(fragment)
    for _, text in ipairs(texts) do
        if text:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

local function has_drawn(fragment)
    for _, text in ipairs(drawn) do
        if text:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

local function button_at(id)
    for index, name in ipairs(buttons) do
        if name == id then
            return index
        end
    end
    return nil
end

local function jp_deadline(offset)
    local now = os.time()
    return math.floor((now + offset) / 86400) * 86400 + 86400 - offset
end

local function write_file(path, contents)
    local handle = io.open(path, 'wb')
    if handle == nil then
        fail('could not write ' .. path)
        return
    end
    handle:write(contents)
    handle:close()
end

local function mkdir(path)
    os.execute('mkdir "' .. path .. '" >nul 2>&1')
end

if arg and arg[1] == 'migrate' then
    local temp = (os.getenv('TEMP') or '.') .. '\\tracker-migrate-test'
    local function wipe()
        os.execute('rmdir /s /q "' .. temp .. '" >nul 2>&1')
    end
    wipe()
    mkdir(temp)
    mkdir(temp .. '\\config')
    mkdir(temp .. '\\config\\addons')
    mkdir(temp .. '\\config\\addons\\Goldilox-UI')
    mkdir(temp .. '\\config\\addons\\Goldilox-UI\\Seekey_33748')
    mkdir(temp .. '\\config\\addons\\AMANTracker')
    mkdir(temp .. '\\config\\addons\\AMANTracker\\Seekey_33748')

    local offset = 32400
    local deadline = jp_deadline(offset)
    write_file(temp .. '\\config\\addons\\Goldilox-UI\\Seekey_33748\\settings.lua', string.format([[
require('common')
local settings = T{ }
settings.dailies = T{ }
settings.dailies.Fishstix = T{ zone = 'Zeruhn Mines', message = 'Go to Zeruhn Mines, find it!' }
settings.palalumin_flagged = true
settings.palalumin_quests = T{ }
settings.palalumin_quests['Find flux'] = T{ zone = 'The Garden of RuHmet', message = 'The Garden of RuHmet' }
settings.deadline = %d
settings.offset = %d
settings.version = 1
settings.goldilox_time = %d
settings.ui_mode = 'should-drop'
return settings
]], deadline, offset, deadline))
    write_file(temp .. '\\config\\addons\\AMANTracker\\Seekey_33748\\settings.lua', [[
require('common')
local settings = T{ }
settings.is_active = true
settings.enemies = T{ }
settings.enemies[1] = T{ name = 'Donjon Bats', total = 5, killed = 1, match_type = 'exact' }
settings.target_level_range = '48~49'
settings.training_area_zone = 'Garlaige Citadel'
settings.ui_mode = 'targets'
return settings
]])

    world.install = temp
    settings_path = temp .. '\\config\\addons\\Tracker\\Seekey_33748\\'
    local tracker = require('Tracker')
    local dailies = require('lib.dailies')
    local regime = require('lib.regime')
    local ui = require('lib.ui')
    local cfg = dailies.settings()

    eq(addon.name, 'Tracker', 'name')
    eq(cfg.migrated, true, 'import marks migrated')
    eq(cfg.dailies.Fishstix.zone, 'Zeruhn Mines', 'imported fishstix')
    eq(cfg.palalumin_quests['Find flux'].zone, 'The Garden of RuHmet', 'imported flux')
    eq(cfg.goldilox_time, deadline, 'imported goldilox time')
    eq(cfg.opacity, 100, 'opacity default survives import')
    eq(cfg.ui_mode, nil, 'ui_mode is not kept')
    eq(cfg.is_active, true, 'imported regime active')
    eq(cfg.enemies[1].name, 'Donjon Bats', 'imported enemy')
    eq(cfg.training_area_zone, 'Garlaige Citadel', 'imported zone')
    eq(ui.show[1], true, 'restored hunt opens the window')
    truthy(printed('Restored active hunt'), 'restore notice')

    local used = {
        migrated = false,
        is_active = true,
        enemies = { { name = 'Keep Me', total = 1, killed = 0, match_type = 'exact' } },
        dailies = { Fishstix = { zone = 'Stay' } },
        palalumin_quests = {},
        palalumin_flagged = false,
        opacity = 15,
        deadline = deadline,
        offset = offset,
        version = 1,
    }
    listeners[1](used)
    eq(used.migrated, true, 'used profile is marked migrated')
    eq(used.enemies[1].name, 'Keep Me', 'used profile is not overwritten')
    eq(used.dailies.Fishstix.zone, 'Stay', 'used dailies stay')
    eq(used.opacity, 15, 'used opacity stays')
    eq(regime.view().enemies[1].name, 'Keep Me', 'rebind follows the character table')

    tracker.on_command({ '/tracker', 'help' })
    wipe()
    finish()
end

local parse = require('lib.daily_parse')
local family = require('lib.family')
local parser = require('lib.parser')
local match = require('lib.match')

eq(table.concat(parse.GOBLIN_ORDER, ','), 'Fishstix,Murdox,Mistrix,Saltlix,Beetrix', 'goblin order')
eq(table.concat(parse.PALALUMIN_ORDER, ','), 'Find flux,Item request,Defeat mobs', 'palalumin order')
eq(parse.chest_hint('You sense a secret chest is far in the North direction!'), 'Far North', 'chest hint')
eq(parse.chest_hint('nothing'), nil, 'chest hint miss')

-- One leading color byte, the way chat codes the name. A second 0x1F before the
-- colon is a paired span and the Goldilox strip removes everything inside it.
local npc, data = parse.read_goblin('\31\06Fishstix : Go to Zeruhn Mines, find and open my Secret Treasure Chest!\n', nil)
eq(npc, 'Fishstix', 'fishstix name')
eq(data.zone, 'Zeruhn Mines', 'fishstix zone')

npc, data = parse.read_goblin('Murdox : Go to East Sarutabaruta and kill 20 Crawlers!', { remaining = '16' })
eq(npc, 'Murdox', 'murdox name')
eq(data.count, '20', 'murdox count')
eq(data.target, 'Crawlers', 'murdox target')
eq(data.zone, 'East Sarutabaruta', 'murdox zone')
eq(data.remaining, '16', 'murdox keeps remaining')

npc, data = parse.read_goblin('Mistrix : Craft me up a signed oak cudgel and trade it to me!', nil)
eq(data.item, 'oak cudgel', 'mistrix item')
npc, data = parse.read_goblin('Saltlix : Go to West Sarutabaruta and kill Numbing Norman!', nil)
eq(data.target, 'Numbing Norman', 'saltlix target')
npc, data = parse.read_goblin('Beetrix : Go to Gusgen Mines, get a Gusgen Clay and trade it to me!', nil)
eq(data.item, 'Gusgen Clay', 'beetrix item')
eq(data.zone, 'Gusgen Mines', 'beetrix zone')
eq(parse.read_goblin('Somebody : Hello there!', nil), nil, 'unknown npc')

local system = parse.read_system('You\'ve killed enough, please return to Murdox to claim your reward!')
eq(system.kind, 'return', 'return kind')
eq(system.npc, 'Murdox', 'return npc')
system = parse.read_system('Beetrix quest complete. Nice work.')
eq(system.kind, 'complete', 'complete kind')
eq(system.npc, 'Beetrix', 'complete npc')
system = parse.read_system('Daily Quest: 16 kills remain. (Marid in Wajaom Woodlands)')
eq(system.kind, 'murdox', 'murdox progress')
eq(system.kills, '16', 'murdox kills')
eq(system.mob, 'Marid', 'murdox mob')
eq(system.zone, 'Wajaom Woodlands', 'murdox zone update')
system = parse.read_system('Defeat Mobs 3/10 (Zdei in Grand Palace of HuXzoi)')
eq(system.kind, 'pala_kills', 'pala kills')
eq(system.killed, 3, 'pala killed')
eq(system.total, 10, 'pala total')
eq(system.target, 'Zdei', 'pala target')
eq(system.zone, 'Grand Palace of HuXzoi', 'pala zone')
eq(parse.read_system('\129\158 Quest Completed').kind, 'quest_completed', 'quest completed')
eq(parse.read_system('Dice roll! She rolls a 4 (nice)').kind, 'dice', 'dice')
eq(parse.read_system('hello'), nil, 'system miss')

local menu = '\129\159 Find flux: Completed\n'
    .. '\129\158 Item request: Phuabo Organ x10, Xzomit Organ x5, Yovra Organ x1\n'
    .. '\129\158 Defeat mobs: Zdei (Grand Palace of HuXzoi) 3/10\n'
    .. '\129\158 Find flux: The Garden of RuHmet'
local found = parse.read_palalumin(menu, {})
eq(found['Find flux'].completed, true, 'flux completed wins')
eq(found['Find flux'].zone, 'Completed', 'completed flux keeps the objective text')
eq(found['Item request'].items, 'Phuabo Organ x10, Xzomit Organ x5, Yovra Organ x1', 'item list')
eq(found['Defeat mobs'].target, 'Zdei', 'defeat target')
eq(found['Defeat mobs'].zone, 'Grand Palace of HuXzoi', 'defeat zone')
eq(found['Defeat mobs'].killed, 3, 'defeat killed')
eq(found['Defeat mobs'].total, 10, 'defeat total')

local previous = {
    ['Find flux'] = { completed = true, zone = 'Keep', message = 'Keep' },
    ['Item request'] = { items = 'Old List', message = 'Old List' },
}
found = parse.read_palalumin(
    '\129\158 Find flux: The Garden of RuHmet\n\129\158 Defeat mobs: Zdei (Grand Palace of HuXzoi) 4/10\nItem request: New List',
    previous
)
eq(found['Find flux'], nil, 'open diamond does not reopen a completed flux')
eq(found['Defeat mobs'].killed, 4, 'defeat still updates')
eq(found['Item request'], nil, 'bare name does not replace a stored item list')

found = parse.read_palalumin(
    'Find flux: The Garden of RuHmet\nItem request: Phuabo Organ x10\nDefeat mobs: Zdei (Grand Palace of HuXzoi) 3/10',
    {}
)
eq(found['Find flux'].zone, 'The Garden of RuHmet', 'name fallback flux')
eq(found['Find flux'].completed, nil, 'name fallback flux is open')
eq(found['Item request'].items, 'Phuabo Organ x10', 'name fallback items')
eq(parse.read_palalumin('Just saying hello in Al\'Taieu.', {}), nil, 'unrelated lumoria chat')

local name, count = parse.item_need('Phuabo Organ x10')
eq(name, 'Phuabo Organ', 'item name')
eq(count, 10, 'item count')
name, count = parse.item_need('Gusgen Clay')
eq(name, 'Gusgen Clay', 'bare item')
eq(count, 1, 'bare item counts as one')

local enemies = parser.parse_enemies('5 Donjon Bats. 2 Kabooms. 3 Members of the Gigas Family.')
eq(#enemies, 3, 'three enemies')
eq(enemies[1].name, 'Donjon Bats', 'bats name')
eq(enemies[1].total, 5, 'bats total')
eq(enemies[1].killed, 0, 'bats start at zero')
eq(enemies[1].match_type, 'exact', 'bats are exact')
eq(enemies[3].match_type, 'family', 'gigas is a family')
eq(parser.parse_level_range('Target level range: 48~49.'), '48~49', 'level range')
eq(parser.parse_training_area('Training area: Garlaige Citadel.'), 'Garlaige Citadel', 'training area')
eq(parser.parse_training_area('Training area: Garlaige Citadel'), nil, 'area needs the period')
local hyphenated = parser.parse_enemies('5 Over-grown. 1 Slime.')
eq(#hyphenated, 2, 'hyphenated name does not stall the parser')
eq(hyphenated[2].name, 'Slime', 'second enemy after a hyphen')

truthy(family.is_family_member('Giant Guard', 'Gigas'), 'giant is gigas')
truthy(not family.is_family_member("Gigas's Guard", 'Gigas'), 'possessive gigas is excluded')
truthy(family.is_family_member('Goblin Tinkerer', 'Goblin'), 'goblin member')
truthy(not family.is_family_member("Goblin's Mug", 'Goblin'), 'goblin possessive excluded')
eq(family.extract_family_type('Members of the Gigas Family'), 'Gigas', 'family extract')

eq(match.kind({ name = 'Donjon Bats', match_type = 'exact' }, 'Donjon Bat'), 'added s', 'bat plural')
eq(match.kind({ name = 'Leeches', match_type = 'exact' }, 'Leech'), 'added es', 'leech plural')
eq(match.kind({ name = 'Damselflies', match_type = 'exact' }, 'Damselfly'), 'y to ies', 'fly plural')
eq(match.kind({ name = 'Donjon Bats', match_type = 'exact' }, '123Donjon Bat'), 'added s', 'leading marker stripped')
eq(match.kind({ name = 'Members of the Gigas Family', match_type = 'family' }, 'Giant Guard'), 'family Gigas', 'family kind')
eq(match.kind({ name = 'Members of the Gigas Family', match_type = 'exact' }, 'Giant Guard'), nil, 'exact row skips family')
eq(match.kind({ name = 'Members of the Gigas Family', match_type = 'family' }, 'Donjon Bat'), nil, 'family row skips other mobs')
local row, index = match.find({
    { name = 'Donjon Bats', match_type = 'exact' },
    { name = 'Members of the Gigas Family', match_type = 'family' },
}, 'Giant Guard')
eq(index, 2, 'find returns the family row')
eq(row.name, 'Members of the Gigas Family', 'find returns the enemy')
eq(match.kind({ name = 'Leeches' }, 'Leech'), 'added es', 'legacy plural')
eq(match.kind({ name = 'Members of the Goblin Family' }, "Goblin's Mug"), nil, 'legacy exclusion')

local real_gold = loadfile('R:\\CatsEyeXI\\catseyexi-client\\Vanacore\\config\\addons\\Goldilox-UI\\Seekey_33748\\settings.lua')
local real_aman = loadfile('R:\\CatsEyeXI\\catseyexi-client\\Vanacore\\config\\addons\\AMANTracker\\Seekey_33748\\settings.lua')
if real_gold and real_aman then
    local gold = real_gold()
    local aman = real_aman()
    eq(gold.dailies.Mistrix.item, 'oak cudgel', 'real mistrix item')
    eq(gold.dailies.Saltlix.target, 'Numbing Norman', 'real saltlix')
    eq(gold.palalumin_quests['Item request'].items, 'Phuabo Organ x10, Xzomit Organ x5, Yovra Organ x1', 'real item list')
    eq(gold.version, 1, 'real daily version')
    eq(aman.is_active, true, 'real regime active')
    eq(aman.enemies[1].name, 'Donjon Bats', 'real bats')
    eq(aman.enemies[2].name, 'Kabooms', 'real kabooms')
    eq(aman.target_level_range, '48~49', 'real level')
    eq(aman.training_area_zone, 'Garlaige Citadel', 'real area')
end

local tracker = require('Tracker')
local dailies = require('lib.dailies')
local regime = require('lib.regime')
local ui = require('lib.ui')
require('lib.packets')

eq(addon.name, 'Tracker', 'addon name')
eq(addon.author, 'Seekey', 'addon author')
eq(addon.version, '1.0', 'addon version')
eq(addon.desc, 'Keeps track of dailies and AMAN targets.  Exclusively for CatsEye XI.', 'addon desc')
eq(addon.link, 'https://github.com/seekey13/Tracker', 'addon link')
eq(dailies.settings().migrated, false, 'defaults profile is not migrated')
eq(ui.show[1], true, 'window starts open')
eq(ui.opacity, nil, 'opacity slider is gone')
eq(ui.opacity_open, nil, 'opacity gear is gone')

local cfg = dailies.settings()

text_in('Fishstix : Go to Zeruhn Mines, find and open my Secret Treasure Chest!', 9 + 256, true)
eq(cfg.dailies.Fishstix, nil, 'injected chat is ignored')

world.zone = 240
text_in('Fishstix : Go to Zeruhn Mines, find and open my Secret Treasure Chest!', 9)
eq(cfg.dailies.Fishstix, nil, 'goblin talk outside Jeuno is ignored')

text_in('You sense a secret chest is far in the North direction!', 0)
eq(cfg.dailies.Fishstix, nil, 'hint before the quest does not create a row')

text_in('Daily Quest: 16 kills remain. (Crawlers in East Sarutabaruta)', 121)
eq(cfg.dailies.Murdox, nil, 'kill progress before the talk is ignored')

text_in('Fishstix : Go to Zeruhn Mines, find and open my Secret Treasure Chest!', 121)
eq(cfg.dailies.Fishstix, nil, 'mode 121 is not npc dialogue')

world.zone = 245
text_in('Fishstix : Go to Zeruhn Mines, find and open my Secret Treasure Chest!', 9)
text_in('Murdox : Go to East Sarutabaruta and kill 20 Crawlers!', 9)
text_in('Mistrix : Craft me up a signed oak cudgel and trade it to me!', 9)
text_in('Saltlix : Go to West Sarutabaruta and kill Numbing Norman!', 9)
text_in('Beetrix : Go to Gusgen Mines, get a Gusgen Clay and trade it to me!', 9)
text_in("Beetrix : Congratulations! You've completed my quest for today, here's your reward!", 9)
eq(cfg.dailies.Beetrix.status, 'complete', 'congratulations marks the daily complete')
eq(cfg.dailies.Beetrix.zone, 'Gusgen Mines', 'congratulations keeps the zone')
eq(cfg.dailies.Beetrix.item, 'Gusgen Clay', 'congratulations keeps the item')
eq(dailies.is_complete({ message = 'Congratulations! Here is your reward!' }), true, 'stored congratulations counts as complete')
eq(cfg.dailies.Fishstix.zone, 'Zeruhn Mines', 'talk stores fishstix')
eq(cfg.dailies.Mistrix.item, 'oak cudgel', 'talk stores mistrix')

text_in('Daily Quest: 16 kills remain. (Crawlers in East Sarutabaruta)', 121)
eq(cfg.dailies.Murdox.remaining, '16', 'murdox remaining')
text_in('Murdox : Go to East Sarutabaruta and kill 20 Crawlers!', 9)
eq(cfg.dailies.Murdox.remaining, '16', 'second visit keeps remaining')
text_in('You sense a secret chest is FAR in the North direction!', 1)
eq(cfg.dailies.Fishstix.hint, 'Far North', 'hint lands on fishstix')

text_in('please return to Saltlix to claim your reward', 121)
eq(cfg.dailies.Saltlix.status, 'return', 'saltlix return')
text_in('Beetrix quest complete', 121)
eq(cfg.dailies.Beetrix.status, 'complete', 'beetrix complete')
text_in('Dice roll! Goldilox rolls a 12 (jackpot)', 121)
eq(cfg.goldilox_time, cfg.deadline, 'dice collects the reward')

world.zone = 34
text_in(
    '\129\159 Find flux: Completed\n\129\158 Item request: Phuabo Organ x10, Xzomit Organ x5\n\129\158 Defeat mobs: Zdei (Grand Palace of HuXzoi) 3/10',
    9
)
eq(cfg.palalumin_flagged, true, 'lumoria menu flags the day')
eq(cfg.palalumin_quests['Find flux'].completed, true, 'flux stored complete')
eq(cfg.palalumin_quests['Defeat mobs'].killed, 3, 'defeat stored')
text_in('Defeat Mobs 5/10 (Zdei in Grand Palace of HuXzoi)', 121)
eq(cfg.palalumin_quests['Defeat mobs'].killed, 5, 'system updates the kill count')

handlers.packet_out({ id = 0x0036 })
world.target = 'Palalumin'
text_in('Quest Completed', 121)
eq(cfg.palalumin_quests['Item request'].completed, true, 'trade completes the item request')
eq(cfg.palalumin_quests['Defeat mobs'].completed, nil, 'kills short of the total stay open')

cfg.palalumin_quests['Defeat mobs'].killed = 10
cfg.palalumin_quests['Item request'].completed = nil
handlers.packet_out({ id = 0x0036 })
text_in('Quest Completed', 121)
eq(cfg.palalumin_quests['Defeat mobs'].completed, true, 'satisfied kills complete')
eq(cfg.palalumin_quests['Item request'].completed, true, 'same turn-in completes the items')

cfg.palalumin_quests['Find flux'].completed = nil
world.target = 'Lumorian Flux'
text_in('Quest Completed', 121)
eq(cfg.palalumin_quests['Find flux'].completed, true, 'flux target completes find flux')

world.zone = 33
cfg.palalumin_quests['Find flux'] = { completed = true, zone = 'Keep', message = 'Keep' }
text_in('\129\158 Find flux: The Garden of RuHmet', 9)
eq(cfg.palalumin_quests['Find flux'].zone, 'Keep', 'reopen does not rewrite the row')
eq(cfg.palalumin_flagged, true, 'reopen still counts as the menu')

cfg.palalumin_quests['Defeat mobs'].completed = nil
cfg.palalumin_quests['Defeat mobs'].killed = 3
cfg.palalumin_quests['Defeat mobs'].total = 10
lines = {}
dailies.report()
truthy(printed('Secret chest at Zeruhn Mines'), 'report fishstix')
truthy(printed('Kill 16 more Crawlers at East Sarutabaruta (20 total)'), 'report murdox')
truthy(printed('Trade a signed oak cudgel'), 'report mistrix')
truthy(printed('Return to Saltlix.'), 'report saltlix')
truthy(printed('Beetrix: '), 'report beetrix')
truthy(printed('Complete!'), 'report complete')
truthy(printed('Goldilox: '), 'report reward')
truthy(printed('Kill 7 more Zdei at Grand Palace of HuXzoi (10 total)'), 'report pala')

local prompt = "A tome has been placed here by the Adventurers' Mutual Aid Network (A.M.A.N.)"
text_in('Training regime canceled.', 121)
eq(regime.view().is_active, false, 'cancel does nothing before a regime exists')
text_in('The information on this page instructs you to defeat the following:', 121)
eq(regime.view().is_parsing, false, 'the page is ignored until the tome prompt')
text_in(prompt, 121)
eq(regime.view().is_active, true, 'tome prompt arms tracking')
text_in('The information on this page instructs you to defeat the following:', 121)
eq(regime.view().is_parsing, true, 'page starts parsing')
eq(regime.view().is_active, true, 'parsing keeps the regime armed')
eq(cfg.is_active, false, 'the saved regime stays clear until confirm')
text_in('5 Donjon Bats. 2 Kabooms. 3 Members of the Gigas Family.', 121)
text_in('9 Should Not Appear.', 121)
text_in('Target level range: 48~49.', 121)
text_in('Training area: Garlaige Citadel.', 121)
eq(#regime.view().enemies, 3, 'only the first enemy line is kept')
eq(regime.view().enemies[2].name, 'Kabooms', 'second target')
eq(regime.view().is_parsing, false, 'level ends parsing')
eq(regime.view().target_level_range, '48~49', 'level stored')
eq(regime.view().training_area_zone, 'Garlaige Citadel', 'zone stored')
ui.show[1] = false
local confirm_lines = 0
for _, line in ipairs(lines) do
    if line:find('Training regime confirmed!', 1, true) then
        confirm_lines = confirm_lines + 1
    end
end
text_in('New training regime registered!', 121)
local confirm_after = 0
for _, line in ipairs(lines) do
    if line:find('Training regime confirmed!', 1, true) then
        confirm_after = confirm_after + 1
    end
end
eq(cfg.is_active, true, 'confirm saves the regime')
eq(ui.show[1], true, 'confirm opens the window')
eq(confirm_after - confirm_lines, 1, 'confirm is printed once')

regime.on_defeat('Somebody Else')
regime.on_progress(9)
eq(regime.view().enemies[1].killed, 0, 'untracked death takes no progress')
regime.on_defeat('Donjon Bat')
regime.view().pending[1].at = os.time() - 10
regime.on_defeat('Kaboom')
regime.on_progress(2)
eq(regime.view().enemies[1].killed, 0, 'stale death is dropped')
eq(regime.view().enemies[2].killed, 2, 'fresh death takes the absolute count')
regime.on_defeat('Giant Guard')
regime.on_progress(1)
eq(regime.view().enemies[3].killed, 1, 'family death takes the next count')
regime.on_reset()
eq(regime.view().enemies[2].killed, 0, 'reset zeroes every row')
eq(#regime.view().pending, 0, 'reset drops the queue')
regime.on_complete()
eq(regime.view().is_active, true, 'completion leaves the regime on screen')
truthy(regime.in_area(), 'in the training zone')
world.zone_name = 'Batallia Downs'
eq(regime.in_area(), false, 'outside the training zone')
world.zone_name = nil
truthy(regime.in_area(), 'unknown zone still records')
world.zone_name = 'Garlaige Citadel'

lines = {}
command({ '/tracker', 'test', 'Giant', 'Guard' })
truthy(printed('match: family Gigas'), 'test command family')
truthy(printed('no match'), 'test command misses the bats')
local usage = command({ '/at', 'test' })
eq(usage.blocked, true, '/at is blocked')
truthy(printed('Usage: /tracker test'), 'test usage')

command({ '/tracker' })
truthy(printed('Hold Shift to drag'), 'help mentions shift')
truthy(printed('fades until the mouse'), 'help mentions the hover fade')

lines = {}
local echoed = command({ '/echo', 'hi' })
eq(echoed.blocked, false, 'other commands pass through')
local gold = command({ '/goldilox' })
eq(gold.blocked, true, '/goldilox is handled')
truthy(printed('Fishstix:'), 'goldilox prints status')
command({ '/dailies', 'ui' })
eq(ui.show[1], false, '/dailies ui closes')
command({ '/goldilox', 'ui' })
eq(ui.show[1], true, '/goldilox ui opens')

handlers.key({ wparam = 0x11, lparam = 0 })
eq(ui.shift_held, false, 'other keys do not drag')
handlers.key({ wparam = 0x10, lparam = 0 })
eq(ui.shift_held, true, 'shift down drags')
handlers.key({ wparam = 0x10, lparam = bit.lshift(0x8000, 0x10) })
eq(ui.shift_held, false, 'shift up stops dragging')

local layout_root = (os.getenv('TEMP') or '.') .. '\\tracker-layout-test'
os.execute('rmdir /s /q "' .. layout_root .. '" >nul 2>&1')
mkdir(layout_root)
mkdir(layout_root .. '\\config')
write_file(layout_root .. '\\config\\imgui.ini', '[Window][Tracker]\nPos=12,34\n')
local layout_calls = {}
vana = {
    layout = {
        set = function(window, x, y, scale)
            layout_calls[#layout_calls + 1] = { window, x, y, scale }
        end,
    },
    paths = { install = layout_root },
}

local function render()
    buttons, texts, drawn = {}, {}, {}
    style_colors, dummies, rects = {}, {}, {}
    title_alpha = nil
    slider_id = nil
    local ok, err = xpcall(ui.render, debug.traceback)
    if not ok then
        fail('render\n' .. tostring(err))
    end
end

local function scaled(n)
    local s = math.max(0.75, math.min(1.6, 1440 / 1440)) * 1.1
    return math.floor(n * s + 0.5)
end

local function count_gaps()
    local gap = scaled(12)
    local n = 0
    for _, size in ipairs(dummies) do
        if size[1] == 0 and size[2] == gap then
            n = n + 1
        end
    end
    return n
end

local function has_solid_fill()
    for _, col in ipairs(rects) do
        if type(col) == 'number' and math.floor(col / 16777216) == 255 then
            return true
        end
    end
    return false
end

world.level = 0
ui.show[1] = true
began = 0
render()
eq(began, 0, 'loading skips the window')
eq(#layout_calls, 1, 'layout registers once')
eq(layout_calls[1][1], 'Tracker', 'layout window')
eq(layout_calls[1][2], 12, 'layout x from imgui.ini')
eq(layout_calls[1][3], 34, 'layout y from imgui.ini')
eq(layout_calls[1][4], 1, 'layout scale stays 1')

world.level = 75
cfg.dailies = {}
cfg.palalumin_quests = {}
cfg.palalumin_flagged = false
regime.clear()
began = 0
render()
eq(began, 0, 'an empty day draws nothing')

cfg.dailies = {
    Fishstix = { zone = 'Zeruhn Mines', hint = 'Far North' },
    Murdox = { count = '20', remaining = '16', target = 'Crawlers', zone = 'East Sarutabaruta' },
    Mistrix = { item = 'oak cudgel' },
    Saltlix = { target = 'Numbing Norman', zone = 'West Sarutabaruta', status = 'return' },
    Beetrix = { message = "Congratulations! You've completed my quest for today, here's your reward!" },
}
cfg.goldilox_time = nil
cfg.palalumin_flagged = true
cfg.palalumin_quests = {
    ['Find flux'] = { zone = 'The Garden of RuHmet', message = 'The Garden of RuHmet' },
    ['Item request'] = { items = 'Phuabo Organ x10, Xzomit Organ x5', message = 'Phuabo Organ x10, Xzomit Organ x5' },
    ['Defeat mobs'] = { target = 'Zdei', zone = 'Grand Palace of HuXzoi', killed = 3, total = 10 },
}
regime.bind({
    is_active = true,
    enemies = {
        { name = 'Donjon Bats', total = 5, killed = 1, match_type = 'exact' },
        { name = 'Members of the Gigas Family', total = 3, killed = 0, match_type = 'family' },
    },
    target_level_range = '48~49',
    training_area_zone = 'Garlaige Citadel',
})
render()
local goblin_i = button_at('##fold.Goblin Dailies')
local pala_i = button_at('##fold.Palalumin Quests')
local aman_i = button_at('##fold.AMAN Targets')
local close_i = button_at('##tracker.close')
eq(button_at('##tracker.cog'), nil, 'the gear is gone')
truthy(close_i ~= nil, 'close mark is still there')
truthy(goblin_i and pala_i and aman_i and goblin_i < pala_i and pala_i < aman_i, 'section order')
truthy(has_text('Beetrix: Complete!'), 'congratulations row reads as complete')
truthy(has_text('Training in'), 'regime line')
truthy(has_text('Lv 48~49'), 'level line')
truthy(has_drawn('Goldilox: Reward not collected.'), 'reward notice')
truthy(has_drawn('Tracker'), 'title')
eq(#layout_calls, 1, 'layout is not registered again')
eq(count_gaps(), 2, 'a gap sits between each section')
eq(style_colors[3][4], 0, 'the frame starts clear')
eq(title_alpha, 0, 'the title starts clear')
truthy(has_solid_fill(), 'section wells stay solid while the frame is clear')

local clock = os.clock() + 5
os.clock = function()
    return clock
end
ui.shift_held = true
world.hover = true
render()
eq(style_colors[3][4], 0, 'the fade waits one frame')
clock = clock + 1
render()
eq(style_colors[3][4], 1, 'hover brings the frame back')
eq(title_alpha, 255, 'hover brings the title back')
ui.shift_held = false
world.hover = false
clock = clock + 1
render()
eq(style_colors[3][4], 1, 'the fade-out waits one frame')
clock = clock + 1
render()
eq(style_colors[3][4], 0, 'leaving the window fades the frame')
eq(title_alpha, 0, 'leaving the window fades the title')
truthy(has_solid_fill(), 'section wells stay solid after the fade')

cfg.opacity = 40
cfg.deadline = 0
cfg.version = 1
local enemy_table = regime.view().enemies
truthy(dailies.roll_day(), 'a new day rolls')
eq(cfg.opacity, 40, 'day roll keeps opacity')
eq(regime.view().is_active, true, 'day roll keeps the regime')
eq(regime.view().enemies, enemy_table, 'day roll keeps the enemy table')
eq(cfg.dailies.Fishstix, nil, 'day roll clears goblins')
eq(cfg.palalumin_flagged, false, 'day roll clears palalumin')
cfg.version = 2
cfg.dailies.Fishstix = { zone = 'X' }
cfg.opacity = 40
truthy(dailies.roll_day(), 'version mismatch rolls dailies')
eq(cfg.version, 1, 'version returns to 1')
eq(cfg.dailies.Fishstix, nil, 'version mismatch clears dailies')
eq(cfg.opacity, 40, 'version mismatch keeps opacity')
eq(regime.view().is_active, true, 'version mismatch keeps the regime')

command({ '/tracker', 'clear' })
eq(regime.view().is_active, false, 'clear drops the regime')
eq(#regime.view().enemies, 0, 'clear drops enemies')
truthy(printed('Training data cleared'), 'clear notice')

ui.show[1] = true
cfg.palalumin_flagged = false
began = 0
render()
eq(began, 0, 'a finished day draws nothing')

os.execute('rmdir /s /q "' .. layout_root .. '" >nul 2>&1')
finish()
