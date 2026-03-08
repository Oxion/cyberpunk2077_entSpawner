local utils = require("modules/utils/utils")

local maxHistory = 999
local maxPendingRequests = 16

---@class history
---@field index number
---@field actions table
---@field spawnedUI spawnedUI?
local history = {
    index = 0,
    actions = {},
    spawnedUI = nil,
    propBeingEdited = false,
    pending = {},
    active = nil,
    frameBudgetMs = 2.5
}

---@param registryAffected boolean?
local function rebuildCache(registryAffected)
    if not history.spawnedUI then
        return
    end

    if history.spawnedUI.invalidateCache then
        history.spawnedUI.invalidateCache(registryAffected == true)
    end

    if history.spawnedUI.cachePaths then
        history.spawnedUI.cachePaths()
    elseif history.spawnedUI.ensureCache then
        history.spawnedUI.ensureCache()
    end
end

---@param message string
---@param err any
local function logActionError(message, err)
    print("[entSpawner][history] " .. tostring(message) .. ": " .. tostring(err))
end

---@param node element?
---@param id number
---@return element?
local function findElementByIdRecursive(node, id)
    if not node then
        return nil
    end

    if node.id == id then
        return node
    end

    for _, child in ipairs(node.childs or {}) do
        local found = findElementByIdRecursive(child, id)
        if found then
            return found
        end
    end

    return nil
end

---@param path string
---@return element?
local function findElementByPathTree(path)
    if not history.spawnedUI or not history.spawnedUI.root then
        return nil
    end

    if path == "" then
        return history.spawnedUI.root
    end

    local current = history.spawnedUI.root
    for segment in string.gmatch(path, "/([^/]+)") do
        local found = nil
        for _, child in ipairs(current.childs or {}) do
            if child.name == segment then
                found = child
                break
            end
        end

        if not found then
            return nil
        end

        current = found
    end

    return current
end

---@param path string
---@param forceRefresh boolean?
---@param expectedId number?
---@param allowExpensiveFallback boolean?
---@return element?
local function resolveElementByPath(path, forceRefresh, expectedId, allowExpensiveFallback)
    if not history.spawnedUI then
        return nil
    end

    if forceRefresh then
        rebuildCache(true)
    end

    local entry = findElementByPathTree(path)
    if entry then
        return entry
    end

    if expectedId then
        entry = findElementByIdRecursive(history.spawnedUI.root, expectedId)
        if entry then
            return entry
        end
    end

    if allowExpensiveFallback == false or not history.spawnedUI.getElementByPath then
        return nil
    end

    entry = history.spawnedUI.getElementByPath(path)
    if entry then
        return entry
    end

    rebuildCache(true)

    entry = history.spawnedUI.getElementByPath(path)
    if entry then
        return entry
    end

    if expectedId and history.spawnedUI.paths then
        for _, node in ipairs(history.spawnedUI.paths) do
            if node and node.ref and node.ref.id == expectedId then
                return node.ref
            end
        end
    end

    return nil
end

---@param action table
---@param mode "undo"|"redo"
---@return boolean
local function runActionImmediate(action, mode)
    if not action then
        return false
    end

    if action.begin then
        local ok, err = pcall(action.begin, mode)
        if not ok then
            logActionError("Action begin failed", err)
            return false
        end
    end

    if action.step then
        local done = false
        while not done do
            local ok, result = pcall(action.step, mode, 1e9)
            if not ok then
                logActionError("Action step failed", result)
                return false
            end
            done = result == true
        end
    else
        local fn = mode == "undo" and action.undo or action.redo
        if not fn then
            return false
        end

        local ok, err = pcall(fn)
        if not ok then
            logActionError("Action " .. mode .. " failed", err)
            return false
        end
    end

    if action.finish then
        local ok, err = pcall(action.finish, mode)
        if not ok then
            logActionError("Action finish failed", err)
        end
    end

    return true
end

