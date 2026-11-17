--[[
Tracker - Magian trials.

Each objective prints "Trial 1010: 155 objectives remain." (message 583).
That line gives what is left, not the total. The total comes from the
server's trial list in lib/trial_data.lua. For a trial not in that list, the
first line heard is taken to follow its first objective, so the total is one
more than that line leaves. /tracker trial <number> <total> sets a total by
hand, and that total stays. "You have completed Trial 1010." (584) finishes
the trial. Its row stays until a Magian Moogle takes the report: a trade to
the moogle, then its "Obtained: <reward>." Trials do not roll with the day.
]]

local settingslib = require('settings')
local trade = require('lib.trade')
local items = require('lib.items')
local trial_data = require('lib.trial_data')

local trials = {}

local cfg

-- When this character last traded to a Magian Moogle. Its "Obtained:
-- <reward>." reports a finished trial only through the event that trade
-- starts and REPORT_WINDOW seconds past it. Backing out of the reward, or a
-- trade the moogle turns down, prints no reward, so the trial stays.
local report_at = nil
local REPORT_WINDOW = 10
-- Where that trade's event is: 'waiting' for it to start, 'open', or
-- 'closed'. A later event does not hold the window open.
local report_event = nil

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

local function known(number)
    local entry = trial_data[tonumber(number)]
    if entry == nil then
        return nil, nil
    end
    return entry.total, entry.reward
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
    -- "Obtained key item: ..." has no colon right after Obtained.
    local item = text:match('^[^%a]*Obtained: (.-)%.?%s*$')
    if item and item ~= '' then
        return { kind = 'obtained', item = item }
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
    local total = tonumber(own(row, 'total')) or known(number)
    if total == nil or remaining >= total then
        total = remaining + 1
    end
    row.total = total
end

local function complete(number)
    local row = find(number) or add(number)
    row.completed = true
    row.remaining = 0
    if own(row, 'total') == nil then
        row.total = known(number)
    end
end

local function report_arm()
    report_at = os.clock()
    report_event = 'waiting'
end

local function report_disarm()
    report_at = nil
    report_event = nil
end

-- True while this character's last trade to a Magian Moogle can still be
-- what an "Obtained:" line is for. Runs every frame, so a long event keeps
-- it. Only the first event after the trade does.
local function reporting()
    if report_at == nil then
        return false
    end
    local now = os.clock()
    if trade.in_event() and report_event ~= 'closed' then
        report_event = 'open'
        report_at = now
    elseif report_event == 'open' then
        report_event = 'closed'
    end
    if now - report_at > REPORT_WINDOW then
        report_disarm()
        return false
    end
    return true
end

-- One reward reports one trial: the first finished trial whose reward is
-- that item. Several trials can share a reward. A finished trial not in the
-- list has no known reward, so a reward no listed trial matches reports the
-- first of those.
local function report(item)
    local listed, unlisted
    for _, row in ipairs(cfg.trials) do
        if finished(row) then
            local _, reward = known(own(row, 'number'))
            if reward == nil then
                unlisted = unlisted or row
            elseif listed == nil and items.named(reward, item) then
                listed = row
            end
        end
    end
    local reported = listed or unlisted
    if reported == nil then
        return false
    end
    for i, row in ipairs(cfg.trials) do
        if row == reported then
            table.remove(cfg.trials, i)
            break
        end
    end
    return true
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
    if event.kind == 'obtained' then
        if not reporting() or not report(event.item) then
            return false
        end
        report_disarm()
    elseif event.kind == 'progress' then
        progress(event.number, event.remaining)
    else
        complete(event.number)
    end
    save()
    return true
end

-- Every 0x036 this client sends. One to a Magian Moogle opens the report
-- window. A trade to anyone else is newer, so it ends that window.
function trials.on_trade(data)
    local name = trade.recipient(data)
    if name ~= nil and name:find('Magian', 1, true) then
        report_arm()
    else
        report_disarm()
    end
end

-- Every frame, so a long moogle event holds the report window open.
function trials.update()
    reporting()
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
