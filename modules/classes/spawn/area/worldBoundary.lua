local area = require("modules/classes/spawn/area/area")

---Class for gameWorldBoundaryNode
---@class worldBoundary : area
local worldBoundary = setmetatable({}, { __index = area })

function worldBoundary:new()
	local o = area.new(self)

    o.spawnListType = "files"
    o.dataType = "World Boundary"
    o.spawnDataPath = "data/spawnables/area/worldBoundary/"
    o.modulePath = "area/worldBoundary"
    o.node = "gameWorldBoundaryNode"
    o.description = "Defines a world boundary area for systems that react to world limits."
    o.previewNote = "Does not work in the editor."
    o.icon = IconGlyphs.SelectionRemove

    setmetatable(o, { __index = self })
   	return o
end

function worldBoundary:export()
    local data = area.export(self)
    data.type = "gameWorldBoundaryNode"

    return data
end

return worldBoundary
