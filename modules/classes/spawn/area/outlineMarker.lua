local connectedMarker = require("modules/classes/spawn/connectedMarker")
local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")
local visualizer = require("modules/utils/visualizer")

---Class for outline marker (Not a node, meta class used for area nodes)
---@class outlineMarker : connectedMarker
---@field private height number
---@field private dragBeingEdited boolean
---@field private heightZLocked boolean
local outlineMarker = setmetatable({}, { __index = connectedMarker })

function outlineMarker:new()
	local o = connectedMarker.new(self)

    o.spawnListType = "files"
    o.dataType = "Outline Marker"
    o.spawnDataPath = "data/spawnables/area/outlineMarker/"
    o.modulePath = "area/outlineMarker"
    o.node = "---"
    o.description = "Places a marker for an outline. Automatically connects with other outline markers in the same group, to form an outline. The parent group can be used to reference the contained outline, and use it in worldAreaShapeNode's"
    o.icon = IconGlyphs.SelectMarker

    o.height = 2
    o.dragBeingEdited = false
    o.heightZLocked = false
    o.previewText = "Preview Outline"

    setmetatable(o, { __index = self })
   	return o
end

function outlineMarker:midAssemble()
    self:inheritLinkedState(self.object and self.object.parent or nil)
    self:enforceSameZ()
    self:setPreview(self.previewed)
end

function outlineMarker:onParentChanged(oldParent)
    self:inheritLinkedState(self.object and self.object.parent or nil)
    connectedMarker.onParentChanged(self, oldParent)
    self:setPreview(self.previewed)
end

function outlineMarker:save()
    local data = connectedMarker.save(self)

    data.height = self.height
    data.heightZLocked = self.heightZLocked

    return data
end

function outlineMarker:update()
    self.rotation = EulerAngles.new(0, 0, 0)

    self:enforceSameZ()
    self:updateTransform(self.object.parent)
    self:updateHeight()

    for _, neighbor in pairs(self:getNeighbors().neighbors) do
        neighbor:updateTransform(neighbor.object.parent)
        neighbor.height = self.height
        neighbor:updateHeight()
    end
end

