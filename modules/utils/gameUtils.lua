local settings = require("modules/utils/settings")

local gameUtils = {}

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

function gameUtils.isPauseActive()
    local timeSystem = Game.GetTimeSystem()
    if not timeSystem then return false end

    return timeSystem:IsTimeDilationActive("console")
end

function gameUtils.setPause(state)
    local timeSystem = Game.GetTimeSystem()
    if not timeSystem then return end

    if state then
        timeSystem:SetTimeDilation("console", 0.000000001)
    else
        timeSystem:UnsetTimeDilation("console")
    end
end

function gameUtils.setSceneTier(tier)
    local blackboardDefs = Game.GetAllBlackboardDefs()
    local blackboardPSM = Game.GetBlackboardSystem():GetLocalInstanced(GetPlayer():GetEntityID(), blackboardDefs.PlayerStateMachine)
    blackboardPSM:SetInt(blackboardDefs.PlayerStateMachine.SceneTier, tier, true)
end

function gameUtils.getNPC(npcID)
    if not npcID then return end

    return Game.GetDynamicEntitySystem():GetEntity(npcID)
end

return gameUtils
