local settings = require("modules/utils/settings")

local gameUtils = {}
local locKeyCache = {}

local function trimTextValue(value)
    return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

local function isLocKey(value)
    return type(value) == "string" and string.match(trimTextValue(value), "^LocKey#%d+$") ~= nil
end

local function isSecondaryKey(value)
    return type(value) == "string" and string.match(trimTextValue(value), "^SecondaryKey#%d+$") ~= nil
end

local function isRawLocalizationKey(value)
    if type(value) ~= "string" then
        return false
    end

    local normalized = trimTextValue(value)
    if string.match(normalized, "^#%d+$") then
        return true
    end

    -- Heuristic for hash-like numeric keys.
    return #normalized >= 6 and string.match(normalized, "^%d+$") ~= nil
end

local function isNamespacedLocalizationKey(value)
    if type(value) ~= "string" then
        return false
    end

    local normalized = trimTextValue(value)
    if normalized == "" or string.find(normalized, "%s") then
        return false
    end

    -- Namespaced secondary keys are usually tokenized with multiple separators,
    -- e.g. "Gameplay-Devices-DisplayNames-Button".
    local separatorCount = 0
    for _ in string.gmatch(normalized, "[-_%.:/]") do
        separatorCount = separatorCount + 1
    end

    if separatorCount < 2 then
        return false
    end

    return string.match(normalized, "^[A-Za-z][A-Za-z0-9%-%._:/]*$") ~= nil
end

local function isLocalizationKeyLike(value)
    return isLocKey(value) or isSecondaryKey(value) or isRawLocalizationKey(value) or isNamespacedLocalizationKey(value)
end

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

---Resolve a localization key string into localized text.
---Supports chained key indirections (for example `LocKey#...` -> `SecondaryKey#...` -> text).
---@param value any Candidate localization key (e.g. `LocKey#123`).
---@param cache table? Optional cache table to reuse between callers.
---@return string? localizedText Localized text, or `nil` when unresolved.
function gameUtils.resolveLocKey(value, cache)
    if type(value) ~= "string" then
        return nil
    end

    local key = trimTextValue(value)
    if key == "" or key == "None" or key == "0" then
        return nil
    end

    if not isLocalizationKeyLike(key) then
        return nil
    end

    local lookupCache = cache or locKeyCache
    local cached = lookupCache[key]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local function analyzeCandidate(currentKey, candidate)
        if type(candidate) ~= "string" then
            return nil, nil
        end

        local normalized = trimTextValue(candidate)
        if normalized == "" or normalized == currentKey then
            return nil, nil
        end

        if isLocalizationKeyLike(normalized) then
            return nil, normalized
        end

        return candidate, nil
    end

    local currentKey = key
    local visited = {}

    for _ = 1, 8 do
        if visited[currentKey] then
            break
        end
        visited[currentKey] = true

        local nextKey = nil

        local okText, text = pcall(function ()
            return GetLocalizedText(currentKey)
        end)
        if okText then
            local localized, chained = analyzeCandidate(currentKey, text)
            if localized then
                lookupCache[key] = localized
                return localized
            end
            nextKey = chained or nextKey
        end

        local okByKey, byKeyText = pcall(function ()
            CName.add(currentKey)
            return GetLocalizedTextByKey(CName.new(currentKey))
        end)
        if okByKey then
            local localized, chained = analyzeCandidate(currentKey, byKeyText)
            if localized then
                lookupCache[key] = localized
                return localized
            end
            nextKey = chained or nextKey
        end

        local okLocKey, locKeyText = pcall(function ()
            CName.add(currentKey)
            return LocKeyToString(CName.new(currentKey))
        end)
        if okLocKey then
            local localized, chained = analyzeCandidate(currentKey, locKeyText)
            if localized then
                lookupCache[key] = localized
                return localized
            end
            nextKey = chained or nextKey
        end

        if not nextKey or visited[nextKey] then
            break
        end

        currentKey = nextKey
    end

    lookupCache[key] = false
    return nil
end

return gameUtils