function outlineMarker:getNeighbors(parent)
    parent = parent or self.object.parent
    if not parent or not parent.childs then
        return { neighbors = {}, selfIndex = 1, previous = nil, nxt = nil }
    end

    local neighbors = {}
    local selfIndex = 0

    for _, entry in pairs(parent.childs) do
        if utils.isA(entry, "spawnableElement") and entry.spawnable.modulePath == self.modulePath and entry ~= self.object then
            table.insert(neighbors, entry.spawnable)
        elseif entry == self.object then
            selfIndex = #neighbors + 1
        end
    end

    local previous = selfIndex == 1 and neighbors[#neighbors] or neighbors[selfIndex - 1]
    local nxt = selfIndex > #neighbors and neighbors[1] or neighbors[selfIndex]

    return { neighbors = neighbors, selfIndex = selfIndex, previous = previous, nxt = nxt }
end

---@protected
---@param parent element?
function outlineMarker:inheritLinkedState(parent)
    local neighbors = self:getNeighbors(parent).neighbors
    if #neighbors == 0 then return end

    local template = neighbors[1]
    if not template then return end

    self.height = template.height
    self.heightZLocked = template.heightZLocked == true
    self.previewed = template.previewed ~= false

    if self.heightZLocked then
        self.position.z = template.position.z
    end
end

function outlineMarker:getTransform(parent)
    local neighbors = self:getNeighbors(parent)
    local width = 0.005
    local yaw = self.rotation.yaw

    if #neighbors.neighbors > 1 then
        local diff = utils.subVector(neighbors.nxt.position, self.position)
        yaw = diff:ToRotation().yaw + 90
        width = diff:Length() / 2
    end

    return {
        scale = { x = width, y = 0.005, z = self.height },
        rotation = { roll = 0, pitch = 0, yaw = yaw },
    }
end

---Updates the x scale and yaw rotation of the outline marker based on the neighbors
function outlineMarker:updateTransform(parent)
    spawnable.update(self)

    local entity = self:getEntity()
    if not entity then return end

    local transform = self:getTransform(parent)
    local mesh = entity:FindComponentByName("mesh")
    mesh.visualScale = Vector3.new(transform.scale.x, 0.005, transform.scale.z / 2)
    mesh:SetLocalOrientation(EulerAngles.new(0, 0, transform.rotation.yaw):ToQuat())

    mesh:RefreshAppearance()
end

-- Enforce same z for all neighbors
---@protected
function outlineMarker:enforceSameZ()
    local neighbors = self:getNeighbors().neighbors
    if #neighbors == 0 then return end

    local targetZ = self.position.z
    local lockedTargetZ = self.heightZLocked and self.position.z or nil

    -- If a linked marker is lock-enabled, its existing Z stays authoritative.
    for _, neighbor in pairs(neighbors) do
        if neighbor.heightZLocked then
            lockedTargetZ = neighbor.position.z
            break
        end
    end

    if lockedTargetZ ~= nil then
        targetZ = lockedTargetZ
        self.position.z = targetZ

        local selfEntity = self:getEntity()
        if selfEntity then
            spawnable.update(self)
        end
    end

    for _, neighbor in pairs(neighbors) do
        neighbor.position.z = targetZ
        local entity = neighbor:getEntity()

        if entity then
            spawnable.update(neighbor)
        end
    end
end

function outlineMarker:updateHeight()
    local entity = self:getEntity()
    if not entity then return end

    local mesh = entity:FindComponentByName("mesh")
    mesh.visualScale = Vector3.new(mesh.visualScale.x, 0.005, self.height / 2)
    mesh:RefreshAppearance()
    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
end

---@protected
function outlineMarker:setLinkedHeightZLock(state)
    self.heightZLocked = state

    for _, neighbor in pairs(self:getNeighbors().neighbors) do
        neighbor.heightZLocked = state
    end
end

---@param axis string
---@return boolean
function outlineMarker:isTransformAxisLocked(axis)
    if not self.heightZLocked then
        return false
    end

    return axis == "z" or axis == "relZ"
end

function outlineMarker:draw()
    connectedMarker.draw(self)

    style.mutedText("Height")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    ImGui.SetNextItemWidth(110 * style.viewSize)
    ImGui.BeginDisabled(self.heightZLocked)
    local newValue, changed = ImGui.DragFloat("##height", self.height, 0.01, 0, 250, "%.2f Height")
    ImGui.EndDisabled()
    ImGui.SameLine()

    local lockIcon = self.heightZLocked and IconGlyphs.LockOutline or IconGlyphs.LockOpenVariantOutline
    local nextHeightZLocked, lockChanged = style.toggleButton(lockIcon .. "##heightZLock" .. tostring(self.object.id), self.heightZLocked)
    if lockChanged then
        local elements = { self.object }
        for _, neighbor in pairs(self:getNeighbors().neighbors) do
            table.insert(elements, neighbor.object)
        end

        history.addAction(history.getMultiSelectChange(elements))
        self:setLinkedHeightZLock(nextHeightZLocked)
    end
    style.tooltip("Lock Height and Z/Rel Z transforms for all linked outline markers")

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		self.dragBeingEdited = false
	end
	if changed and not self.dragBeingEdited then
        local elements = { self.object }
        for _, neighbor in pairs(self:getNeighbors().neighbors) do
            table.insert(elements, neighbor.object)
        end

        history.addAction(history.getMultiSelectChange(elements))
		self.dragBeingEdited = true
	end

    if changed or finished then
        newValue = math.max(newValue, 0)
        newValue = math.min(newValue, 250)

        self.height = newValue
        self:updateHeight()

        for _, neighbor in pairs(self:getNeighbors().neighbors) do
            neighbor.height = self.height
            neighbor:updateHeight()
        end
    end
end

return outlineMarker
