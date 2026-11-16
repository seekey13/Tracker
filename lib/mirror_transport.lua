--[[
Tracker - the file the mirror's leader writes and its followers read.

Ashita gives one client no way to message another, so a pick travels through
config\addons\Tracker\mirror_channel.txt. Only clients that share that folder
see each other. The file holds one record:

    TRACKER-MIRROR-1|<payload>
    #END

A reader that catches the file half written finds no #END, drops it, and
reads the whole record on its next poll.
]]

local transport = {}

local PROTOCOL = 'TRACKER-MIRROR-1'
local TERMINATOR = '#END'

local channel_path = nil
-- The last payload read or written here. Every record carries a sequence
-- number and a time, so two picks never make the same payload.
local last_seen = nil
local last_error = nil

local function default_path()
    local install = ''
    pcall(function()
        install = AshitaCore:GetInstallPath() or ''
    end)
    if install ~= '' and not install:match('[\\/]$') then
        install = install .. '\\'
    end
    return install .. 'config\\addons\\Tracker\\mirror_channel.txt'
end

--- Point the channel at a file. No path means Ashita's config folder.
function transport.init(path)
    channel_path = path or default_path()
    last_seen = nil
    last_error = nil
end

function transport.path()
    if channel_path == nil then
        channel_path = default_path()
    end
    return channel_path
end

--- Why the last publish failed, or nil when it went out.
function transport.last_error()
    return last_error
end

local function read_record()
    local handle = io.open(transport.path(), 'rb')
    if handle == nil then
        return nil
    end
    local body = handle:read('*a')
    handle:close()
    if body == nil then
        return nil
    end
    -- Plain compares: the hyphens in PROTOCOL are pattern magic.
    local trimmed = (body:gsub('%s+$', ''))
    if trimmed:sub(-#TERMINATOR) ~= TERMINATOR then
        return nil
    end
    local line_end = trimmed:find('\n', 1, true)
    local line = line_end and trimmed:sub(1, line_end - 1) or trimmed
    line = (line:gsub('\r$', ''))
    local prefix = PROTOCOL .. '|'
    if line:sub(1, #prefix) ~= prefix then
        return nil
    end
    return line:sub(#prefix + 1)
end

--- Count whatever is in the file as already handled, so turning the mirror
--- on never repeats an old pick.
function transport.prime()
    last_seen = read_record()
end

--- Replace the record. False when the file could not be written.
function transport.publish(payload)
    local path = transport.path()
    local dir = path:match('^(.*)[\\/][^\\/]*$')
    if dir ~= nil then
        pcall(function()
            ashita.fs.create_dir(dir)
        end)
    end
    local handle, err = io.open(path, 'wb')
    if handle == nil then
        last_error = err or ('could not open ' .. path)
        return false
    end
    local ok = handle:write(PROTOCOL .. '|' .. payload .. '\n' .. TERMINATOR .. '\n')
    handle:close()
    if not ok then
        last_error = 'write failed: ' .. path
        return false
    end
    last_seen = payload
    last_error = nil
    return true
end

--- A payload this client has not handled yet, or nil.
function transport.poll()
    local payload = read_record()
    if payload == nil or payload == last_seen then
        return nil
    end
    last_seen = payload
    return payload
end

return transport
