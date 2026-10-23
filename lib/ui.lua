--[[
Tracker - one Vanacore panel.

The drawing is the Goldilox window: /vana colours, Segoe UI, folding
small-cap headers, and one well per row. An amber meter is kill or item
progress. Hold Shift to drag. The title, close mark, frame, and the
gaps between sections fade out until the mouse is over the window.
A section header lines up with its rows. An open section stays opaque.
A collapsed header fades with the frame until the mouse is over the window.
The cog left of the close mark opens a scale slider, 0.5x to 2x. The
window takes the new size once the slider is let go.
]]

local imgui = require('imgui')
local settingslib = require('settings')
local dailies = require('lib.dailies')
local regime = require('lib.regime')
local family = require('lib.family')
local parse = require('lib.daily_parse')

local ui = {}
ui.show = { true }
ui.shift_held = false
ui.scale_open = false

local HEX = {
    bg = '#161822', border = '#2A2E3E', line = '#242838', well = '#0E1017',
    hover = '#1F2334', white = '#FFFFFF', text = '#E8EAF1', text2 = '#BDC1D0',
    dim = '#7B8095', faint = '#4E536A', accent = '#7AA2F7', accent2 = '#A9C1FF',
    accent_lo = '#3E5CB3', teal = '#5FD3B3', amber = '#E8B45C', rose = '#EE6F78',
    off = '#2B2F42', popup = '#0F1118',
}

local function rgba(hex, alpha)
    return {
        tonumber(hex:sub(2, 3), 16) / 255,
        tonumber(hex:sub(4, 5), 16) / 255,
        tonumber(hex:sub(6, 7), 16) / 255,
        alpha or 1,
    }
end

local function u32(hex, alpha)
    local r = tonumber(hex:sub(2, 3), 16)
    local g = tonumber(hex:sub(4, 5), 16)
    local b = tonumber(hex:sub(6, 7), 16)
    local a = math.floor(math.max(0, math.min(1, alpha or 1)) * 255 + 0.5)
    return ((a * 256 + b) * 256 + g) * 256 + r
end

local function mix(a, b, t)
    t = math.max(0, math.min(1, t or 0))
    local out = '#'
    for i = 2, 6, 2 do
        local x = tonumber(a:sub(i, i + 1), 16)
        local y = tonumber(b:sub(i, i + 1), 16)
        out = out .. string.format('%02X', math.floor(x + (y - x) * t + 0.5))
    end
    return out
end

-- grey_bar and dark_grey are sentinels compared by identity.
-- grey_bar: the row is done, so the count dims. dark_grey: the count is unknown.
local COLORS = {
    white     = rgba(HEX.text),
    link      = rgba(HEX.accent),
    orange    = rgba(HEX.amber),
    grey_text = rgba(HEX.dim),
    grey_bar  = rgba(HEX.teal),
    dark_grey = rgba(HEX.off),
}

local scale = 1
local function S(n)
    return math.floor(n * scale + 0.5)
end

-- The slider's scale. It is taken up only while the slider is not held, or
-- the window would resize and move the slider under the mouse.
local user_scale = 1
local SCALE_MIN, SCALE_MAX = 0.5, 2

local function update_scale()
    local h = 1080
    local ok, io = pcall(imgui.GetIO)
    if ok and io and io.DisplaySize then
        h = tonumber(io.DisplaySize.y) or h
    end
    scale = math.max(0.75, math.min(1.6, h / 1440)) * 1.1 * user_scale
end

local BODY, SMALL = 16, 13.5
local DYNAMIC = (tonumber(IMGUI_VERSION_NUM) or 0) >= 19200
-- Each face is baked at this size. ImGui before 1.92 draws a face only at
-- its bake size, so there the window font scale makes up the rest.
local BAKE_PX = 18
local fonts = { tried = false, ready = false }
local measured, measured_scale, measured_n = {}, nil, 0

-- Segoe UI from Windows, once, from the load event. Adding to the shared
-- atlas mid-frame can crash. Without segoeui.ttf, ready stays false.
function ui.bake()
    if fonts.tried then
        return
    end
    fonts.tried = true
    local dir = ((os.getenv and os.getenv('WINDIR')) or 'C:\\Windows') .. '\\Fonts\\'
    local function add(file, fallback)
        local path = dir .. file
        local handle = io.open(path, 'rb')
        if not handle then
            return fallback
        end
        handle:close()
        local ok, face_now = pcall(imgui.AddFontFromFileTTF, path, BAKE_PX)
        if ok and face_now then
            return face_now
        end
        return fallback
    end
    local text = add('segoeui.ttf')
    if text == nil then
        return
    end
    local semi = add('seguisb.ttf', text)
    fonts.text = text
    fonts.semi = semi
    fonts.bold_italic = add('segoeuiz.ttf', semi)
    fonts.semi_italic = add('seguisbi.ttf', semi)
    fonts.ready = true
end

local function face(which)
    return fonts[which] or imgui.GetFont()
end

-- The window font scale that stands in for size before 1.92.
local function scale_for(size)
    return math.max(0.1, S(size) / BAKE_PX)
end

-- The window font scale each push replaced, for its pop to put back.
local scales, window_scale = {}, 1