---@param state table
---@param action table
---@param mode "undo"|"redo"
---@param budgetMs number
---@return boolean done
local function stepNestedAction(state, action, mode, budgetMs)
    if not state.started then
        if action.begin then
            local ok, err = pcall(action.begin, mode)
            if not ok then
                logActionError("Nested begin failed", err)
                state.started = false
                return true
            end
        end
        state.started = true
    end

    local done = false
    if action.step then
        local ok, result = pcall(action.step, mode, budgetMs)
        if not ok then
            logActionError("Nested step failed", result)
            done = true
        else
            done = result == true
        end
    else
        local fn = mode == "undo" and action.undo or action.redo
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                logActionError("Nested " .. mode .. " failed", err)
            end
        end
        done = true
    end

    if done then
        if action.finish then
            local ok, err = pcall(action.finish, mode)
            if not ok then
                logActionError("Nested finish failed", err)
            end
        end
        state.started = false
    end

    return done
end

---@param elements element[]|{ path : string, ref : element }[]
---@return element[]
function history.normalizeElements(elements)
    local normalized = {}

    for _, element in ipairs(elements) do
        if element.ref then
            element = element.ref
        end
        table.insert(normalized, element)
    end

    return normalized
end

---@param actions table[]
---@return table
function history.getComposite(actions)
    local action = {}
    local state = nil

    action.undo = function()
        for i = #actions, 1, -1 do
            actions[i].undo()
        end
    end

    action.redo = function()
        for _, nested in ipairs(actions) do
            nested.redo()
        end
    end

    action.begin = function(mode)
        state = {
            mode = mode,
            index = mode == "undo" and #actions or 1,
            delta = mode == "undo" and -1 or 1,
            nested = { started = false }
        }
    end

    action.step = function(mode, budgetMs)
        if not state or state.mode ~= mode then
            action.begin(mode)
        end

        local deadline = nil
        if budgetMs and budgetMs > 0 then
            deadline = os.clock() + (budgetMs / 1000)
        end

        while state.index >= 1 and state.index <= #actions do
            local nested = actions[state.index]
            local remainingBudget = budgetMs
            if deadline then
                remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
            end

            local doneNested = stepNestedAction(state.nested, nested, mode, remainingBudget)
            if doneNested then
                state.index = state.index + state.delta
            end

            if deadline and os.clock() >= deadline then
                return false
            end
        end

        return true
    end

    action.finish = function()
        state = nil
    end

    return action
end

function history.getMove(remove, insert)
    local action = {}
    local state = nil

    action.redo = function()
        remove.redo()
        insert.redo()
    end

    action.undo = function()
        insert.undo()
        remove.undo()
    end

    action.begin = function(mode)
        local sequence = nil
        if mode == "redo" then
            sequence = {
                { action = remove, mode = "redo" },
                { action = insert, mode = "redo" }
            }
        else
            sequence = {
                { action = insert, mode = "undo" },
                { action = remove, mode = "undo" }
            }
        end

        state = {
            mode = mode,
            sequence = sequence,
            phase = 1,
            nested = { started = false }
        }
    end

    action.step = function(mode, budgetMs)
        if not state or state.mode ~= mode then
            action.begin(mode)
        end

        local deadline = nil
        if budgetMs and budgetMs > 0 then
            deadline = os.clock() + (budgetMs / 1000)
        end

        while state.phase <= #state.sequence do
            local phase = state.sequence[state.phase]
            local remainingBudget = budgetMs
            if deadline then
                remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
            end

            local donePhase = stepNestedAction(state.nested, phase.action, phase.mode, remainingBudget)
            if donePhase then
                state.phase = state.phase + 1
            end

            if deadline and os.clock() >= deadline then
                return false
            end
        end

        return true
    end

    action.finish = function()
        state = nil
    end

    return action
end

