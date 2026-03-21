local settings = require("modules/utils/settings")

local gameUtils = {}

---Get player world position used for spawning logic.
---When editor mode is active, this returns a point in front of the camera
---at `settings.spawnDist` instead of the player's current feet position.
---@param editorActive boolean? Whether 3D editor mode is active.
---@return Vector4 position
function gameUtils.getPlayerPosition(editorActive)
    local pos = Game.GetPlayer():GetWorldPosition()

    if editorActive then
        local forward = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetAxisY()
        pos = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation()

        pos.z = pos.z + forward.z * settings.spawnDist
        pos.x = pos.x + forward.x * settings.spawnDist
        pos.y = pos.y + forward.y * settings.spawnDist
    end

    return pos
end

---Check whether the mod pause time dilation is currently active.
---@return boolean isPaused
function gameUtils.isPauseActive()
    local timeSystem = Game.GetTimeSystem()
    if not timeSystem then return false end

    return timeSystem:IsTimeDilationActive("console")
end

---Enable or disable pause time dilation managed by this mod.
---@param state boolean `true` to pause game time, `false` to resume.
function gameUtils.setPause(state)
    local timeSystem = Game.GetTimeSystem()
    if not timeSystem then return end

    if state then
        timeSystem:SetTimeDilation("console", 0.000000001)
    else
        timeSystem:UnsetTimeDilation("console")
    end
end

---Set the player scene tier in the player-state-machine blackboard.
---@param tier number Scene tier value (commonly `1` for normal, `4` for editor/freecam use).
function gameUtils.setSceneTier(tier)
    local blackboardDefs = Game.GetAllBlackboardDefs()
    local blackboardPSM = Game.GetBlackboardSystem():GetLocalInstanced(GetPlayer():GetEntityID(), blackboardDefs.PlayerStateMachine)
    blackboardPSM:SetInt(blackboardDefs.PlayerStateMachine.SceneTier, tier, true)
end

---Resolve a dynamic NPC/entity handle by entity ID.
---@param npcID entEntityID? Dynamic entity ID.
---@return Entity? npc Resolved entity handle, or `nil` when unavailable.
function gameUtils.getNPC(npcID)
    if not npcID then return end

    return Game.GetDynamicEntitySystem():GetEntity(npcID)
end

return gameUtils