-- Inside a window only: before 1.92 the size is that window's font scale.
local function push_font(font, size)
    if DYNAMIC then
        imgui.PushFont(font, S(size))
        return true
    end
    if not (fonts.ready and font) then
        return false
    end
    imgui.PushFont(font)
    scales[#scales + 1] = window_scale
    window_scale = scale_for(size)
    imgui.SetWindowFontScale(window_scale)
    return true
end

local function pop_font()
    if not DYNAMIC then
        window_scale = table.remove(scales) or 1
        imgui.SetWindowFontScale(window_scale)
    end
    imgui.PopFont()
end

-- Ahead of Begin. Before 1.92 the face goes on now, and its size waits for
-- Begin to make the window current.
local function push_window_font(size)
    if DYNAMIC then
        imgui.PushFont(face('text'), S(size))
        return true
    end
    if fonts.ready then
        imgui.PushFont(fonts.text)
        return true
    end
    return false
end

local function measure(str, font, size)
    str = tostring(str or '')
    if measured_scale ~= scale or measured_n > 4000 then
        measured, measured_scale, measured_n = {}, scale, 0
    end
    local key = tostring(font) .. '|' .. tostring(size) .. '|' .. str
    local found = measured[key]
    if not found then
        local pushed = push_font(font, size)
        local w, h = imgui.CalcTextSize(str)
        if pushed then
            pop_font()
        end
        found = { w or 0, h or 0 }
        measured[key] = found
        measured_n = measured_n + 1
    end
    return found[1], found[2]
end

local function text_mid(dl, x, cy, str, hex, font, size, alpha)
    local _, h = measure(str, font, size)
    local y = cy - h / 2
    -- Segoe's tall ascent sets text centred by its box low.
    if fonts.ready then
        y = y - math.floor(h * 0.06 + 0.5)
    end
    local pushed = push_font(font, size)
    dl:AddText({ x, y }, u32(hex, alpha), str)
    if pushed then
        pop_font()
    end
end

local function text_spaced(dl, x, cy, str, hex, font, size, spacing, alpha)
    local start = x
    local i, n = 1, #str
    while i <= n do
        local b = str:byte(i)
        local len = 1
        if b >= 0xF0 then
            len = 4
        elseif b >= 0xE0 then
            len = 3
        elseif b >= 0xC0 then
            len = 2
        end
        local letter = str:sub(i, i + len - 1)
        if dl ~= nil then
            text_mid(dl, x, cy, letter, hex, font, size, alpha)
        end
        x = x + measure(letter, font, size) + spacing
        i = i + len
    end
    if x == start then
        return 0
    end
    return x - start - spacing
end

local function fill(dl, x, y, w, h, hex, radius, alpha, corners)
    if w <= 0 or h <= 0 then
        return
    end
    local col = u32(hex, alpha)
    if corners then
        dl:AddRectFilled({ x, y }, { x + w, y + h }, col, radius or 0, corners)
    else
        dl:AddRectFilled({ x, y }, { x + w, y + h }, col, radius or 0)
    end
end

local function outline(dl, x, y, w, h, hex, radius, alpha)
    if w <= 0 or h <= 0 then
        return
    end
    dl:AddRect({ x, y }, { x + w, y + h }, u32(hex, alpha), radius or 0)
end

local anim, last_clock, frame_dt = {}, nil, 0
local function tick()
    local now = os.clock()
    frame_dt = last_clock and math.max(0, math.min(0.1, now - last_clock)) or 0
    last_clock = now
end

local function ease(id, target)
    local v = anim[id]
    if v == nil then
        v = target
    else
        v = v + (target - v) * math.min(1, frame_dt * 18)
        if math.abs(v - target) < 0.004 then
            v = target
        end
    end
    anim[id] = v
    return v
end

-- A filled triangle, wound clockwise on screen as ImGui's anti-aliasing expects.
local function tri(dl, a, b, c, col)
    if (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) < 0 then
        b, c = c, b
    end
    dl:AddTriangleFilled(a, b, c, col)
end

local function glyph(dl, kind, cx, cy, hex, glyph_scale, alpha)
    local k = S(11) / 24 * (glyph_scale or 1)
    local col = u32(hex, alpha)
    local thickness = math.max(1, 2 * k)
    local function p(px, py)
        return { cx + (px - 12) * k, cy + (py - 12) * k }
    end
    if kind == 'right' then
        dl:AddLine(p(9, 5), p(16, 12), col, thickness)
        dl:AddLine(p(16, 12), p(9, 19), col, thickness)
    elseif kind == 'close' then
        dl:AddLine(p(6, 6), p(18, 18), col, thickness)
        dl:AddLine(p(18, 6), p(6, 18), col, thickness)
    elseif kind == 'cog' then
        -- Sidekick3's cog: eight teeth, one straight up, trapezoids from radius
        -- 7 to 12 round a body of 9. The hole of 4 is the window ground, which
        -- fades with the cog.
        dl:AddCircleFilled({ cx, cy }, 9 * k, col, 24)
        for i = 0, 7 do
            local a = i * math.pi / 4
            local dx, dy = math.sin(a), -math.cos(a)
            local function q(r, w)
                return { cx + (dx * r - dy * w) * k, cy + (dy * r + dx * w) * k }
            end
            local b1, b2, t1, t2 = q(7, -2.8), q(7, 2.8), q(12, -2.2), q(12, 2.2)
            tri(dl, b1, b2, t2, col)
            tri(dl, b1, t2, t1, col)
        end
        dl:AddCircleFilled({ cx, cy }, 4 * k, u32(HEX.bg, alpha), 24)
    else
        dl:AddLine(p(5, 9), p(12, 16), col, thickness)
        dl:AddLine(p(12, 16), p(19, 9), col, thickness)
    end
end

local folded = {}
-- chrome fades the frame, the title, and the gaps. A section plate stays
-- opaque: the header and the ground behind its rows do not take the fade.
local panel = { chrome = 0, hover = false, layered = false, plates = {} }

-- Stock Ashita's ImGui binds no draw-list channels, so a ground cannot slide
-- under text already drawn. There each ground is painted first: its spot is
-- the cursor now, and its size is the same piece's size last frame.
local grounds, grounds_next = {}, {}

local CHROME_PAD_X = 8
local BAR_PAD_X = 4
local ROW_PAD_X = 6
local ZONE_GAP = 8
local SECTION_GAP = 12
local TRAIN_PAD = 4
local SECTION_RADIUS = 4

local function indent_chrome()
    local x, y = imgui.GetCursorScreenPos()
    local pad = S(CHROME_PAD_X)
    if pad > 0 then
        imgui.SetCursorScreenPos({ x + pad, y })
    end
    return pad
end

local function mark_width(w)
    if w > (panel.fit_now or 0) then
        panel.fit_now = w
    end
end

local function piece_w(s)
    local w = imgui.CalcTextSize(tostring(s or ''))
    if type(w) == 'table' then
        return w.x or w[1] or 0
    end
    return w or 0
end

local function place_after(min_gap, item_w)
    local left_end = select(1, imgui.GetItemRectMax())
    local row_left = panel.row_x or left_end
    local natural = (left_end - row_left) + min_gap + item_w
    panel.natural = math.max(panel.natural or 0, natural)
    local fitted = (panel.fit_w or 0) - ROW_PAD_X
    if fitted < natural then
        fitted = natural
    end
    local gap = math.max(min_gap, fitted - (left_end - row_left) - item_w)
    imgui.SameLine(0, gap)
end

local function draw_section_header(text)
    local h = S(18)
    local x, y = imgui.GetCursorScreenPos()
    local title_font = face('semi_italic')
    local title = string.upper(text)
    local spacing = S(1.2)
    if spacing < 1 then
        spacing = 1
    end
    local title_w = text_spaced(nil, 0, 0, title, nil, title_font, SMALL, spacing)
    local btn_w = S(14) + title_w + S(6)
    imgui.InvisibleButton('##fold.' .. text, { btn_w, h })
    local hovered = imgui.IsItemHovered()
    if imgui.IsItemClicked(0) then
        folded[text] = not folded[text] or nil
    end
    local open = folded[text] ~= true
    -- A collapsed header follows the frame fade. An open one stays solid.
    local fade = open and 1 or panel.chrome
    if panel.section_mark then
        panel.section_mark.fade = fade
    end
    local t = ease('fold.' .. text, hovered and 1 or 0)
    local dl = imgui.GetWindowDrawList()
    local span = math.max(btn_w, panel.fit_w or 0)
    -- The section plate paints this when layers are on, or when last frame
    -- left its size. This covers the header otherwise.
    if not panel.layered and not (panel.section_mark and panel.section_mark.painted) then
        fill(dl, x, y, span, h, HEX.bg, S(SECTION_RADIUS), fade)
    end
    local cy = y + h / 2
    local color = mix(HEX.teal, HEX.white, t * 0.25)
    glyph(dl, open and 'down' or 'right', x + S(5), cy, hovered and HEX.teal or HEX.faint, nil, fade)
    text_spaced(dl, x + S(14), cy, title, color, title_font, SMALL, spacing, fade)
    local line_x = x + S(14) + title_w + S(8)
    local line_end = x + span
    if line_end > line_x + S(4) then
        dl:AddLine({ line_x, cy }, { line_end, cy }, u32(HEX.teal, 0.85 * fade), 1)
    end
    mark_width(btn_w)
    return open
end

local function show_tooltip(text)
    if text == nil or text == '' then
        return
    end
    imgui.PushStyleColor(ImGuiCol_PopupBg, rgba(HEX.popup, 0.97))
    imgui.PushStyleColor(ImGuiCol_Border, rgba(HEX.border))
    imgui.PushStyleColor(ImGuiCol_Text, rgba(HEX.text))
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { S(9), S(6) })
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, S(4))
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, S(4))
    imgui.PushStyleVar(ImGuiStyleVar_PopupBorderSize, 1)
    local pushed = push_window_font(SMALL + 0.5)
    -- ImGui 1.80 (stock Ashita) returns nothing here, and 1.92 always returns
    -- true. The tooltip is open either way. Skipping EndTooltip would pour the
    -- rest of the window into it.
    imgui.BeginTooltip()
    -- Before 1.92 the size is the tooltip window's font scale. Every addon
    -- shares that window, so the scale goes back to 1 before it closes.
    local sized = pushed and not DYNAMIC
    if sized then
        imgui.SetWindowFontScale(scale_for(SMALL + 0.5))
    end
    imgui.TextUnformatted(text)
    if sized then
        imgui.SetWindowFontScale(1)
    end
    imgui.EndTooltip()
    if pushed then
        imgui.PopFont()
    end
    imgui.PopStyleVar(4)
    imgui.PopStyleColor(3)