function history.getMoveToNewGroup(insert, remove, insertElement)
    local move = history.getMove(remove, insertElement)
    local action = {}
    local state = nil

    action.redo = function()
        insert.redo()
        if history.spawnedUI and history.spawnedUI.cachePaths then
            history.spawnedUI.cachePaths() -- Very important so that the path of the new group can be found.
        end
        move.redo()
    end

    action.undo = function()
        move.undo()
        insert.undo()
    end

    action.begin = function(mode)
        if mode == "redo" then
            state = {
                mode = mode,
                phase = 1, -- 1: insert.redo, 2: refresh paths, 3: move.redo
                nested = { started = false }
            }
        else
            state = {
                mode = mode,
                phase = 1, -- 1: move.undo, 2: insert.undo
                nested = { started = false }
            }
        end
    end

    action.step = function(mode, budgetMs)
        if not state or state.mode ~= mode then
            action.begin(mode)
        end

        local deadline = nil
        if budgetMs and budgetMs > 0 then
            deadline = os.clock() + (budgetMs / 1000)
        end

        while true do
            if mode == "redo" then
                if state.phase == 1 then
                    local remainingBudget = budgetMs
                    if deadline then
                        remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
                    end
                    local doneInsert = stepNestedAction(state.nested, insert, "redo", remainingBudget)
                    if doneInsert then
                        state.phase = 2
                    end
                elseif state.phase == 2 then
                    if history.spawnedUI and history.spawnedUI.cachePaths then
                        history.spawnedUI.cachePaths()
                    end
                    state.phase = 3
                elseif state.phase == 3 then
                    local remainingBudget = budgetMs
                    if deadline then
                        remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
                    end
                    local doneMove = stepNestedAction(state.nested, move, "redo", remainingBudget)
                    if doneMove then
                        state.phase = 4
                    end
                else
                    return true
                end
            else
                if state.phase == 1 then
                    local remainingBudget = budgetMs
                    if deadline then
                        remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
                    end
                    local doneMove = stepNestedAction(state.nested, move, "undo", remainingBudget)
                    if doneMove then
                        state.phase = 2
                    end
                elseif state.phase == 2 then
                    local remainingBudget = budgetMs
                    if deadline then
                        remainingBudget = math.max((deadline - os.clock()) * 1000, 0)
                    end
                    local doneInsert = stepNestedAction(state.nested, insert, "undo", remainingBudget)
                    if doneInsert then
                        state.phase = 3
                    end
                else
                    return true
                end
            end

            if deadline and os.clock() >= deadline then
                return false
            end
        end
    end

    action.finish = function()
        state = nil
    end

    return action
end

function history.getElementChange(element)
    local action = {}

    if history.spawnedUI and element == history.spawnedUI.multiSelectGroup then -- Multiselect group is not real
        return history.getMultiSelectChange(element.childs)
    end

    action.data = element:serialize()
    action.path = element:getPath()
    action.id = element.id

    local function swap()
        local target = resolveElementByPath(action.path, false, action.id, true)
        if not target then
            print("[entSpawner][history] Element change target not found for path: " .. tostring(action.path))
            return
        end

        local old = target:serialize()
        target:load(action.data)
        action.data = old
    end

    action.redo = swap
    action.undo = swap

    return action
end

function history.getMultiSelectChange(elements)
    return history.getComposite(history.getElementChanges(elements))
end

---@param elements element[]|{ path : string, ref : element }[]
---@return table[]
function history.getElementChanges(elements)
    local changes = {}

    for _, element in ipairs(history.normalizeElements(elements)) do
        table.insert(changes, history.getElementChange(element))
    end

    return changes
end

function history.getRename(data, current, new, id)
    local action = {}
    action.data = data
    action.old = current
    action.new = new
    action.id = id

    local function swap(path)
        local target = resolveElementByPath(path, true, action.id, true)
        if not target then
            print("[entSpawner][history] Rename target not found for path: " .. tostring(path))
            return
        end

        local old = target:serialize()
        target:load(action.data)
        action.data = old
    end

    action.redo = function()
        swap(action.old)
    end

    action.undo = function()
        swap(action.new)
    end

    return action
end

