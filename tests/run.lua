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
local tips, tooltip_depth = {}, 0
local sequence = {}
local slider_mode = 'idle'
local slider_id = nil
local slider_range = nil
local circles = 0
local click_id = nil

-- Fonts the way ImGui keeps them: one stack, and a font scale per window.
-- Every addon shares the tooltip window.
local font_stack, font_calls, faces = {}, {}, {}
local window_scales, in_window, scale_calls, stray_scale = {}, false, 0, 0

local function window_key()
    return tooltip_depth > 0 and 'tooltip' or 'main'
end

local function face_now()
    local top = font_stack[#font_stack]
    return { top and top.font, window_scales[window_key()] or 1 }
end

local draw_list = {
    AddLine = function() end,
    AddRect = function() end,
    AddRectFilled = function(_, _, _, col)
        rects[#rects + 1] = col
        sequence[#sequence + 1] = { 'rect', col }
    end,
    AddTriangleFilled = function() end,
    AddCircleFilled = function()
        circles = circles + 1
    end,
    ChannelsSplit = function() end,
    ChannelsSetCurrent = function() end,
    ChannelsMerge = function() end,
    AddText = function(_, _, col, str)
        if str == 'Tracker' and type(col) == 'number' then
            title_alpha = math.floor(col / 16777216)
        end
        if str == 'Trade' then
            world.trade_color = col
        end
        if type(str) == 'string' and #str > 1 then
            drawn[#drawn + 1] = str
            faces[str] = face_now()
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
        sequence[#sequence + 1] = { 'text', text }
        faces[text] = face_now()
    end,
    TextUnformatted = function(text)
        if tooltip_depth > 0 then
            tips[#tips + 1] = text
            faces[text] = face_now()
        end
    end,
    InvisibleButton = function(id)
        buttons[#buttons + 1] = id
        sequence[#sequence + 1] = { 'button', id }
        if id == click_id then
            world.arm_click = true
        end
    end,
    IsItemHovered = function()
        return world.hover_items and true or false
    end,
    IsItemClicked = function()
        if world.arm_click then
            world.arm_click = false
            click_id = nil
            return true
        end
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
    PushFont = function(font, size)
        font_stack[#font_stack + 1] = { font = font, size = size }
        font_calls[#font_calls + 1] = { font, size }
    end,
    PopFont = function()
        table.remove(font_stack)
    end,
    SetWindowFontScale = function(s)
        scale_calls = scale_calls + 1
        if not in_window and tooltip_depth == 0 then
            stray_scale = stray_scale + 1
        end
        window_scales[window_key()] = s
    end,
    -- Stock Ashita's ImGui 1.80 BeginTooltip returns nothing.
    BeginTooltip = function()
        tooltip_depth = tooltip_depth + 1
    end,
    EndTooltip = function()
        tooltip_depth = tooltip_depth - 1
    end,
    SetNextWindowSizeConstraints = function() end,
    SetNextItemWidth = function() end,
    AlignTextToFramePadding = function() end,
    -- slider_mode: 'idle', or a number the drag moves the slider to.
    SliderFloat = function(id, buf, min, max)
        slider_id = id
        slider_range = { min, max }
        if type(slider_mode) == 'number' then
            buf[1] = slider_mode
            return true
        end
        return false
    end,
    IsItemActive = function()
        return world.slider_held and true or false
    end,
    Begin = function()
        began = began + 1
        in_window = true
        return true
    end,
    End = function()
        in_window = false
    end,
    GetWindowPos = function()
        return 99, 99
    end,
    GetWindowSize = function()
        return 220, 180
    end,
    AddFontFromFileTTF = function(path, size)
        return { file = path, size = size }
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
handlers.load()

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

local function render(target)
    buttons, texts, drawn = {}, {}, {}
    style_colors, dummies, rects = {}, {}, {}
    title_alpha = nil
    slider_id, slider_range, circles = nil, nil, 0
    world.trade_color = nil
    tips, tooltip_depth = {}, 0
    sequence = {}
    font_calls, faces, scale_calls, stray_scale = {}, {}, 0, 0
    local ok, err = xpcall((target or ui).render, debug.traceback)
    if not ok then
        fail('render\n' .. tostring(err))
    end
end

local function scaled(n)
    local s = math.max(0.75, math.min(1.6, 1440 / 1440)) * 1.1
    return math.floor(n * s + 0.5)
end

local function is_face(font, file)
    return type(font) == 'table' and tostring(font.file):lower():sub(-#file - 1) == '\\' .. file
end

local function sized_pushes()
    local n = 0
    for _, call in ipairs(font_calls) do
        if call[2] ~= nil then
            n = n + 1
        end
    end
    return n
end

local function count_gaps(size)
    local gap = size or scaled(12)
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

local function bg_rect(alpha)
    local r, g, b = 0x16, 0x18, 0x22
    return ((alpha * 256 + b) * 256 + g) * 256 + r
end

local function has_rect(col)
    for _, painted in ipairs(rects) do
        if painted == col then
            return true
        end
    end
    return false
end

-- True when col is among the rects painted just before the named text or
-- button, with nothing else drawn between them.
local function laid_under(col, kind, value)
    for i, event in ipairs(sequence) do
        if event[1] == kind and event[2] == value then
            for j = i - 1, 1, -1 do
                if sequence[j][1] ~= 'rect' then
                    return false
                end
                if sequence[j][2] == col then
                    return true
                end
            end
            return false
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
local cog_i = button_at('##tracker.cog')
truthy(close_i ~= nil, 'close mark is still there')
truthy(cog_i and close_i and cog_i < close_i, 'the cog is left of the close mark')
eq(circles, 2, 'the cog is a body and its hole')
eq(slider_id, nil, 'the scale slider starts closed')
truthy(goblin_i and pala_i and aman_i and goblin_i < pala_i and pala_i < aman_i, 'section order')
eq(has_text('Beetrix: Complete!'), false, 'a finished goblin stays off the panel')
truthy(has_text('Secret chest at '), 'an open goblin stays')
cfg.goldilox_time = cfg.deadline
render()
eq(has_drawn('Goldilox: Complete!'), false, 'a collected reward stays off the panel')
eq(has_drawn('Goldilox: Reward not collected.'), false, 'a collected reward is not pending')
truthy(has_text('Secret chest at '), 'open goblins stay when the reward is in')
cfg.goldilox_time = nil
render()
truthy(has_text('Training in'), 'regime line')
truthy(has_text('Lv 48~49'), 'level line')
truthy(has_drawn('Goldilox: Reward not collected.'), 'reward notice')
truthy(has_drawn('Tracker'), 'title')
eq(#layout_calls, 1, 'layout is not registered again')
eq(count_gaps(), 2, 'a gap sits between each section')
eq(style_colors[3][4], 0, 'the frame starts clear')
eq(title_alpha, 0, 'the title starts clear')
truthy(has_solid_fill(), 'section wells stay solid while the frame is clear')
truthy(is_face(faces['Secret chest at '][1], 'segoeui.ttf'), 'row text is Segoe UI')
truthy(is_face(faces['Tracker'][1], 'seguisb.ttf'), 'the title is Segoe UI Semibold')
truthy(#font_calls > 0 and sized_pushes() == #font_calls, '1.92 pushes every face with its size')
eq(scale_calls, 0, '1.92 leaves the window font scale alone')
eq(#font_stack, 0, 'every font push is popped')

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

click_id = '##fold.Goblin Dailies'
render()
eq(has_text('Secret chest at '), false, 'a collapsed section hides its rows')
truthy(has_rect(bg_rect(0)), 'a collapsed header fades with the frame')
truthy(has_rect(bg_rect(255)), 'an open section stays opaque while another is collapsed')
click_id = '##fold.Goblin Dailies'
render()
truthy(has_text('Secret chest at '), 'expanding the section shows its rows')
eq(has_rect(bg_rect(0)), false, 'an open header stays opaque off the window')

-- The cog opens the scale slider. A drag moves the saved value at once. The
-- window takes it up, and it is saved, once the slider is let go.
local function count_rect(col)
    local n = 0
    for _, painted in ipairs(rects) do
        if painted == col then
            n = n + 1
        end
    end
    return n
end

eq(cfg.scale, 1, 'scale defaults to 1x')
eq(ui.scale(), 1, 'the window starts at 1x')
local opaque_grounds = count_rect(bg_rect(255))
click_id = '##tracker.cog'
render()
eq(ui.scale_open, true, 'the cog opens the scale slider')
eq(count_rect(bg_rect(255)), opaque_grounds + 1, 'the scale row stays opaque while the frame is clear')
eq(slider_id, '##tracker.scale', 'the scale slider shows once the cog opens it')
eq(slider_range and slider_range[1], 0.5, 'the scale slider starts at 0.5x')
eq(slider_range and slider_range[2], 2, 'the scale slider ends at 2x')
local saves_before = saves
world.slider_held = true
slider_mode = 2
render()
eq(cfg.scale, 2, 'a drag sets the scale')
eq(saves, saves_before, 'a drag does not save')
render()
eq(count_gaps(), 2, 'the window keeps its size while the slider is held')
world.slider_held = false
slider_mode = 'idle'
render()
eq(saves, saves_before + 1, 'letting go saves the scale')
render()
eq(count_gaps(math.floor(12 * 1.1 * 2 + 0.5)), 2, 'letting go takes the new scale up')
truthy(ui.set_scale(9), 'set_scale takes a number')
eq(cfg.scale, 2, 'scale stops at 2x')
ui.set_scale(0.1)
eq(cfg.scale, 0.5, 'scale stops at 0.5x')
ui.set_scale(1.234)
eq(cfg.scale, 1.23, 'scale keeps hundredths')
eq(ui.set_scale('big'), false, 'a word is not a scale')
cfg.scale = 7
eq(ui.scale(), 2, 'a saved scale past 2x reads as 2x')
cfg.scale = 'x'
eq(ui.scale(), 1, 'a bad saved scale reads as 1x')
cfg.scale = 1
click_id = '##tracker.cog'
render()
eq(ui.scale_open, false, 'the cog closes the scale slider')
eq(slider_id, nil, 'a closed scale slider is not drawn')
eq(count_gaps(), 2, 'the window is back at 1x')
click_id = '##tracker.cog'
render()
click_id = '##tracker.close'
render()
eq(ui.show[1], false, 'the x closes the window')
eq(ui.scale_open, false, 'the x closes the scale slider too')
ui.show[1] = true

world.hover_items = true
render()
eq(tooltip_depth, 0, 'every tooltip closes before the window ends')
local zone_tip = false
for _, tip in ipairs(tips) do
    if tip == 'Open FFXI Wiki: Garlaige Citadel' then
        zone_tip = true
    end
end
truthy(zone_tip, 'a hovered link shows its tooltip')
world.hover_items = false

-- ImGui before 1.92 draws a face only at its bake size, so the window font
-- scale sizes it. This is how Chains draws Segoe there.
package.loaded['lib.ui'] = nil
IMGUI_VERSION_NUM = 18000
local old_ui = require('lib.ui')
IMGUI_VERSION_NUM = 19223
package.loaded['lib.ui'] = ui
old_ui._layout_set = true
old_ui.bake()
old_ui.show[1] = true
render(old_ui)
render(old_ui)
local body_scale = scaled(16) / 18
truthy(is_face(faces['Secret chest at '][1], 'segoeui.ttf'), 'before 1.92 row text is Segoe UI')
eq(faces['Secret chest at '][2], body_scale, 'before 1.92 the window font scale sizes row text')
truthy(is_face(faces['Tracker'][1], 'seguisb.ttf'), 'before 1.92 the title is Segoe UI Semibold')
eq(faces['Tracker'][2], body_scale, 'before 1.92 the title is sized by the window font scale')
truthy(#font_calls > 0, 'before 1.92 faces are pushed')
eq(sized_pushes(), 0, 'before 1.92 a face goes on without a size')
eq(stray_scale, 0, 'before 1.92 the font scale is only set inside a window')
eq(#font_stack, 0, 'before 1.92 every font push is popped')
eq(window_scales.main, body_scale, 'before 1.92 the panel ends on its body scale')
world.hover_items = true
render(old_ui)
world.hover_items = false
local tip_face = faces['Open FFXI Wiki: Garlaige Citadel']
truthy(tip_face and is_face(tip_face[1], 'segoeui.ttf'), 'before 1.92 a tooltip is Segoe UI')
eq(tip_face and tip_face[2], scaled(14) / 18, 'before 1.92 the tooltip window font scale sizes it')
eq(window_scales.tooltip, 1, 'the shared tooltip window goes back to scale 1')
eq(faces['Secret chest at '][2], body_scale, 'a tooltip leaves the panel on its body scale')

-- Stock Ashita's ImGui binds no draw-list channels.
local channels_split = draw_list.ChannelsSplit
draw_list.ChannelsSplit = nil
render()
render()
local well = ((255 * 256 + 0x17) * 256 + 0x10) * 256 + 0x0E
truthy(laid_under(bg_rect(255), 'button', '##fold.AMAN Targets'), 'without channels the section ground goes down first')
truthy(laid_under(well, 'text', 'Donjon Bats'), 'without channels a row well goes under its text')
truthy(laid_under(well, 'text', 'Secret chest at '), 'without channels a static row well goes under its text')
world.hover = true
clock = clock + 1
render()
clock = clock + 1
render()
truthy(laid_under(bg_rect(255), 'button', '##fold.AMAN Targets'), 'without channels the section ground stays opaque on hover')
world.hover = false
clock = clock + 1
render()
clock = clock + 1
render()
ui.scale_open = true
render()
render()
truthy(laid_under(bg_rect(255), 'text', 'Scale'), 'without channels the scale row ground stays opaque')
ui.scale_open = false
draw_list.ChannelsSplit = channels_split

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

local trade = require('lib.trade')

local function hex_to_bin(text)
    return (text:gsub('%s', ''):gsub('%x%x', function(byte)
        return string.char(tonumber(byte, 16))
    end))
end

local function packet_matches(packet, hex, why)
    local want = hex_to_bin(hex)
    eq(#packet, 64, why .. ' length')
    local got = packet:sub(5)
    local body = want:sub(5)
    eq(#got, #body, why .. ' body length')
    for i = 1, #body do
        if got:byte(i) ~= body:byte(i) then
            eq(got:byte(i), body:byte(i), string.format('%s byte 0x%02X', why, i + 3))
            return
        end
    end
    eq(true, true, why)
end

-- The bytes XIIM captured from the client's own 0x036 packets. The first four
-- are the header Ashita writes, so the body comparison starts at byte 5.
packet_matches(trade.build_trade(0x010F581D, 0x071D, {
    { slot = 0x29, count = 10 }, { slot = 0x18, count = 1 },
    { slot = 0x02, count = 9 }, { slot = 0x0A, count = 3 },
    { slot = 0x2A, count = 3 }, { slot = 0x47, count = 9 },
    { slot = 0x1D, count = 12 }, { slot = 0x13, count = 1 },
}), [[
    36 20 1C 17 1D 58 0F 01 0A 00 00 00 01 00 00 00
    09 00 00 00 03 00 00 00 03 00 00 00 09 00 00 00
    0C 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00
    29 18 02 0A 2A 47 1D 13 00 00 1D 07 08 00 00 00
]], '8-entry trade')
packet_matches(trade.build_trade(0x010F581D, 0x071D, {
    { slot = 0x44, count = 1 }, { slot = 0x3A, count = 1 }, { slot = 0x0D, count = 1 },
}), [[
    36 20 92 1A 1D 58 0F 01 01 00 00 00 01 00 00 00
    01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    44 3A 0D 00 00 00 00 00 00 00 1D 07 03 00 00 00
]], '3-entry trade')

local function read_u32(bytes, index)
    return bytes[index] + bytes[index + 1] * 256 + bytes[index + 2] * 65536 + bytes[index + 3] * 16777216
end

local function read_u16(bytes, index)
    return bytes[index] + bytes[index + 1] * 256
end

local function rgba_u32(hex)
    local r = tonumber(hex:sub(2, 3), 16)
    local g = tonumber(hex:sub(4, 5), 16)
    local b = tonumber(hex:sub(6, 7), 16)
    return ((255 * 256 + b) * 256 + g) * 256 + r
end

local slots = {
    [0] = { Id = 1001, Count = 99, Flags = 0 },
    [1] = { Id = 1001, Count = 12, Flags = 0 },
    [2] = { Id = 1002, Count = 5, Flags = 0 },
    [3] = { Id = 1003, Count = 9, Flags = 0 },
    [4] = { Id = 1001, Count = 12, Flags = 1 },
}
local max_slot = 80
local actors = {
    [10] = { name = 'Player', id = 1, flags = 0, dist = 0, status = 0 },
    [1794] = { name = 'Palalumin', id = 16918530, flags = 0x200, dist = 0.25, status = 0 },
}
local captured = {}
local names = {
    [1001] = 'Phuabo Organ',
    [1002] = 'Xzomit Organ',
    [1003] = 'Yovra Organ',
}
local old_memory = AshitaCore.GetMemoryManager
local old_resources = AshitaCore.GetResourceManager
local old_packets = AshitaCore.GetPacketManager

AshitaCore.GetMemoryManager = function()
    return {
        GetPlayer = function()
            return { GetMainJobLevel = function() return world.level end }
        end,
        GetParty = function()
            return {
                GetMemberZone = function() return world.zone end,
                GetMemberTargetIndex = function() return 10 end,
            }
        end,
        GetTarget = function()
            return {
                GetIsSubTargetActive = function() return 0 end,
                GetTargetIndex = function() return 1 end,
            }
        end,
        GetInventory = function()
            return {
                GetContainerCountMax = function() return max_slot end,
                GetContainerItem = function(_, _, slot)
                    return slots[slot] or { Id = 0, Count = 0, Flags = 0 }
                end,
            }
        end,
        GetEntity = function()
            return {
                GetName = function(_, index)
                    local actor = actors[index]
                    return actor and actor.name or ''
                end,
                GetServerId = function(_, index)
                    local actor = actors[index]
                    return actor and actor.id or 0
                end,
                GetRenderFlags0 = function(_, index)
                    local actor = actors[index]
                    return actor and actor.flags or 0
                end,
                GetDistance = function(_, index)
                    local actor = actors[index]
                    return actor and actor.dist or 10000
                end,
                GetStatus = function(_, index)
                    local actor = actors[index]
                    return actor and actor.status or 0
                end,
            }
        end,
    }
end
AshitaCore.GetResourceManager = function()
    return {
        GetString = function() return world.zone_name end,
        GetItemByName = function(_, item_name)
            if type(item_name) ~= 'string' then
                return nil
            end
            for id, item_name_known in pairs(names) do
                if item_name_known:lower() == item_name:lower() then
                    return { Id = id, Name = { item_name_known } }
                end
            end
            return nil
        end,
        GetItemById = function(_, id)
            local item_name = names[id]
            if not item_name then
                return nil
            end
            return { Id = id, Name = { item_name } }
        end,
    }
end
AshitaCore.GetPacketManager = function()
    return {
        AddOutgoingPacket = function(_, id, data)
            captured[#captured + 1] = { id = id, data = data }
        end,
    }
end

local needs = {
    { name = 'Phuabo Organ', needed = 10 },
    { name = 'Xzomit Organ', needed = 5 },
}
local npc = actors[1794]

local function offer()
    return dailies.trade_button(needs)
end

clock = 100000
world.zone = 34
eq(offer(), 'ready', 'HuXzoi within 3 yalms can trade')
npc.dist = 9
eq(offer(), 'ready', '3 yalms is in range')
npc.dist = 9.01
eq(offer(), nil, 'past 3 yalms hides the button')
npc.dist = 36
eq(offer(), nil, '6 yalms is not close enough')
npc.dist = 0.25
npc.flags = 0
eq(offer(), nil, 'an unrendered Palalumin is ignored')
npc.flags = 0x200
npc.id = 0
eq(offer(), nil, 'a Palalumin with no id is ignored')
npc.id = 16918530
local saved_name = npc.name
npc.name = 'Not Palalumin'
eq(offer(), nil, 'a different npc is ignored')
npc.name = saved_name
world.zone = 33
eq(offer(), nil, 'AlTaieu hides the button')
world.zone = 35
eq(offer(), nil, 'RuHmet hides the button')
world.zone = 245
eq(offer(), nil, 'Jeuno hides the button')
world.zone = 34
eq(offer(), 'ready', 'back in HuXzoi the button returns')

local held = slots[1]
slots[1] = { Id = 1001, Count = 12, Flags = 1 }
eq(offer(), nil, 'locked stacks are not tradable')
slots[1] = { Id = 1001, Count = 4, Flags = 0 }
eq(offer(), nil, 'slot 0 is not a trade slot')
slots[1] = held

local function check_turnin(packet, why)
    eq(packet.id, 0x36, why .. ' id')
    local data = packet.data
    eq(type(data), 'table', why .. ' bytes')
    eq(#data, 64, why .. ' size')
    eq(read_u32(data, 5), 16918530, why .. ' npc id')
    eq(read_u32(data, 9), 10, why .. ' phuabo count')
    eq(read_u32(data, 13), 5, why .. ' xzomit count')
    eq(read_u32(data, 17), 0, why .. ' no third stack')
    eq(data[49], 1, why .. ' first slot')
    eq(data[50], 2, why .. ' second slot')
    eq(data[51], 0, why .. ' no third slot')
    eq(read_u16(data, 59), 1794, why .. ' npc index')
    eq(data[61], 2, why .. ' entry count')
end

cfg.palalumin_flagged = true
cfg.palalumin_quests = {
    ['Item request'] = {
        items = 'Phuabo Organ x10, Xzomit Organ x5',
        message = 'Phuabo Organ x10, Xzomit Organ x5',
    },
}

actors[10].status = 4
truthy(dailies.trade_start(needs), 'queue the turn-in')
dailies.trade_update()
eq(#captured, 0, 'no trade while an event is open')
eq(offer(), 'wait', 'the button waits out the event')
eq(dailies.trade_start(needs), false, 'a second click does not queue another')
actors[10].status = 0
dailies.trade_update()
eq(#captured, 1, 'one trade once the event ends')
check_turnin(captured[1], 'turn-in')
dailies.trade_update()
eq(#captured, 1, 'the next frame does not trade again')

clock = 100002
dailies.trade_update()
eq(#captured, 1, 'two seconds does not finish the wait')
eq(offer(), 'wait', 'the button stays gray during the wait')
eq(dailies.trade_start(needs), false, 'three seconds have not elapsed')

clock = 100010
actors[10].status = 4
dailies.trade_update()
eq(#captured, 1, 'the open event still blocks another trade')
eq(offer(), 'wait', 'the button stays down through the event')
actors[10].status = 0
dailies.trade_update()
eq(offer(), 'ready', 'the button returns after the event and the delay')
truthy(dailies.trade_start(needs), 'a later turn-in is allowed')
dailies.trade_update()
eq(#captured, 2, 'the later turn-in is a single packet')
check_turnin(captured[2], 'second turn-in')
clock = 100012
eq(dailies.trade_start(needs), false, 'the next trade waits three seconds')
dailies.trade_update()
eq(#captured, 2, 'no packet during that delay')

local saved_count = slots[1].Count
clock = 100020
trade.cancel()
truthy(dailies.trade_start(needs), 'queue a stack that then changes')
slots[1].Count = 3
dailies.trade_update()
eq(#captured, 2, 'a short stack is not traded')
eq(offer(), nil, 'the button hides once the items are short')
slots[1].Count = saved_count

local original_slots = {
    [0] = slots[0],
    [1] = slots[1],
    [2] = slots[2],
    [3] = slots[3],
    [4] = slots[4],
}
local holder = { slots = original_slots, max_slot = 80 }
AshitaCore.GetMemoryManager = function()
    return {
        GetPlayer = function()
            return { GetMainJobLevel = function() return world.level end }
        end,
        GetParty = function()
            return {
                GetMemberZone = function() return world.zone end,
                GetMemberTargetIndex = function() return 10 end,
            }
        end,
        GetTarget = function()
            return {
                GetIsSubTargetActive = function() return 0 end,
                GetTargetIndex = function() return 1 end,
            }
        end,
        GetInventory = function()
            return {
                GetContainerCountMax = function() return holder.max_slot end,
                GetContainerItem = function(_, _, slot)
                    return holder.slots[slot] or { Id = 0, Count = 0, Flags = 0 }
                end,
            }
        end,
        GetEntity = function()
            return {
                GetName = function(_, index)
                    local actor = actors[index]
                    return actor and actor.name or ''
                end,
                GetServerId = function(_, index)
                    local actor = actors[index]
                    return actor and actor.id or 0
                end,
                GetRenderFlags0 = function(_, index)
                    local actor = actors[index]
                    return actor and actor.flags or 0
                end,
                GetDistance = function(_, index)
                    local actor = actors[index]
                    return actor and actor.dist or 10000
                end,
                GetStatus = function(_, index)
                    local actor = actors[index]
                    return actor and actor.status or 0
                end,
            }
        end,
    }
end

holder.max_slot = 9
holder.slots = {}
for slot = 1, 9 do
    holder.slots[slot] = { Id = 1001, Count = 1, Flags = 0 }
end
eq(dailies.trade_button({ { name = 'Phuabo Organ', needed = 9 } }), nil, 'nine stacks do not fit one trade')
eq(dailies.trade_start({ { name = 'Phuabo Organ', needed = 9 } }), false, 'nine stacks are not sent')
eq(#captured, 2, 'a refused trade sends nothing')
holder.max_slot = 8
holder.slots[9] = nil
clock = clock + 3
truthy(dailies.trade_start({ { name = 'Phuabo Organ', needed = 8 } }), 'eight stacks fit one trade')
dailies.trade_update()
eq(#captured, 3, 'eight stacks are one packet')
eq(captured[3].data[61], 8, 'eight entries')
for i = 1, 8 do
    eq(captured[3].data[48 + i], i, 'eight-stack slot ' .. i)
    eq(read_u32(captured[3].data, 9 + (i - 1) * 4), 1, 'eight-stack count ' .. i)
end

holder.slots = original_slots
holder.max_slot = 80
clock = clock + 3
trade.cancel()
cfg.palalumin_flagged = true
cfg.palalumin_quests = {
    ['Item request'] = {
        items = 'Phuabo Organ x10, Xzomit Organ x5',
        message = 'Phuabo Organ x10, Xzomit Organ x5',
    },
}
cfg.dailies = {}
ui.show[1] = true
world.level = 75
world.zone = 34
npc.dist = 0.25
npc.flags = 0x200
npc.id = 16918530
actors[10].status = 0

render()
truthy(has_drawn('Trade'), 'the row shows Trade]')
eq(world.trade_color, rgba_u32('#FFFFFF'), 'the trade button is lit')
local trade_i = button_at('##pala.trade')
local pala_header = button_at('##fold.Palalumin Quests')
truthy(trade_i and pala_header and pala_header < trade_i, 'the trade button is on the palalumin row')

holder.slots[2].Count = 0
render()
eq(button_at('##pala.trade'), nil, 'missing items hide the button')
eq(world.trade_color, nil, 'missing items draw no label')
holder.slots[2].Count = 5

world.zone = 33
render()
eq(button_at('##pala.trade'), nil, 'the button is not drawn outside HuXzoi')
world.zone = 34
npc.dist = 36
render()
eq(button_at('##pala.trade'), nil, 'the button is not drawn out of range')
npc.dist = 0.25
render()
eq(world.trade_color, rgba_u32('#FFFFFF'), 'the button returns in range')

cfg.palalumin_quests['Item request'].completed = true
eq(dailies.trade_start(needs), false, 'a finished request is not traded')
cfg.palalumin_quests['Item request'].completed = nil

click_id = '##pala.trade'
render()
eq(offer(), 'wait', 'the click leaves the turn-in pending')
render()
eq(world.trade_color, rgba_u32('#7B8095'), 'a pending trade button is gray')
local sent_before = #captured
handlers.d3d_present()
eq(#captured, sent_before + 1, 'present sends the one queued trade')
check_turnin(captured[#captured], 'row trade')
handlers.d3d_present()
eq(#captured, sent_before + 1, 'present does not send a second trade')
click_id = '##pala.trade'
render()
eq(world.trade_color, rgba_u32('#7B8095'), 'the gray button stays gray')
handlers.d3d_present()
eq(#captured, sent_before + 1, 'clicking the gray button does not trade')

clock = clock + 3
actors[10].status = 0
dailies.trade_update()
world.target = 'Palalumin'
text_in('Quest Completed', 121)
cfg.palalumin_quests['Item request'].completed = nil
truthy(dailies.trade_start(needs), 'queue the completion trade')
dailies.trade_update()
eq(cfg.palalumin_quests['Item request'].completed, nil, 'sending does not finish the quest by itself')
text_in('Quest Completed', 121)
eq(cfg.palalumin_quests['Item request'].completed, true, 'the issued trade completes the item request')

AshitaCore.GetMemoryManager = old_memory
AshitaCore.GetResourceManager = old_resources
AshitaCore.GetPacketManager = old_packets
finish()