end

-- flush: the meter runs to the well's right edge, so it meets the level text.
local function paint_well(dl, x1, y1, well_w, row_h, fraction, bar_color, flush)
    local radius = S(3)
    -- Wells stay solid. The window frame's fade does not apply here.
    fill(dl, x1, y1, well_w, row_h, HEX.well, radius, 1)
    outline(dl, x1, y1, well_w, row_h, HEX.line, radius, 1)
    if fraction == nil or well_w <= S(8) then
        return
    end
    local mh = math.max(2, S(3))
    local mx = x1 + S(4)
    local mw = flush and (well_w - (mx - x1)) or (well_w - S(8))
    local my = y1 + row_h - S(2) - mh
    fill(dl, mx, my, mw, mh, HEX.off, mh / 2, 1)
    local frac = math.max(0, math.min(1, fraction or 0))
    if frac <= 0 then
        return
    end
    local meter = HEX.amber
    if bar_color == COLORS.dark_grey then
        meter = mix(HEX.amber, HEX.off, 0.45)
    end
    fill(dl, mx, my, math.max(mh, mw * frac), mh, meter, mh / 2, 1)
end

local function draw_bar(fraction, count_text, bar_color, content_fn, add_spacing, flush)
    local pad_y = S(1)
    local dl = imgui.GetWindowDrawList()
    -- outer: the window already split channels, so the well goes on the back
    -- channel and must not merge that split. inner: this row splits for itself.
    local layer = nil
    if panel.layered then
        layer = 'outer'
    else
        local ok_method, method = pcall(function() return dl.ChannelsSplit end)
        if ok_method and type(method) == 'function' then
            local split = pcall(function()
                dl:ChannelsSplit(2)
                dl:ChannelsSetCurrent(1)
            end)
            if split then
                layer = 'inner'
            end
        end
    end
    local ground_key = nil
    if layer == nil then
        panel.section_row = (panel.section_row or 0) + 1
        ground_key = 'well.' .. tostring(panel.section_key) .. '.' .. panel.section_row
        local size = grounds[ground_key]
        if size then
            local gx, gy = imgui.GetCursorScreenPos()
            paint_well(dl, gx, gy, size[1], size[2], fraction, bar_color, flush)
        end
    end

    imgui.BeginGroup()
    if pad_y > 0 then
        imgui.Dummy({ 0, pad_y })
    end
    local row_x = select(1, imgui.GetCursorScreenPos())
    panel.row_x = row_x
    panel.natural = nil
    imgui.Dummy({ ROW_PAD_X, 1 })
    imgui.SameLine(0, 0)
    if content_fn then
        content_fn()
    end
    if count_text and count_text ~= '' then
        place_after(S(8), piece_w(count_text))
        local hex = (bar_color == COLORS.grey_bar) and HEX.dim or HEX.text2
        imgui.TextColored(rgba(hex), count_text)
    end
    imgui.SameLine(0, 0)
    imgui.Dummy({ ROW_PAD_X, 1 })
    if fraction ~= nil then
        imgui.Dummy({ 0, S(4) })
    end
    if pad_y > 0 then
        imgui.Dummy({ 0, pad_y })
    end
    imgui.EndGroup()

    local x1, y1 = imgui.GetItemRectMin()
    local x2, y2 = imgui.GetItemRectMax()
    local row_w = math.max(1, x2 - x1)
    local row_h = math.max(1, y2 - y1)
    mark_width(panel.natural and (panel.natural + ROW_PAD_X) or row_w)
    local zone_w = 0
    if flush and panel.zone_right and panel.zone_right > x1 then
        zone_w = panel.zone_right - x1
    end
    local well_w = math.max(row_w, panel.fit_w or 0, zone_w)

    if layer == 'outer' then
        pcall(function() dl:ChannelsSetCurrent(1) end)
        paint_well(dl, x1, y1, well_w, row_h, fraction, bar_color, flush)
        pcall(function() dl:ChannelsSetCurrent(2) end)
    elseif layer == 'inner' then
        pcall(function() dl:ChannelsSetCurrent(0) end)
        paint_well(dl, x1, y1, well_w, row_h, fraction, bar_color, flush)
        pcall(function() dl:ChannelsMerge() end)
    else
        grounds_next[ground_key] = { well_w, row_h }
    end
    if add_spacing ~= false then
        imgui.Dummy({ 0, S(1) })
    end
