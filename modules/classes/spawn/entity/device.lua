local entity = require("modules/classes/spawn/entity/entity")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local registry = require("modules/utils/nodeRefRegistry")
local history = require("modules/utils/history")
local visualizer = require("modules/utils/visualizer")

local POSITION_MARKER_COMPONENT = "sphere"
local POSITION_MARKER_SCALE = { x = 0.05, y = 0.05, z = 0.05 }
local POSITION_MARKER_COLOR = "blue"

local propertyNames = {
    "Device Class Name",
    "Persistent"
}

---Class for worldDeviceNode
---@class device : entity
---@field public deviceConnections {deviceClassName : string, nodeRef : string}[]
---@field public connectionsHeaderState boolean
---@field public persistent boolean
---@field private maxPropertyWidth number?
---@field public controllerComponent string
local device = setmetatable({}, { __index = entity })

function device:new()
	local o = entity.new(self)

    o.dataType = "Device"
    o.modulePath = "entity/device"
    o.spawnDataPath = "data/spawnables/entity/device/"
    o.node = "worldDeviceNode"
    o.description = "Spawns an entity (.ent), as a worldDeviceNode. This allows it to be connected to other worldDeviceNodes."
    o.previewNote = "Device connections / functionality is not previewed."

    o.icon = IconGlyphs.DesktopClassic

    o.deviceConnections = {}
    o.connectionsHeaderState = false
    o.persistent = false

    o.maxPropertyWidth = nil
    o.controllerComponent = ""
    o.showPositionMarker = false

    setmetatable(o, { __index = self })
   	return o
end

function device:updatePositionMarker()
    local entityRef = self:getEntity()
    if not entityRef then return end

    local marker = entityRef:FindComponentByName(POSITION_MARKER_COMPONENT)

    if self.showPositionMarker then
        if not marker then
            visualizer.addSphere(entityRef, POSITION_MARKER_SCALE, POSITION_MARKER_COLOR)
        else
            visualizer.updateScale(entityRef, POSITION_MARKER_SCALE, POSITION_MARKER_COMPONENT)
            marker:Toggle(true)
        end
    elseif marker then
        marker:Toggle(false)
    end
end

function device:setPositionMarkerVisible(state)
    self.showPositionMarker = state
    self:updatePositionMarker()
end

function device:onAssemble(entRef)
    entity.onAssemble(self, entRef)
    self:updatePositionMarker()
end

function device:save()
    local data = entity.save(self)
    data.deviceConnections = utils.deepcopy(self.deviceConnections)
    data.persistent = self.persistent
    data.controllerComponent = self.controllerComponent
    data.showPositionMarker = self.showPositionMarker

    return data
end

function device:draw()
    entity.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth(propertyNames) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    style.mutedText("Persistent")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.persistent, _, _ = style.trackedCheckbox(self.object, "##persistent", self.persistent)
    if self.nodeRef == "" then
        self.persistent = false
        style.tooltip("Requires NodeRef to be set.")
    else
        style.tooltip("If true, the device will get an entry in the .psrep file. Not all devices need this, still subject to more testing.")
    end
    ImGui.SameLine()
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.Reload) then
        Game.GetPersistencySystem():ForgetObject(PersistentID.ForComponent(entEntityID.new({ hash = loadstring("return " .. utils.nodeRefStringToHashString(self.nodeRef) .. "ULL", "")() }), self.controllerComponent), true)
    end
    style.pushButtonNoBG(false)
    style.tooltip("Reloads the devices persistent state.\nApplies to the actual device in the world (Imported), not the editor.")

    self.connectionsHeaderState = ImGui.TreeNodeEx("Device Connections")

    if self.connectionsHeaderState then
        for index, connection in pairs(self.deviceConnections) do
            ImGui.PushID(key)

            connection.deviceClassName, _, _ = style.trackedTextField(self.object, "##className", connection.deviceClassName, "gameDeviceComponentPS", 150)
            style.tooltip("Device class name of the connected device. Name of the gameDeviceComponentPS used in the devices gameDeviceComponent")
            ImGui.SameLine()
            connection.nodeRef, _ = registry.drawNodeRefSelector(style.getMaxWidth(250) - 30, connection.nodeRef, self.object, true)
            style.tooltip("NodeRef of the connected device. Can be set using \"World Node\" section of the target device")
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.Delete) then
                history.addAction(history.getElementChange(self.object))
                table.remove(self.deviceConnections, index)
            end

            ImGui.PopID()
        end

        if ImGui.Button("+") then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.deviceConnections, { deviceClassName = "", nodeRef = "" })
        end

        ImGui.TreePop()
    end
end

function device:getPSData()
    for _, data in pairs(self.instanceDataChanges) do
        if data.persistentState and data.persistentState.Data then
            self:prepareInstanceData(data.persistentState.Data)
            return data.persistentState.Data
        end
    end
end

function device:getProperties()
    local properties = entity.getProperties(self)
    table.insert(properties, {
        id = self.node .. "Visualization",
        name = "Visualization",
        defaultHeader = false,
        draw = function()
            style.mutedText("Show Position Marker")
            ImGui.SameLine()
            local changed
            self.showPositionMarker, changed = style.trackedCheckbox(self.object, "##showPositionMarkerDevice", self.showPositionMarker)
            if changed then
                self:setPositionMarkerVisible(self.showPositionMarker)
                self:respawn()
            end
            style.tooltip("Draw a sphere marker at the entity position.")
        end
    })
    return properties
end

function device:export(index, length)
    local data = entity.export(self, index, length)

    data.type = "worldDeviceNode"
    data.data.deviceConnections = {}

    local connections = {}

    -- Group by deviceClassName
    for _, connection in pairs(self.deviceConnections) do
        if not connections[connection.deviceClassName] then
            connections[connection.deviceClassName] = {}
        end

        table.insert(connections[connection.deviceClassName], connection.nodeRef)
    end

    for className, connection in pairs(connections) do
        local nodeRefs = {}

        for _, nodeRef in pairs(connection) do
            table.insert(nodeRefs, {
                ["$type"] = "NodeRef",
                ["$storage"] = "string",
                ["$value"] = nodeRef
            })
        end

        table.insert(data.data.deviceConnections, {
            ["$type"] = "worldDeviceConnections",
            ["deviceClassName"] = {
                ["$type"] = "CName",
                ["$storage"] = "string",
                ["$value"] = className
            },
            ["nodeRefs"] = nodeRefs
        })
    end

    return data
end

return device
