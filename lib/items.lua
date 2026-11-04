--[[
Tracker - item ids for the names quests give.

A quest can name its item in full, as Beetrix's "Scholar's Testimony", where
the client's own name for it is cut short ("Sch. Testimony"). GetItemByName
knows only the short name. The full one is the item's log name, which nothing
looks an item up by, so a name GetItemByName does not know is compared with
both names of each item carried in the inventory.
]]

local items = {}

-- Ids by lowercased name, once found. The button asks every frame, and a
-- name search walks the whole item table. Names and ids do not change.
local ids = {}
-- Each item id's lowercased short and log names.
local names_by_id = {}

local function trim(name)
    if type(name) ~= 'string' then
        return ''
    end
    return (name:match('^%s*(.-)%s*$'))
end

local function resources()
    local ok, res = pcall(function()
        return AshitaCore:GetResourceManager()
    end)
    if ok then
        return res
    end
    return nil
end

local function by_name(res, name)
    for _, lang in ipairs({ 0, 1, 2, 3 }) do
        local ok, id = pcall(function()
            local item = res:GetItemByName(name, lang)
            if item == nil then
                return nil
            end
            return item.Id
        end)
        if ok and type(id) == 'number' and id > 0 then
            return id
        end
    end
    return nil
end

-- The item's own name and its log name, in each language the client keeps.
-- Indexes 1 to 3 hold English whether Lua counts these arrays from 0 or 1.
local function names_of(res, id)
    local known = names_by_id[id]
    if known then
        return known
    end
    local ok, item = pcall(function()
        return res:GetItemById(id)
    end)
    if not ok then
        return {}
    end
    known = {}
    if item ~= nil then
        for _, field in ipairs({ 'Name', 'LogNameSingular' }) do
            for index = 1, 3 do
                local read, value = pcall(function()
                    return item[field][index]
                end)
                if read and type(value) == 'string' and value ~= '' then
                    known[value:lower()] = true
                end
            end
        end
    end
    names_by_id[id] = known
    return known
end

-- The id of a carried item with this lowercased name, short or full. The
-- second value is false when the inventory could not be read.
local function carried(res, key)
    local ok, inv = pcall(function()
        return AshitaCore:GetMemoryManager():GetInventory()
    end)
    if not ok or inv == nil then
        return nil, false
    end
    local last = 80
    local sized, limit = pcall(function()
        return inv:GetContainerCountMax(0)
    end)
    if sized and type(limit) == 'number' and limit > 0 then
        last = limit
    end
    for slot = 1, last do
        local read, id = pcall(function()
            local entry = inv:GetContainerItem(0, slot)
            return entry and entry.Id
        end)
        if read and type(id) == 'number' and id > 0 and names_of(res, id)[key] then
            return id, true
        end
    end
    return nil, true
end

--- The item id for name, or nil. A name the client knows is found anywhere.
--- A full name it cuts short is found once that item is carried. The second
--- value is true when nil means no carried item has the name, not that the
--- client could not be read.
function items.id(name)
    name = trim(name)
    if name == '' then
        return nil, false
    end
    local key = name:lower()
    if ids[key] then
        return ids[key], true
    end
    local res = resources()
    if res == nil then
        return nil, false
    end
    local id = by_name(res, name)
    local looked = true
    if not id then
        id, looked = carried(res, key)
    end
    if id then
        ids[key] = id
    end
    return id, looked
end

return items