end

local function draw_static(content_fn, add_spacing)
    draw_bar(nil, '', nil, content_fn, add_spacing, false)
end

local function draw_notice(text, hex)
    local h = S(18)
    local tw = measure(text, face('text'), SMALL + 1)
    local w = tw + S(10)
    local x, y = imgui.GetCursorScreenPos()
    imgui.Dummy({ w, h })
    mark_width(w)
    local dl = imgui.GetWindowDrawList()
    fill(dl, x, y, w, h, hex, S(3), 0.12)
    local left = ImDrawFlags_RoundCornersLeft or ImDrawCornerFlags_Left
    fill(dl, x, y, S(2), h, hex, S(2), 1, left)
    text_mid(dl, x + S(6), y + h / 2, text, hex, face('text'), SMALL + 1)
end

local style_count = 0

local function push_window_style()
    local colors = {
        { ImGuiCol_Text, rgba(HEX.text) },
        { ImGuiCol_TextDisabled, rgba(HEX.faint) },
        { ImGuiCol_WindowBg, rgba(HEX.bg, panel.chrome) },
        { ImGuiCol_ChildBg, rgba(HEX.bg, panel.chrome) },
        { ImGuiCol_PopupBg, rgba(HEX.popup, 0.97) },
        { ImGuiCol_Border, rgba(HEX.border, panel.chrome) },
        { ImGuiCol_Separator, rgba(HEX.line, panel.chrome) },
        { ImGuiCol_ScrollbarBg, rgba(HEX.bg, 0) },
        { ImGuiCol_ScrollbarGrab, rgba('#3A4158') },
        { ImGuiCol_ScrollbarGrabHovered, rgba('#4A5270') },
        { ImGuiCol_ScrollbarGrabActive, rgba(HEX.accent_lo) },
    }
    for _, entry in ipairs(colors) do
        imgui.PushStyleColor(entry[1], entry[2])
    end
    style_count = #colors
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { BAR_PAD_X, S(4) })
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, S(5))
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, S(3))
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, S(5))
    imgui.PushStyleVar(ImGuiStyleVar_PopupBorderSize, 1)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { S(4), S(2) })
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarSize, S(6))
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, S(3))
end

local function pop_window_style()
    imgui.PopStyleVar(9)
    imgui.PopStyleColor(style_count)
end

local function section_begin(title)
    local x, y = imgui.GetCursorScreenPos()
    local fade = folded[title] and panel.chrome or 1
    local mark = { x = x, y = y, fade = fade, key = 'plate.' .. title }
    panel.section_mark = mark
    panel.section_key, panel.section_row = title, 0
    local h = not panel.layered and grounds[mark.key]
    if h then
        fill(imgui.GetWindowDrawList(), x, y, panel.fit_w or 0, h, HEX.bg, S(SECTION_RADIUS), fade)
        mark.painted = (panel.fit_w or 0) > 0
    end
end

local function section_end()
    local mark = panel.section_mark
    panel.section_mark = nil
    if mark == nil then
        return
    end
    local _, y2 = imgui.GetItemRectMax()
    local _, cursor_y = imgui.GetCursorScreenPos()
    if cursor_y > y2 then
        y2 = cursor_y
    end
    if y2 <= mark.y then
        return
    end
    grounds_next[mark.key] = y2 - mark.y
    panel.plates[#panel.plates + 1] = {
        x = mark.x, y = mark.y, y2 = y2, fade = mark.fade or 1,
    }
end

-- The saved scale, held to the slider's range.
function ui.scale()
    local saved = dailies.settings()
    local n = saved and tonumber(saved.scale) or 1
    return math.max(SCALE_MIN, math.min(SCALE_MAX, n))
end

-- Held to the range and to hundredths, as the slider shows it. The slider
-- saves once it is let go.
function ui.set_scale(n)
    local saved = dailies.settings()
    n = tonumber(n)
    if saved == nil or n == nil then
        return false
    end
    n = math.max(SCALE_MIN, math.min(SCALE_MAX, n))
    saved.scale = math.floor(n * 100 + 0.5) / 100
    return true
end

-- The scale row under the title. It sits on a plate, so it stays opaque as
-- an open section does. The value moves with a drag, and the window takes it
-- up once the slider is let go.
local function draw_scale_slider()
    section_begin('Scale')
    local pad = indent_chrome()
    imgui.PushStyleColor(ImGuiCol_FrameBg, rgba(HEX.well))
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, rgba(HEX.hover))
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, rgba(HEX.hover))
    imgui.PushStyleColor(ImGuiCol_SliderGrab, rgba(HEX.teal))
    imgui.PushStyleColor(ImGuiCol_SliderGrabActive, rgba(HEX.accent2))
    imgui.BeginGroup()
    imgui.AlignTextToFramePadding()
    imgui.TextColored(rgba(HEX.text2), 'Scale')
    imgui.SameLine(0, S(8))
    imgui.SetNextItemWidth(S(130))
    local buf = { ui.scale() }
    local flags = ImGuiSliderFlags_AlwaysClamp
    local changed
    if flags then
        changed = imgui.SliderFloat('##tracker.scale', buf, SCALE_MIN, SCALE_MAX, '%.2fx', flags)
    else
        changed = imgui.SliderFloat('##tracker.scale', buf, SCALE_MIN, SCALE_MAX, '%.2fx')
    end
    local hovered = imgui.IsItemHovered()
    local held = imgui.IsItemActive() and true or false
    imgui.EndGroup()
    imgui.PopStyleColor(5)
    local x1 = select(1, imgui.GetItemRectMin())
    local x2 = select(1, imgui.GetItemRectMax())
    mark_width((x2 - x1) + pad)
    section_end()
    if changed then
        ui.set_scale(buf[1])
    end
    if panel.scale_held and not held then
        settingslib.save()
    end
    panel.scale_held = held
    if hovered and not held then
        show_tooltip('Window size. Taken up once the slider is let go.')
    end
end