---Must be called after the elements are inserted
---@param elements element[]|{ path : string, ref : element }[]
---@return table
function history.getInsert(elements)
    local base = history.getRemove(elements)
    local action = {}

    local function invertMode(mode)
        return mode == "redo" and "undo" or "redo"
    end

    action.redo = function()
        if base.undo then
            base.undo()
        end
    end

    action.undo = function()
        if base.redo then
            base.redo()
        end
    end

    if base.begin then
        action.begin = function(mode)
            base.begin(invertMode(mode))
        end
    end

    if base.step then
        action.step = function(mode, budgetMs)
            return base.step(invertMode(mode), budgetMs)
        end
    end

    if base.finish then
        action.finish = function(mode)
            base.finish(invertMode(mode))
        end
    end

    return action
end

---Must be called before the elements are removed / reparented
---@param elements element[]|{ path : string, ref : element }[]
---@return table
function history.getRemove(elements)
    local data = {}
    local seenIds = {}
    for _, element in ipairs(history.normalizeElements(elements)) do
        local id = element and element.id or nil
        if element.parent ~= nil and (id == nil or not seenIds[id]) then
            if id ~= nil then
                seenIds[id] = true
            end
            local parentPath = element.parent:getPath()
            table.insert(data, {
                index = utils.indexValue(element.parent.childs, element),
                parentPath = parentPath,
                parentId = element.parent.id,
                path = element:getPath(),
                id = element.id,
                data = element:serialize()
            })
        end
    end

    local insertOrder = {}
    for _, entry in ipairs(data) do
        table.insert(insertOrder, entry)
    end
    table.sort(insertOrder, function(a, b)
        if a.parentPath ~= b.parentPath then
            return a.parentPath < b.parentPath
        end

        local aIndex = a.index ~= -1 and a.index or math.huge
        local bIndex = b.index ~= -1 and b.index or math.huge
        if aIndex ~= bIndex then
            return aIndex < bIndex
        end

        return a.path < b.path
    end)

    local function processRedoEntry(elementData)
        local entry = resolveElementByPath(elementData.path, false, elementData.id, false)
        if entry then
            entry:remove()
        end
    end

    local function processUndoEntry(elementData)
        local parent = resolveElementByPath(elementData.parentPath, false, elementData.parentId, false)
        if parent then
            local existing = resolveElementByPath(elementData.path, false, elementData.id, false)
            if existing then
                local insertAtExisting = elementData.index ~= -1 and elementData.index or nil
                existing:setParent(parent, insertAtExisting)
                return
            end

            local new = require(elementData.data.modulePath):new(history.spawnedUI)
            new:load(elementData.data)
            new.id = elementData.id -- Preserve runtime identity so later history steps can resolve by id.
            local insertAt = elementData.index ~= -1 and elementData.index or nil
            new:setParent(parent, insertAt)
        end
    end

    local action = {}
    local state = nil

    action.redo = function()
        for _, elementData in ipairs(data) do
            processRedoEntry(elementData)
        end
    end

    action.undo = function()
        for _, elementData in ipairs(insertOrder) do
            processUndoEntry(elementData)
        end
    end

    action.begin = function(mode)
        state = {
            mode = mode,
            index = 1,
            list = mode == "redo" and data or insertOrder
        }
    end

    action.step = function(mode, budgetMs)
        if not state or state.mode ~= mode then
            action.begin(mode)
        end

        local deadline = nil
        if budgetMs and budgetMs > 0 then
            deadline = os.clock() + (budgetMs / 1000)
        end

        local list = state.list or (mode == "redo" and data or insertOrder)
        while state.index <= #list do
            local elementData = list[state.index]
            if mode == "redo" then
                processRedoEntry(elementData)
            else
                processUndoEntry(elementData)
            end

            state.index = state.index + 1

            if deadline and os.clock() >= deadline then
                return false
            end
        end

        return true
    end

    action.finish = function()
        state = nil
    end

    return action
end

local function clearExecutionQueue()
    history.pending = {}
    history.active = nil
end

