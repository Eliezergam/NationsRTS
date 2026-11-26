local Rts = {}
Rts.__index = Rts

local function copyList(items)
    local result = {}
    for i, item in ipairs(items or {}) do
        result[i] = item
    end
    return result
end

local function roleOf(object)
    return object and object.rts and object.rts.role or nil
end

local function playerOf(object)
    return object and object.rts and tonumber(object.rts.playerId) or nil
end

local function objectKind(object)
    if not object or not object.rts then
        return nil
    end
    return object.rts.kind or object.rts.unitType or object.rts.buildingType or object.rts.resourceKind
end

local function sourceData(source)
    return source and (source.data or source.map or source)
end

function Rts.new(source)
    local data = sourceData(source) or {}
    local self = setmetatable({
        level = source and source.data and source or nil,
        data = data,
        rts = data.rts or {},
        objects = {},
        objectsByPlayerId = {},
        objectsByRoleName = {},
        objectsByKindName = {},
    }, Rts)
    self:rebuild()
    return self
end

function Rts:rebuild()
    self.objects = {}
    self.objectsByPlayerId = {}
    self.objectsByRoleName = {}
    self.objectsByKindName = {}
    for _, layer in ipairs(self.data.layers or {}) do
        for _, object in ipairs(layer.objects or {}) do
            if object.rts then
                self.objects[#self.objects + 1] = object
                local playerId = playerOf(object)
                if playerId then
                    self.objectsByPlayerId[playerId] = self.objectsByPlayerId[playerId] or {}
                    self.objectsByPlayerId[playerId][#self.objectsByPlayerId[playerId] + 1] = object
                end
                local role = roleOf(object)
                if role then
                    self.objectsByRoleName[role] = self.objectsByRoleName[role] or {}
                    self.objectsByRoleName[role][#self.objectsByRoleName[role] + 1] = object
                end
                local kind = objectKind(object)
                if kind and kind ~= '' then
                    self.objectsByKindName[kind] = self.objectsByKindName[kind] or {}
                    self.objectsByKindName[kind][#self.objectsByKindName[kind] + 1] = object
                end
            end
        end
    end
    return self
end

function Rts:players()
    return copyList(self.rts.players)
end

function Rts:player(id)
    id = tonumber(id)
    for _, player in ipairs(self.rts.players or {}) do
        if tonumber(player.id) == id then
            return player
        end
    end
end

function Rts:resources(kind)
    local result = {}
    for _, resource in ipairs(self.rts.resources or {}) do
        if not kind or resource.kind == kind then
            result[#result + 1] = resource
        end
    end
    for _, object in ipairs(self.objectsByRoleName.resource or {}) do
        if not kind or objectKind(object) == kind then
            result[#result + 1] = object
        end
    end
    return result
end

function Rts:starts(playerId)
    local result = {}
    playerId = tonumber(playerId)
    for _, start in ipairs(self.rts.starts or {}) do
        if not playerId or tonumber(start.playerId) == playerId then
            result[#result + 1] = start
        end
    end
    for _, object in ipairs(self.objectsByRoleName.spawn or {}) do
        if not playerId or playerOf(object) == playerId then
            result[#result + 1] = object
        end
    end
    return result
end

function Rts:zones(kind)
    local result = {}
    for _, zone in ipairs(self.rts.zones or {}) do
        if not kind or zone.kind == kind then
            result[#result + 1] = zone
        end
    end
    return result
end

function Rts:objectsByPlayer(playerId)
    return copyList(self.objectsByPlayerId[tonumber(playerId)] or {})
end

function Rts:objectsByRole(role)
    return copyList(self.objectsByRoleName[role] or {})
end

function Rts:objectsByKind(kind)
    return copyList(self.objectsByKindName[kind] or {})
end

function Rts:units(playerId)
    local result = {}
    for _, object in ipairs(self.objectsByRoleName.unit or {}) do
        if not playerId or playerOf(object) == tonumber(playerId) then
            result[#result + 1] = object
        end
    end
    return result
end

function Rts:buildings(playerId)
    local result = {}
    for _, object in ipairs(self.objectsByRoleName.building or {}) do
        if not playerId or playerOf(object) == tonumber(playerId) then
            result[#result + 1] = object
        end
    end
    return result
end

return Rts