local function draw_header()
    local pad = indent_chrome()
    local h = S(18)
    local x, y = imgui.GetCursorScreenPos()
    imgui.Dummy({ 0, h })
    local dl = imgui.GetWindowDrawList()
    local cy = y + h / 2
    local title_font = face('semi')
    text_mid(dl, x, cy, 'Tracker', HEX.white, title_font, BODY, panel.chrome)
    local title_w = measure('Tracker', title_font, BODY)

    local box = S(14) * 1.5
    local gap = S(4)
    local content_left = x - pad
    -- Title, a gap, the cog, a gap, the close mark, then S(6) before the content edge.
    local min_span = pad + title_w + S(10) + box + gap + box + S(6)
    local span = math.max(panel.fit_w or 0, min_span)
    local right = content_left + span
    local close_cx = right - S(6) - box / 2
    local cog_cx = close_cx - gap - box

    local function hit(id, cx)
        local rx, ry = imgui.GetCursorScreenPos()
        imgui.SetCursorScreenPos({ cx - box / 2, cy - box / 2 })
        imgui.InvisibleButton(id, { box, box })
        local hovered = imgui.IsItemHovered()
        local clicked = imgui.IsItemClicked(0)
        imgui.SetCursorScreenPos({ rx, ry })
        return hovered, clicked
    end

    local cog_hover, cog_click = hit('##tracker.cog', cog_cx)
    if cog_click then
        ui.scale_open = not ui.scale_open
    end
    local cog_color = (cog_hover or ui.scale_open) and HEX.teal or HEX.dim
    glyph(dl, 'cog', cog_cx, cy, cog_color, 1.1, panel.chrome)
    if cog_hover then
        show_tooltip('Scale')
    end

    local close_hover, close_click = hit('##tracker.close', close_cx)
    if close_click then
        ui.show[1] = false
        ui.scale_open = false
    end
    local close_color = close_hover and HEX.rose or HEX.dim
    glyph(dl, 'close', close_cx, cy, close_color, 1.5, panel.chrome)
    -- Mark what the header needs, not where the close mark landed. The close
    -- mark follows fit_w, so its spot would hold a too-wide frame for frames.
    mark_width(min_span - S(6))

    if ui.scale_open then
        draw_scale_slider()
    end

    local rule_y = select(2, imgui.GetCursorScreenPos())
    local rule_w = math.max(panel.fit_w or 0, close_cx + box / 2 - content_left)
    dl:AddLine({ content_left, rule_y }, { content_left + rule_w, rule_y }, u32(HEX.border, panel.chrome), 1)
    imgui.Dummy({ 0, S(2) })
end

local function section_gap()
    imgui.Dummy({ 0, S(SECTION_GAP) })
end

local function begin_layers(dl)
    panel.plates = {}
    panel.layered = false
    panel.section_mark = nil
    panel.section_key = nil
    if dl == nil or dl.ChannelsSplit == nil then
        return
    end
    local ok = pcall(function()
        dl:ChannelsSplit(3)
        dl:ChannelsSetCurrent(2)
    end)
    panel.layered = ok and true or false
end

-- Drawn on the back channel so row wells and labels stay above it.
-- An open plate stays opaque. A collapsed header uses the frame fade.
local function paint_plates(dl)
    local plates = panel.plates or {}
    panel.plates = {}
    local w = math.max(panel.fit_w or 0, panel.fit_now or 0)
    local function paint()
        if w < 1 then
            return
        end
        for _, plate in ipairs(plates) do
            fill(dl, plate.x, plate.y, w, plate.y2 - plate.y, HEX.bg, S(SECTION_RADIUS), plate.fade or 1)
        end
    end
    if not panel.layered then
        panel.layered = false
        return
    end
    local ok = pcall(function()
        dl:ChannelsSetCurrent(0)
        paint()
        dl:ChannelsMerge()
    end)
    panel.layered = false
    if not ok then
        pcall(function() dl:ChannelsMerge() end)
    end
end

local function draw_shadow()
    local ok, dl = pcall(imgui.GetBackgroundDrawList)
    if not ok or dl == nil then
        return
    end
    local x, y = imgui.GetWindowPos()
    local w, h = imgui.GetWindowSize()
    dl:AddRectFilled({ x - S(1), y + S(1) }, { x + w + S(1), y + h + S(3) }, u32('#000000', 0.35 * panel.chrome), S(6))
end

-- Links ------------------------------------------------------------------------

local PALALUMIN_ZONE_FIXUPS = {
    ['HuXzoi'] = "Hu'Xzoi",
    ['AlTaieu'] = "Al'Taieu",
    ['RuHmet'] = "Ru'Hmet",
}

local SINGULAR_NAMES = { gigas = true }

local function to_wiki_path(name)
    return name:gsub(' ', '_'):gsub("'", '%%27')
end

local function to_wiki_path_titled(name)
    local titled = name:gsub('(%a)([%w\']*)', function(first, rest)
        return first:upper() .. rest:lower()
    end)
    return titled:gsub(' ', '_'):gsub("'", '%%27')
end

local function singularize_simple(name)
    if #name > 1 and name:sub(-1) == 's' then
        return name:sub(1, -2)
    end
    return name
end

local function singularize_mob(name)
    local lower = name:lower()
    if SINGULAR_NAMES[lower] then
        return name
    end
    if #name > 3 and name:sub(-3):lower() == 'ies' then
        return name:sub(1, -4) .. 'y'
    end
    if #name > 3 and name:sub(-2):lower() == 'es' then
        local stem = name:sub(1, -3)
        local tail = stem:sub(-2):lower()
        local last = stem:sub(-1):lower()
        if last == 's' or last == 'x' or last == 'z' or tail == 'ch' or tail == 'sh' then
            return stem
        end
    end
    if #name > 1 and name:sub(-1):lower() == 's' and name:sub(-2, -2):lower() ~= 's' then
        return name:sub(1, -2)
    end
    return name
end

local function title_case(name)
    return (name:gsub('(%a)([%w\']*)', function(first, rest)
        return first:upper() .. rest:lower()
    end))
end

local function draw_interactive_text(text, color, tooltip_text, on_click_fn)
    imgui.TextColored(color, text)
    local min_x, min_y = imgui.GetItemRectMin()
    local max_x, max_y = imgui.GetItemRectMax()
    local hovered = imgui.IsItemHovered()
    local draw_list = imgui.GetWindowDrawList()
    local hot = hovered and color == COLORS.link
    if hot then
        draw_list:AddText({ min_x, min_y }, u32(HEX.accent2), text)
    end
    local a = math.floor((color[4] or 1.0) * 255)
    local b = math.floor((color[3] or 0) * 255)
    local g = math.floor((color[2] or 0) * 255)
    local r = math.floor((color[1] or 0) * 255)
    local col_u32 = hot and u32(HEX.accent2) or bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(g, 8), r)
    draw_list:AddLine({ min_x, max_y }, { max_x, max_y }, col_u32, 1.0)
    if hovered then
        show_tooltip(tooltip_text)
    end
    if imgui.IsItemClicked(0) then
        on_click_fn()
    end
