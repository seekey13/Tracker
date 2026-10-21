--[[
Tracker - which tracked enemy a defeated name belongs to.

The tome lists a plural ("Leeches", "Damselflies") or a family
("Members of the Gigas Family"). Death messages use the singular mob name,
sometimes with a non-letter marker in front (a Summit of the Stars target).
]]

local family = require('lib.family')

local match = {}

local function clean_name(name)
    name = tostring(name or '')
    return name:match('^[^%a]*(.*)') or name
end

-- How `listed` (the tome row) relates to `defeated` (the death message), or nil.
local function plural_kind(listed, defeated)
    if listed == defeated then
        return 'exact'
    end
    if listed == defeated .. 's' then
        return 'added s'
    end
    if listed == defeated .. 'es' then
        return 'added es'
    end
    if listed:sub(-1) == 's' and listed:sub(1, -2) == defeated then
        return 'removed s'
    end
    if #listed >= 2 and listed:sub(-2) == 'es' and listed:sub(1, -3) == defeated then
        return 'removed es'
    end
    if #listed >= 3 and listed:sub(-3) == 'ies' and (listed:sub(1, -4) .. 'y') == defeated then
        return 'y to ies'
    end
    if defeated:sub(-1) == 'y' and listed == (defeated:sub(1, -2) .. 'ies') then
        return 'ies to y'
    end
    return nil
end

local function family_kind(listed, defeated)
    local family_type = family.extract_family_type(listed or '')
    if not family_type then
        return nil
    end
    if family.is_family_member(defeated, family_type) then
        return 'family ' .. family_type
    end
    return nil
end

-- Returns the kind of match, or nil when the row does not claim this mob.
function match.kind(enemy, defeated)
    if type(enemy) ~= 'table' then
        return nil
    end
    defeated = clean_name(defeated)
    local listed = enemy.name or ''
    local mode = enemy.match_type

    if mode == 'family' then
        return family_kind(listed, defeated)
    end
    if mode == 'exact' then
        return plural_kind(listed, defeated)
    end

    -- Rows saved before match_type existed: exact, then family, then plural.
    if listed == defeated then
        return 'exact'
    end
    local as_family = family_kind(listed, defeated)
    if as_family then
        return as_family
    end
    return plural_kind(listed, defeated)
end

-- The tracked row and its index, or nil.
function match.find(enemies, defeated)
    if type(enemies) ~= 'table' then
        return nil, nil
    end
    for i, enemy in ipairs(enemies) do
        if match.kind(enemy, defeated) then
            return enemy, i
        end
    end
    return nil, nil
end

return match