function history.addAction(action)
    clearExecutionQueue()

    if history.index < #history.actions then
        for i = history.index + 1, #history.actions do
            history.actions[i] = nil
        end
    end

    if #history.actions >= maxHistory then
        table.remove(history.actions, 1)
    end

    table.insert(history.actions, action)
    history.index = #history.actions
end

---@return boolean
function history.requestUndo()
    if #history.pending >= maxPendingRequests then
        return false
    end

    table.insert(history.pending, "undo")
    return true
end

---@return boolean
function history.requestRedo()
    if #history.pending >= maxPendingRequests then
        return false
    end

    table.insert(history.pending, "redo")
    return true
end

---@return boolean
function history.isBusy()
    return history.active ~= nil
end

---@return number
function history.getPendingCount()
    local inFlight = history.active and 1 or 0
    return inFlight + #history.pending
end

local function beginNextPendingAction()
    while #history.pending > 0 do
        local mode = table.remove(history.pending, 1)
        local action = nil
        local shouldStart = true

        if mode == "undo" then
            if history.index == 0 then
                shouldStart = false
            else
                action = history.actions[history.index]
            end
        else
            if history.index == #history.actions then
                shouldStart = false
            else
                action = history.actions[history.index + 1]
            end
        end

        if shouldStart and action then
            history.active = {
                mode = mode,
                action = action,
                failed = false
            }

            if action.begin then
                local ok, err = pcall(action.begin, mode)
                if not ok then
                    logActionError("Queued begin failed", err)
                    history.active = nil
                    shouldStart = false
                end
            end

            if shouldStart then
                return true
            end
        end
    end

    return false
end

local function finishActiveAction(success)
    if not history.active then
        return
    end

    local mode = history.active.mode
    local action = history.active.action

    if action and action.finish then
        local ok, err = pcall(action.finish, mode)
        if not ok then
            logActionError("Queued finish failed", err)
        end
    end

    if success then
        if mode == "undo" then
            history.index = math.max(0, history.index - 1)
        else
            history.index = math.min(#history.actions, history.index + 1)
        end
    end

    history.active = nil
    history.propBeingEdited = false
    rebuildCache(true)
end

local function processActiveStep(budgetMs)
    if not history.active then
        return true
    end

    local action = history.active.action
    local mode = history.active.mode
    local done = false
    local success = true

    if action.step then
        local ok, result = pcall(action.step, mode, budgetMs)
        if not ok then
            logActionError("Queued step failed", result)
            done = true
            success = false
        else
            done = result == true
        end
    else
        local fn = mode == "undo" and action.undo or action.redo
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                logActionError("Queued " .. mode .. " failed", err)
                success = false
            end
        else
            success = false
        end
        done = true
    end

    if done then
        finishActiveAction(success)
        return true
    end

    return false
end

---@param frameBudgetMs number?
function history.update(frameBudgetMs)
    local budgetMs = frameBudgetMs or history.frameBudgetMs
    if budgetMs <= 0 then
        budgetMs = history.frameBudgetMs
    end

    local deadline = os.clock() + (budgetMs / 1000)
    while os.clock() < deadline do
        if not history.active then
            if not beginNextPendingAction() then
                break
            end
        end

        local remainingMs = math.max((deadline - os.clock()) * 1000, 0)
        if remainingMs <= 0 then
            break
        end

        local finished = processActiveStep(remainingMs)
        if not finished then
            break
        end
    end
end

function history.undo()
    if history.active then
        return
    end
    if history.index == 0 then
        return
    end

    local action = history.actions[history.index]
    local success = runActionImmediate(action, "undo")
    if success then
        history.index = history.index - 1
    end
    history.propBeingEdited = false
    rebuildCache(true)
end

function history.redo()
    if history.active then
        return
    end
    if history.index == #history.actions then
        return
    end

    local action = history.actions[history.index + 1]
    local success = runActionImmediate(action, "redo")
    if success then
        history.index = history.index + 1
    end
    history.propBeingEdited = false
    rebuildCache(true)
end

return history