end

local function open_url(url)
    os.execute('start "" "' .. tostring(url):gsub('"', '') .. '"')
end

local function draw_link(text, color, url, tooltip)
    draw_interactive_text(text, color, tooltip or ('Open FFXI Wiki: ' .. text), function()
        open_url(url)
    end)
end

local function draw_command_link(text, color, command, tooltip)
    draw_interactive_text(text, color, tooltip or command, function()
        AshitaCore:GetChatManager():QueueCommand(1, command)
    end)
end

local function draw_zone_link(zone_name, color, is_palalumin)
    local wiki_name = zone_name
    if is_palalumin then
        for pattern, replacement in pairs(PALALUMIN_ZONE_FIXUPS) do
            wiki_name = wiki_name:gsub(pattern, replacement)
        end
    end
    draw_link(zone_name, color, 'https://www.bg-wiki.com/ffxi/' .. to_wiki_path(wiki_name))
end

local function draw_mob_link(mob_name, color)
    local singular = singularize_simple(mob_name)
    draw_link(mob_name, color, 'https://www.bg-wiki.com/ffxi/Category:' .. to_wiki_path_titled(singular))
end

local function draw_nm_link(nm_name, color)
    draw_link(nm_name, color, 'https://www.bg-wiki.com/ffxi/' .. to_wiki_path_titled(nm_name))
end

local function draw_item_link(item_name, color)
    draw_link(item_name, color, 'https://www.bg-wiki.com/ffxi/' .. to_wiki_path_titled(item_name))
end

local function draw_family_link(family_type, color)
    local display = title_case(family_type)
    local wiki_name = display
    if display:lower() == 'bats' then
        wiki_name = 'Bat'
    end
    draw_link(display, color, 'https://www.bg-wiki.com/ffxi/Category:' .. to_wiki_path_titled(wiki_name))
end

local function draw_exact_mob_link(mob_name, color)
    draw_link(mob_name, color, 'https://www.bg-wiki.com/ffxi/' .. to_wiki_path_titled(singularize_mob(mob_name)))
end

local function draw_kill_at(target, zone, label_color, highlight_color, opts)
    opts = opts or {}
    imgui.TextColored(label_color, 'Kill ')
    imgui.SameLine()
    if opts.mob_link then
        draw_mob_link(target, highlight_color)
    else
        draw_nm_link(target, highlight_color)
    end
    imgui.SameLine()
    imgui.TextColored(label_color, ' at ')
    imgui.SameLine()
    draw_zone_link(zone, highlight_color, opts.palalumin)
end

local function progress_colors(is_done)
    if is_done then
        return COLORS.grey_text, COLORS.grey_text
    end
    return COLORS.white, COLORS.link
end

-- Sections ---------------------------------------------------------------------

local SEA = 'https://discord.com/channels/696847769444548700/1359317001457242192'

local TRADE_LABEL = 'Trade'

local function trade_button_size()
    local tw, th = imgui.CalcTextSize(TRADE_LABEL)
    if type(tw) == 'table' then
        th = tw.y or tw[2] or 0
        tw = tw.x or tw[1] or 0
    end
    tw = tonumber(tw) or 0
    th = tonumber(th) or 0
    local pad_x = S(6)
    local pad_y = S(1)
    return tw + pad_x * 2, th + pad_y * 2, pad_x, th
end

-- The hit target is invisible. The face drawn over it is the button, so a
-- pending turn-in can go gray without a second widget.
local function draw_trade_button(state)
    local w, h, pad_x, th = trade_button_size()
    pcall(imgui.AlignTextToFramePadding)
    imgui.InvisibleButton('##pala.trade', { w, h })
    local ready = state == 'ready'
    local hot = ready and imgui.IsItemHovered()
    local clicked = imgui.IsItemClicked(0)
    local x1, y1 = imgui.GetItemRectMin()
    local _, y2 = imgui.GetItemRectMax()
    local dl = imgui.GetWindowDrawList()
    local bg = HEX.off
    local fg = HEX.dim
    local edge = HEX.faint
    if ready then
        bg = hot and HEX.accent or HEX.accent_lo
        fg = HEX.white
        edge = HEX.accent
    end
    fill(dl, x1, y1, w, h, bg, S(3), 1)
    outline(dl, x1, y1, w, h, edge, S(3), 1)
    dl:AddText({ x1 + pad_x, (y1 + y2) / 2 - th / 2 }, u32(fg), TRADE_LABEL)
    if hot then
        show_tooltip('Trade these items to Palalumin')
    end
    return ready and clicked and true or false
end

local function draw_goblins(saved)
    local rows = saved.dailies or {}
    local completed = 0
    for _, npc in ipairs(dailies.order) do
        local row = rows[npc]
        if row ~= nil then
            if dailies.is_complete(row) then
                completed = completed + 1
            elseif row.status == 'return' then
                draw_bar(1, '', COLORS.grey_bar, function()
                    imgui.TextColored(COLORS.grey_text, 'Return to ' .. npc .. '.')
                end)
            elseif npc == 'Fishstix' and row.zone then
                local right_text = row.hint or '/huh motion'
                draw_static(function()
                    imgui.TextColored(COLORS.white, 'Secret chest at ')
                    imgui.SameLine()
                    draw_zone_link(row.zone, COLORS.link)
                    place_after(S(12), piece_w(right_text))
                    draw_command_link(right_text, COLORS.link, '/huh motion', 'Send /huh motion')
                end)
            elseif npc == 'Murdox' and row.count and row.target and row.zone then
                local total = tonumber(row.count) or 0
                local remaining = tonumber(row.remaining or row.count) or 0
                local killed = total - remaining
                local is_done = total > 0 and killed >= total
                local fraction = (total > 0) and (killed / total) or 0
                local count_text = string.format('%d/%d', killed, total)
                local label_color, highlight_color = progress_colors(is_done)
                local bar_color = is_done and COLORS.grey_bar or nil
                draw_bar(fraction, count_text, bar_color, function()
                    draw_kill_at(row.target, row.zone, label_color, highlight_color, { mob_link = true })
                end)
            elseif npc == 'Mistrix' and row.item then
                draw_static(function()
                    imgui.TextColored(COLORS.white, 'Trade a signed ')
                    imgui.SameLine()
                    draw_item_link(row.item, COLORS.link)
                    imgui.SameLine()
                    imgui.TextColored(COLORS.white, ' ')
                end)
            elseif npc == 'Saltlix' and row.target and row.zone then
                draw_static(function()
                    draw_kill_at(row.target, row.zone, COLORS.white, COLORS.link)
                end)
            elseif npc == 'Beetrix' and row.item and row.zone then
                local have = dailies.item_count(row.item)
                local has_item = have and have >= 1
                local fraction = has_item and 1 or 0
                local bar_color = has_item and COLORS.grey_bar or COLORS.dark_grey
                local label_color, highlight_color = progress_colors(has_item)
                local count_text = have and (tostring(math.min(have, 1)) .. '/1') or '?/1'
                draw_bar(fraction, count_text, bar_color, function()
                    imgui.TextColored(label_color, 'Trade ')
                    imgui.SameLine()
                    draw_item_link(row.item, highlight_color)
                    imgui.SameLine()
                    imgui.TextColored(label_color, ' found at ')
                    imgui.SameLine()
                    draw_zone_link(row.zone, highlight_color)
                end)
            else
                local text = dailies.goblin_line(npc, row)
                if text then
                    draw_static(function()
                        imgui.TextColored(COLORS.white, parse.strip(text))
                    end)
                end
            end
        end
    end
    if completed > 0 and saved.goldilox_time ~= saved.deadline then
        draw_notice('Goldilox: Reward not collected.', HEX.amber)
    end
