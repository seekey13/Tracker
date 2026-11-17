--[[
Tracker - Magian trials.

Each objective prints "Trial 1010: 155 objectives remain." (message 583).
That line gives what is left, not the total. The first line heard for a
trial follows its first objective, so the total is one more than that line
leaves. /tracker trial <number> <total> sets the total for a trial already
under way. "You have completed Trial 1010." (584) finishes the trial. Its
row stays until a trade to a Magian Moogle reports it. Trials do not roll
with the day.
]]

local settingslib = require('settings')
local trade = require('lib.trade')

local trials = {}

local cfg

local function save()
    settingslib.save()
end

-- A row read back from the settings file is a T{}, which answers a missing
-- field from the table library.
local function own(row, key)
    if type(row) ~= 'table' then
        return nil
    end
    return rawget(row, key)
end

local function finished(row)
    return own(row, 'completed') == true or tonumber(own(row, 'remaining')) == 0
end

local function find(number)
    if cfg == nil then
        return nil
    end
    for i, row in ipairs(cfg.trials) do
        if tonumber(own(row, 'number')) == number then
            return row, i
        end
    end
    return nil
end

local function add(number)
    local row = { number = number }
    cfg.trials[#cfg.trials + 1] = row
    return row
end

function trials.bind(saved)
    cfg = saved
    if type(cfg.trials) ~= 'table' then
        cfg.trials = {}
    end
end

function trials.list()
    return cfg and cfg.trials or {}
end

function trials.label(row)
    return 'Trial-' .. tostring(own(row, 'number') or '?')
end

-- done, total, and whether the trial is finished. done and total are nil
-- while the total is unknown.
function trials.progress(row)
    local total = tonumber(own(row, 'total'))
    local over = finished(row)
    if total == nil then
        return nil, nil, over
    end
    local remaining = tonumber(own(row, 'remaining')) or total
    local done = over and total or (total - remaining)
    return math.max(0, math.min(total, done)), total, over
end

-- Chat a player types has a name before it, so the line must open with the
-- trial. A timestamp ahead of it has no letters.
function trials.read(text)
    text = tostring(text or '')
    local number, left = text:match('^[^%a]*Trial (%d+): (%d+) objectives? remains?%.')
    if number then
        return { kind = 'progress', number = tonumber(number), remaining = tonumber(left) }
    end
    number = text:match('^[^%a]*You have completed Trial (%d+)%.')
    if number then
        return { kind = 'complete', number = tonumber(number) }
    end
    return nil
end

local function progress(number, remaining)
    local row, index = find(number)
    -- A finished trial's number heard again is that trial taken anew.
    if row and finished(row) then
        table.remove(cfg.trials, index)
        row = nil
    end
    row = row or add(number)
    row.remaining = remaining
    local total = tonumber(own(row, 'total'))
    if total == nil or remaining >= total then
        row.total = remaining + 1
    end
end

local function complete(number)
    local row = find(number) or add(number)
    row.completed = true
    row.remaining = 0
end

-- True when the line was a trial's.
function trials.on_text(text)
    if cfg == nil then
        return false
    end
    local event = trials.read(text)
    if event == nil then
        return false
    end
    if event.kind == 'progress' then
        progress(event.number, event.remaining)
    else
        complete(event.number)
    end
    save()
    return true
end

-- Reporting a finished trial is trading its item to a Magian Moogle. Every
-- finished trial leaves then. One still under way stays.
function trials.on_trade(data)
    if cfg == nil then
        return
    end
    local name = trade.recipient(data)
    if name == nil or not name:find('Magian', 1, true) then
        return
    end
    local kept = {}
    for _, row in ipairs(cfg.trials) do
        if not finished(row) then
            kept[#kept + 1] = row
        end
    end
    if #kept ~= #cfg.trials then
        cfg.trials = kept
        save()
    end
end

-- False when the trial already has more than total objectives left.
function trials.set_total(number, total)
    if cfg == nil then
        return false
    end
    local row = find(number)
    local remaining = tonumber(own(row, 'remaining'))
    if remaining and total < remaining then
        return false
    end
    row = row or add(number)
    row.total = total
    save()
    return true
end

-- One trial by number, or every trial. Returns how many left.
function trials.clear(number)
    if cfg == nil then
        return 0
    end
    local removed = 0
    if number == nil then
        removed = #cfg.trials
        cfg.trials = {}
    else
        local _, index = find(number)
        if index then
            table.remove(cfg.trials, index)
            removed = 1
        end
    end
    if removed > 0 then
        save()
    end
    return removed
end

function trials.line(row)
    local done, total, over = trials.progress(row)
    if over then
        return trials.label(row) .. ': Complete! Report to a Magian Moogle.'
    end
    if total then
        return string.format('%s: %d/%d', trials.label(row), done, total)
    end
    return string.format('%s: %s left', trials.label(row), tostring(own(row, 'remaining') or '?'))
end

function trials.report(say)
    local list = trials.list()
    if #list == 0 then
        say('No trials tracked.')
        return
    end
    for _, row in ipairs(list) do
        say('%s', trials.line(row))
    end
end

return trials