end

local function draw_palalumin(saved)
    local rows = saved.palalumin_quests or {}
    local flagged = 0
    local known = 0
    local header_open = true
    for _, name in ipairs(dailies.pala_order) do
        local row = rows[name]
        if row then
            known = known + 1
        end
        if row and not row.completed then
            flagged = flagged + 1
            if flagged == 1 then
                header_open = draw_section_header('Palalumin Quests')
                if not header_open then
                    break
                end
            end
            if name == 'Item request' and row.items then
                local items = {}
                for entry in row.items:gmatch('([^,]+)') do
                    entry = entry:match('^%s*(.-)%s*$')
                    local item_name, needed = parse.item_need(entry)
                    items[#items + 1] = { name = item_name, needed = needed, have = dailies.item_count(item_name) }
                end
                local total_have, total_needed, any_unknown = 0, 0, false
                for _, item in ipairs(items) do
                    total_needed = total_needed + item.needed
                    if item.have == nil then
                        any_unknown = true
                    else
                        total_have = total_have + math.min(item.have, item.needed)
                    end
                end
                local all_satisfied = (not any_unknown) and (total_have >= total_needed)
                local fraction = (total_needed > 0) and (total_have / total_needed) or 0
                local bar_color = all_satisfied and COLORS.grey_bar or (any_unknown and COLORS.dark_grey or nil)
                local summary_label, summary_highlight = progress_colors(all_satisfied)
                draw_bar(fraction, '', bar_color, function()
                    imgui.TextColored(summary_label, 'Trade ')
                    for i, item in ipairs(items) do
                        imgui.SameLine()
                        draw_item_link(item.name, summary_highlight)
                        imgui.SameLine()
                        local have_str = item.have and tostring(item.have) or '?'
                        local suffix = ' ' .. have_str .. '/' .. item.needed
                        if i < #items then
                            suffix = suffix .. ','
                        end
                        imgui.TextColored(summary_label, suffix)
                    end
                    imgui.SameLine()
                    imgui.TextColored(summary_label, ' ')
                    local offer = dailies.trade_button(items)
                    if offer then
                        place_after(S(12), trade_button_size())
                        if draw_trade_button(offer) then
                            dailies.trade_start(items)
                        end
                    end
                end, false)
            elseif name == 'Defeat mobs' and (row.killed and row.total or row.completed) then
                local killed = row.killed or 0
                local total = row.total or 0
                local is_done = row.completed or (total > 0 and killed >= total)
                local fraction = (total > 0) and (killed / total) or (is_done and 1 or 0)
                local count_text = (total > 0) and string.format('%d/%d', killed, total) or 'Done'
                local label_color, highlight_color = progress_colors(is_done)
                local bar_color = is_done and COLORS.grey_bar or nil
                draw_bar(fraction, count_text, bar_color, function()
                    draw_kill_at(row.target or 'mobs', row.zone or '?', label_color, highlight_color, { mob_link = true, palalumin = true })
                end, false)
            elseif name == 'Find flux' and row.zone then
                draw_bar(nil, '', nil, function()
                    imgui.TextColored(COLORS.white, 'Find the Flux in ')
                    imgui.SameLine()
                    draw_zone_link(row.zone, COLORS.link, true)
                    place_after(S(16), piece_w('#sea'))
                    draw_link('#sea', COLORS.link, SEA, 'Open CatsEyeXI Discord Channel #sea')
                end, false)
            else
                local text = dailies.pala_line(name, row)
                if text then
                    draw_static(function()
                        imgui.TextColored(COLORS.white, parse.strip(text))
                    end, false)
                end
            end
        end
    end
    if flagged == 0 and known < #dailies.pala_order then
        if draw_section_header('Palalumin Quests') then
            draw_notice('Quests active', HEX.amber)
        end
    end
end

local function draw_regime_line(state)
    local zone = state.training_area_zone
    if type(zone) == 'string' then
        zone = zone:match('^%s*(.-)%s*$')
        if zone == '' then
            zone = nil
        end
    else
        zone = nil
    end
    local level = state.target_level_range
    if type(level) ~= 'string' or level == '' then
        level = nil
    end
    if not zone and not level then
        return
    end

    local origin_x, origin_y = imgui.GetCursorScreenPos()
    local start_x = origin_x + TRAIN_PAD
    imgui.SetCursorScreenPos({ start_x, origin_y })
    if zone then
        imgui.TextColored(COLORS.white, 'Training in')
        imgui.SameLine(0, ZONE_GAP)
        draw_zone_link(zone, COLORS.link)
    else
        imgui.TextColored(COLORS.orange, 'Training area unknown')
    end
    local left_end = select(1, imgui.GetItemRectMax())
    local natural = TRAIN_PAD + (left_end - start_x)
    if level then
        local level_text = 'Lv ' .. level
        local level_w = piece_w(level_text)
        natural = natural + ZONE_GAP + level_w + TRAIN_PAD
        local fitted = math.max(natural, panel.fit_w or 0)
        local target_right = origin_x + fitted - TRAIN_PAD
        local gap = target_right - left_end - level_w
        if gap < ZONE_GAP then
            gap = ZONE_GAP
        end
        imgui.SameLine(0, gap)
        imgui.TextColored(rgba(HEX.text2), level_text)
    end
    panel.zone_right = select(1, imgui.GetItemRectMax())
    mark_width(natural)
    imgui.Dummy({ 0, S(2) })
end

local function regime_complete(enemies)
    local any = false
    for _, enemy in ipairs(enemies) do
        local total = tonumber(enemy.total) or 0
        local killed = tonumber(enemy.killed) or 0
        if total > 0 then
            any = true
            if killed < total then
                return false
            end
        end
    end
    return any
end

local function draw_enemies(state)
    draw_regime_line(state)
    for _, enemy in ipairs(state.enemies) do
        local killed = tonumber(enemy.killed) or 0
        local total = tonumber(enemy.total) or 0
        if killed < 0 then
            killed = 0
        end
        local is_done = total > 0 and killed >= total
        local fraction = 0
        if total > 0 then
            fraction = killed / total
            if fraction > 1 then
                fraction = 1
            end
        end
        local label_color, highlight_color = progress_colors(is_done)
        local bar_color = is_done and COLORS.grey_bar or nil
        local family_type = family.extract_family_type(enemy.name or '')
        draw_bar(fraction, string.format('%d/%d', killed, total), bar_color, function()
            if family_type then
                imgui.TextColored(label_color, 'Members of the ')
                imgui.SameLine()
                draw_family_link(family_type, highlight_color)
                imgui.SameLine()
                imgui.TextColored(label_color, ' Family')
            else
                draw_exact_mob_link(enemy.name or 'Unknown', highlight_color)
            end
        end, true, true)
    end
    if regime_complete(state.enemies) then
        draw_notice('Regime complete', HEX.teal)
    end
end

local function has_goblin(saved)
    local rows = saved.dailies or {}
    local completed = 0
    for _, npc in ipairs(dailies.order) do
        local row = rows[npc]
        if row ~= nil then
            if not dailies.is_complete(row) then
                return true
            end
            completed = completed + 1
        end
    end
    return completed > 0 and saved.goldilox_time ~= saved.deadline
end

local function has_pala(saved)
    if not saved.palalumin_flagged then
        return false
    end
    local rows = saved.palalumin_quests or {}
    local known = 0
    for _, name in ipairs(dailies.pala_order) do
        local row = rows[name]
        if row then
            known = known + 1
            if not row.completed then
                return true
            end
        end
    end
    return known < #dailies.pala_order
end

local function has_aman()
    local state = regime.view()
    return state.is_active and type(state.enemies) == 'table' and #state.enemies > 0
end

-- Layout -----------------------------------------------------------------------

local LAYOUT_WINDOW = 'Tracker'

local function vana_layout()
    local api = rawget(_G, 'vana')
    local layout = api and api.layout
    if layout == nil or layout.set == nil then
        return nil
    end
    return api, layout
end

local function layout_file_has_window(root)
    local file = io.open(root .. '\\config\\layout.json', 'rb')
    if file == nil then
        return false
    end
    local text = file:read('*a') or ''
    file:close()
    return text:find('"Tracker":', 1, true) ~= nil
end

local function imgui_ini_pos(root)
    local file = io.open(root .. '\\config\\imgui.ini', 'rb')
    if file == nil then
        return nil
    end
    local text = file:read('*a') or ''
    file:close()
    local x, y = text:match('%[Window%]%[Tracker%]\r?\nPos=(%-?%d+),(%-?%d+)')
    if x == nil then
        return nil
    end
    return tonumber(x), tonumber(y)
end

local function register_layout(x, y)
    if ui._layout_set then
        return
    end
    local api, layout = vana_layout()
    if api == nil then
        return
    end
    local root = api.paths and api.paths.install
    if type(root) == 'string' and layout_file_has_window(root) then
        ui._layout_set = true
        return
    end
    if x == nil or y == nil then
        if type(root) ~= 'string' then
            return
        end
        x, y = imgui_ini_pos(root)
    end
    if type(x) ~= 'number' or type(y) ~= 'number' then
        return
    end
    if pcall(layout.set, LAYOUT_WINDOW, x, y, 1) then
        ui._layout_set = true
    end
end

local function loading()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if not player then
        return true
    end
    local level = player:GetMainJobLevel()
    return not level or level == 0
end

function ui.open()
    ui.show[1] = true
end

function ui.close()
    ui.show[1] = false
end

function ui.toggle()
    ui.show[1] = not ui.show[1]
end

function ui.visible()
    return ui.show[1] and true or false
end

function ui.render()
    register_layout()
    if not ui.show[1] then
        return
    end
    if loading() then
        return
    end
    local saved = dailies.settings()
    if saved == nil then
        return
    end

    local show_goblin = has_goblin(saved)
    local show_pala = has_pala(saved)
    local show_aman = has_aman()
    if not show_goblin and not show_pala and not show_aman then
        return
    end

    dailies.begin_frame()
    if not panel.scale_held then
        user_scale = ui.scale()
    end
    update_scale()
    tick()
    -- Last frame's hover drives this frame, because the window background is
    -- chosen before Begin. The fade uses that same value for the title.
    panel.chrome = ease('chrome', panel.hover and 1 or 0)

    imgui.SetNextWindowSizeConstraints({ 0, 0 }, { FLT_MAX, FLT_MAX })
    local win_flags = bit.bor(
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_NoScrollWithMouse,
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoNavInputs
    )
    if not ui.shift_held then
        win_flags = bit.bor(win_flags, ImGuiWindowFlags_NoMove)
    end

    push_window_style()
    local font_pushed = push_window_font(BODY)
    if imgui.Begin(LAYOUT_WINDOW, ui.show, win_flags) then
        if font_pushed and not DYNAMIC then
            scales, window_scale = {}, scale_for(BODY)
            imgui.SetWindowFontScale(window_scale)
        end
        local place_x, place_y = imgui.GetWindowPos()
        register_layout(place_x, place_y)
        if imgui.IsWindowHovered then
            panel.hover = imgui.IsWindowHovered() and true or false
        end
        panel.fit_now = 0
        panel.zone_right = nil
        local layers = imgui.GetWindowDrawList()
        begin_layers(layers)
        draw_header()
        local shown = false
        if show_goblin then
            section_begin('Goblin Dailies')
            if draw_section_header('Goblin Dailies') then
                draw_goblins(saved)
            end
            section_end()
            shown = true
        end
        if show_pala then
            if shown then
                section_gap()
            end
            section_begin('Palalumin Quests')
            draw_palalumin(saved)
            section_end()
            shown = true
        end
        if show_aman then
            if shown then
                section_gap()
            end
            section_begin('AMAN Targets')
            if draw_section_header('AMAN Targets') then
                draw_enemies(regime.view())
            end
            section_end()
        end
        if (panel.fit_now or 0) > 0 then
            panel.fit_w = panel.fit_now
        end
        paint_plates(layers)
        grounds, grounds_next = grounds_next, {}
        draw_shadow()
    end
    imgui.End()
    if font_pushed then
        imgui.PopFont()
    end
    pop_window_style()
end

return ui
