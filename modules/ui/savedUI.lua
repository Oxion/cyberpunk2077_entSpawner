local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local amm = require("modules/utils/ammUtils")
local history = require("modules/utils/history")
local groupLoadManager = require("modules/utils/pipeline/groupLoadManager")
local groupAMMImportManager = require("modules/utils/pipeline/groupAMMImportManager")
local backup = require("modules/utils/backup")

savedUI = {
    filter = "",
    color = {group = {0, 255, 0}, object = {0, 50, 255}},
    box = {group = {x = 600, y = 116}, object = {x = 600, y = 133}},
    files = {},
    invalidFiles = {},
    corruptedColor = 0xFF00A5FF,
    spawner = nil,
    popup = false,
    deleteFile = nil,
    popupDontAskAgain = false,
    spawned = {},
    maxTextWidth = nil,
    pendingReload = false,
    pendingGroupOpenState = nil
}

---@param group table
---@param spawner spawner
---@param loadHidden boolean?
function savedUI.startQueuedGroupLoad(group, spawner, loadHidden)
    local hidden = loadHidden == true

    groupLoadManager.start({
        spawner = spawner,
        data = group,
        targetParent = spawner.baseUI.spawnedUI.root,
        setAsSpawnNew = settings.setLoadedGroupAsSpawnNew and not hidden,
        loadHidden = hidden
    })
end

local function isSavedGroup(data)
    return data and (data.type == "group"
        or data.modulePath == "modules/classes/editor/positionableGroup"
        or data.modulePath == "modules/classes/editor/randomizedGroup")
end

local function isSavedElement(data)
    return data and (data.type == "object"
        or data.type == "element"
        or data.modulePath == "modules/classes/editor/spawnableElement")
end

local function hasSavedGroups()
    for _, data in pairs(savedUI.files) do
        if isSavedGroup(data) then
            return true
        end
    end

    return false
end

---@param pos table?
---@return boolean
local function isPositionValid(pos)
    return type(pos) == "table"
        and type(pos.x) == "number"
        and type(pos.y) == "number"
        and type(pos.z) == "number"
end

---@param fileName string
---@param data any
---@return boolean
local function validateSavedEntry(fileName, data)
    if type(data) ~= "table" then
        savedUI.invalidFiles[fileName] = true
        return false
    end

    if type(data.name) ~= "string" or data.name == "" then
        savedUI.invalidFiles[fileName] = true
        return false
    end

    if isSavedGroup(data) then
        if type(data.childs) ~= "table" or not isPositionValid(data.pos) then
            savedUI.invalidFiles[fileName] = true
            return false
        end

        savedUI.invalidFiles[fileName] = nil
        return true
    end

    if isSavedElement(data) then
        if type(data.spawnable) ~= "table" or not isPositionValid(data.spawnable.position) then
            savedUI.invalidFiles[fileName] = true
            return false
        end

        savedUI.invalidFiles[fileName] = nil
        return true
    end

    savedUI.invalidFiles[fileName] = true
    return false
end

---@param fileName string
local function loadSavedEntry(fileName)
    local data = config.loadFile("data/objects/" .. fileName)

    if validateSavedEntry(fileName, data) then
        savedUI.files[fileName] = data
    else
        savedUI.files[fileName] = nil
    end
end

---@param fileName string
---@param data table?
---@return boolean
function savedUI.refreshEntry(fileName, data)
    if type(fileName) ~= "string" or fileName == "" then
        return false
    end

    if data ~= nil then
        if validateSavedEntry(fileName, data) then
            savedUI.files[fileName] = data
            return true
        end

        savedUI.files[fileName] = nil
        return false
    end

    local fullPath = "data/objects/" .. fileName
    if not config.fileExists(fullPath) then
        savedUI.files[fileName] = nil
        savedUI.invalidFiles[fileName] = nil
        return false
    end

    loadSavedEntry(fileName)
    return savedUI.files[fileName] ~= nil
end

local function getToastType(kind)
    if kind == "error" and ImGui.ToastType and ImGui.ToastType.Error then
        return ImGui.ToastType.Error
    end

    return ImGui.ToastType.Success
end

---@param source "on_save"|"on_game_load"
---@param fileName string
local function queueBackupRestore(source, fileName)
    local sourceLabel = source == "on_save" and "previous save" or "game load"

    if backup.restoreObjectBackup(source, fileName) then
        savedUI.pendingReload = true
        ImGui.ShowToast(ImGui.Toast.new(getToastType("success"), 5000, string.format("Restored \"%s\" from %s", fileName, sourceLabel)))
    else
        ImGui.ShowToast(ImGui.Toast.new(getToastType("error"), 5000, string.format("Failed to restore \"%s\" from %s", fileName, sourceLabel)))
    end
end

---@param source "on_save"|"on_game_load"
---@param label string
---@param fileName string
local function drawBackupRestoreAction(source, label, fileName)
    local exists, timestamp = backup.getObjectBackupInfo(source, fileName)
    local displayTimestamp = timestamp

    style.pushGreyedOut(not exists)
    if ImGui.Button(label .. "##" .. source) and exists then
        queueBackupRestore(source, fileName)
    end
    style.popGreyedOut(not exists)

    if type(displayTimestamp) ~= "string" or displayTimestamp == "" then
        displayTimestamp = "Unknown"
    end

    ImGui.SameLine()
    style.mutedText(displayTimestamp)
end

---@param fileName string
local function drawBackupRestoreActions(fileName)
    ImGui.Dummy(0, 4 * style.viewSize)
    style.sectionHeaderStart("BACKUP")
    drawBackupRestoreAction("on_save", "Restore previous save", fileName)
    drawBackupRestoreAction("on_game_load", "Restore from game load", fileName)
end

---@param fileName string
---@param tagX number
local function drawCorruptedEntry(fileName, tagX)
    style.pushStyleColor(true, ImGuiCol.Text, savedUI.corruptedColor)
    local open = ImGui.TreeNodeEx(fileName)
    style.popStyleColor(true)

    ImGui.SameLine()
    ImGui.SetCursorPosX(tagX)
    style.styledText("CORRUPTED", savedUI.corruptedColor, 0.9)

    if open then
        style.styledText("Cannot parse this save file.", savedUI.corruptedColor, 0.9)

        ImGui.PushID("corruptedBackup" .. fileName)
        drawBackupRestoreActions(fileName)
        ImGui.PopID()

        ImGui.TreePop()
        ImGui.Spacing()
    end
end

local function syncSavedFileCaches()
    local existing = {}

    for _, file in pairs(dir("data/objects")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            existing[file.name] = true

            if not savedUI.files[file.name] and savedUI.invalidFiles[file.name] == nil then
                loadSavedEntry(file.name)
            end
        end
    end

    for fileName, _ in pairs(savedUI.files) do
        if not existing[fileName] then
            savedUI.files[fileName] = nil
        end
    end

    for fileName, _ in pairs(savedUI.invalidFiles) do
        if not existing[fileName] then
            savedUI.invalidFiles[fileName] = nil
        end
    end
end

---@param group table
---@return number
local function getSavedGroupElementCount(group)
    if group.elementCount ~= nil then
        return group.elementCount
    end

    local count = 0
    local stack = { group }

    while #stack > 0 do
        local current = table.remove(stack)

        for _, child in pairs(current.childs or {}) do
            if isSavedElement(child) then
                count = count + 1
            elseif isSavedGroup(child) then
                table.insert(stack, child)
            end
        end
    end

    group.elementCount = count
    return count
end

local function removeFromExportListIfPresent(data)
    if not isSavedGroup(data) then
        return 0
    end

    local baseUI = savedUI.spawner and savedUI.spawner.baseUI
    if not baseUI or not baseUI.exportUI or not baseUI.exportUI.removeGroupByName then
        return 0
    end

    return baseUI.exportUI.removeGroupByName(data.name)
end

local function showDeletedGroupToast(data, removedFromExport)
    if not isSavedGroup(data) then
        return
    end

    local msg = string.format("Deleted saved group \"%s\"", data.name)
    if removedFromExport > 0 then
        msg = msg .. " and removed it from export list"
    end

    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, msg))
end

function savedUI.convertObject(object, getState)
    local spawnable = require("modules/classes/spawn/entity/entityTemplate"):new()
    spawnable:loadSpawnData({
        spawnData = object.path,
        app = object.app
    }, ToVector4(object.pos), ToEulerAngles(object.rot))

    local newObject = require("modules/classes/editor/spawnableElement"):new(savedUI)
    newObject.name = object.name
    newObject.headerOpen = object.headerOpen
    newObject.loadRange = object.loadRange
    newObject.autoLoad = object.autoLoad
    newObject.spawnable = spawnable

    if getState then
        return newObject:serialize()
    else
        return newObject
    end
end

function savedUI.convertGroup(group)
    local data = {}

    for _, child in pairs(group.childs) do
        if child.type == "object" then
            table.insert(data, savedUI.convertObject(child, true))
        else
            table.insert(data, savedUI.convertGroup(child))
        end
    end

    group.childs = data
    return group
end

function savedUI.backwardComp()
    for _, file in pairs(dir("data/objects")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile("data/objects/" .. file.name)

            if data.type == "object" and data.path then
                config.saveFile("data/oldFormat/" .. file.name, data)

                local new = savedUI.convertObject(data, true)
                config.saveFile("data/objects/" .. file.name, new)
                print("[" .. settings.mainWindowName .. "] Converted \"" .. file.name .. "\" to the new file format.")
            elseif data.type == "group" and not data.isUsingSpawnables then
                config.saveFile("data/oldFormat/" .. file.name, data)

                data = savedUI.convertGroup(data)
                data.isUsingSpawnables = true
                config.saveFile("data/objects/" .. file.name, data)
                print("[" .. settings.mainWindowName .. "] Converted \"" .. file.name .. "\" to the new file format.")
            end
        end
    end
end

function savedUI.importAMMPresets()
    if groupLoadManager.isActive() or amm.importing or groupAMMImportManager.isActive() then return end

    groupAMMImportManager.start({
        savedUI = savedUI
    })
end

function savedUI.draw(spawner)
    if not savedUI.maxTextWidth then
        savedUI.maxTextWidth = utils.getTextMaxWidth({"File name:", "Position:"}) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    ImGui.PushItemWidth(200 * style.viewSize)
    savedUI.filter, changed = ImGui.InputTextWithHint('##Filter', 'Search for data...', savedUI.filter, 100)
    if changed then
        settings.savedUIFilter = savedUI.filter
        settings.save()
    end
    ImGui.PopItemWidth()

    if savedUI.filter ~= '' then
        ImGui.SameLine()

        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            savedUI.filter = ''
            settings.savedUIFilter = savedUI.filter
            settings.save()
        end
        style.pushButtonNoBG(false)
    end

    local ammImportActive = groupAMMImportManager.isActive()
    local blockImport = groupLoadManager.isActive() or amm.importing or ammImportActive
    local framePaddingX = ImGui.GetStyle().FramePadding.x
    local itemSpacingX = ImGui.GetStyle().ItemSpacing.x
    local importLabel = ammImportActive and "Importing AMM Presets..." or "Import AMM Presets"
    local importLabelWidth, _ = ImGui.CalcTextSize(importLabel)
    local reloadLabelWidth, _ = ImGui.CalcTextSize(IconGlyphs.Reload)
    local primaryActionWidth = importLabelWidth + framePaddingX * 2
    local reloadActionWidth = reloadLabelWidth + framePaddingX * 2
    local topActionsWidth = primaryActionWidth + itemSpacingX * 2 + reloadActionWidth

    ImGui.SameLine()
    ImGui.SetCursorPosX(ImGui.GetWindowWidth() - topActionsWidth)
    style.pushGreyedOut(blockImport)
    if ImGui.Button(importLabel) and not blockImport then
        savedUI.importAMMPresets()
    end
    style.popGreyedOut(blockImport)

    if groupLoadManager.isActive() then
        style.tooltip("Import is disabled while a group is loading.")
    elseif ammImportActive then
        style.tooltip("AMM preset import is already running.")
    elseif amm.importing then
        style.tooltip("Another AMM operation is currently running.")
    else
        style.tooltip("Imports all presets from the AMMImport folder.\nImport might take a bit, depending on size.\nThe initial spawn will lag.\nMight leave behind unwanted objects, so reloading a save is advised.")
    end

    ImGui.SameLine()
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.Reload) then
        savedUI.reload()
    end
    style.tooltip("Reload saved groups from disk.")
    style.pushButtonNoBG(false)

    style.spacedSeparator()

    groupLoadManager.drawProgress(style)
    groupAMMImportManager.drawProgress(style)

    style.pushButtonNoBG(true)
    local hasGroups = hasSavedGroups()
    ImGui.BeginDisabled(not hasGroups)
    if ImGui.Button(IconGlyphs.CollapseAllOutline) then
        savedUI.pendingGroupOpenState = false
    end
    style.tooltip("Fold all groups")

    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.ExpandAllOutline) then
        savedUI.pendingGroupOpenState = true
    end
    style.tooltip("Expand all groups")
    ImGui.EndDisabled()
    style.pushButtonNoBG(false)

    ImGui.BeginChild("savedUI")

    local qtyHeader = "Qty assets"
    local qtyHeaderWidth, _ = ImGui.CalcTextSize(qtyHeader)
    local headerScrollBarAddition = ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0
    local qtyHeaderX = ImGui.GetWindowWidth() - qtyHeaderWidth - ImGui.GetStyle().CellPadding.x / 2 - headerScrollBarAddition + ImGui.GetScrollX()

    style.mutedText("Group name")
    ImGui.SameLine()
    ImGui.SetCursorPosX(qtyHeaderX)
    style.mutedText(qtyHeader)
    ImGui.Separator()

    syncSavedFileCaches()

    local sortedCorruptedFiles = utils.getKeys(savedUI.invalidFiles)
    table.sort(sortedCorruptedFiles, function(a, b)
        return a:lower() < b:lower()
    end)

    for _, fileName in ipairs(sortedCorruptedFiles) do
        if fileName:lower():match(savedUI.filter:lower()) ~= nil then
            drawCorruptedEntry(fileName, qtyHeaderX)
        end
    end

    for fileName, d in pairs(savedUI.files) do
        if d and type(d.name) == "string" and (d.name:lower():match(savedUI.filter:lower())) ~= nil then
            if isSavedGroup(d) then
                savedUI.drawGroup(d, spawner, fileName)
            elseif d.type == "element" or d.modulePath == "modules/classes/editor/spawnableElement" then
                savedUI.drawObject(d, spawner, fileName)
            end
        end
    end

    savedUI.pendingGroupOpenState = nil

    ImGui.EndChild()

    if savedUI.pendingReload then
        savedUI.pendingReload = false
        savedUI.reload()
    end

    savedUI.handlePopUp()
end

---@param group table
---@param spawner spawner
---@param fileName string
function savedUI.drawGroup(group, spawner, fileName)
    if savedUI.pendingGroupOpenState ~= nil then
        ImGui.SetNextItemOpen(savedUI.pendingGroupOpenState, ImGuiCond.Always)
    end

    local open = ImGui.TreeNodeEx(group.name)

    local countText = tostring(getSavedGroupElementCount(group))
    local textWidth, _ = ImGui.CalcTextSize(countText)
    local scrollBarAddition = ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0
    local cursorX = ImGui.GetWindowWidth() - textWidth - ImGui.GetStyle().CellPadding.x / 2 - scrollBarAddition + ImGui.GetScrollX()

    ImGui.SameLine()
    ImGui.SetCursorPosX(cursorX)
    style.mutedText(countText)

    if open then
        local pPos = Vector4.new(0, 0, 0, 0)
        if spawner.player then
            pPos = spawner.player:GetWorldPosition()
        end
        local posString = ("X=%.1f Y=%.1f Z=%.1f, Distance: %.1f"):format(group.pos.x, group.pos.y, group.pos.z, ToVector4(group.pos):Distance(pPos))

        if group.newName == nil then group.newName = group.name end

        style.mutedText("File name:")
        ImGui.SameLine()
        ImGui.SetCursorPosX(savedUI.maxTextWidth)
        ImGui.PushItemWidth(180 * style.viewSize)
        group.newName = ImGui.InputTextWithHint('##Name', 'Name...', group.newName, 100)
        ImGui.PopItemWidth()

        if ImGui.IsItemDeactivatedAfterEdit() then
            savedUI.files[fileName] = nil
            savedUI.invalidFiles[fileName] = nil

            local newFileName = group.newName .. ".json"
            os.rename("data/objects/" .. fileName, "data/objects/" .. newFileName)
            group.name = group.newName
            group.lastEditedAt = os.date("%Y-%m-%d %H:%M:%S")
            config.saveFile("data/objects/" .. newFileName, group)
            savedUI.files[newFileName] = group
            fileName = newFileName
        end

        style.mutedText("Position:")
        ImGui.SameLine()
        ImGui.SetCursorPosX(savedUI.maxTextWidth)
        ImGui.Text(posString)

        local groupLoadActive = groupLoadManager.isActive() or groupAMMImportManager.isActive()
        style.pushGreyedOut(groupLoadActive)
        if ImGui.Button("Load") and not groupLoadActive then
            savedUI.startQueuedGroupLoad(group, spawner)
        end
        if groupLoadActive then
            style.tooltip("Loading is disabled while another pipeline operation is active")
        else
            style.tooltip("Load and spawn the group immediately")
        end

        ImGui.SameLine()
        if ImGui.Button("Load as Hidden") and not groupLoadActive then
            savedUI.startQueuedGroupLoad(group, spawner, true)
        end
        if groupLoadActive then
            style.tooltip("Loading is disabled while another pipeline operation is active")
        else
            style.tooltip("Load with hidden root so children are kept despawned until shown")
        end
        style.popGreyedOut(groupLoadActive)

        ImGui.SameLine()
        if style.warnButton(IconGlyphs.RunFast) then
            Game.GetTeleportationFacility():Teleport(Game.GetPlayer(), utils.getVector(group.pos), GetSingleton('Quaternion'):ToEulerAngles(Game.GetPlayer():GetWorldOrientation()))
        end
	    style.tooltip("Teleport player to group")

        ImGui.SameLine()
        if ImGui.Button("Add to Export") then
            spawner.baseUI.exportUI.addGroup(group.name)
        end
        
        ImGui.SameLine()
        if style.dangerButton(IconGlyphs.DeleteOutline) then
            savedUI.deleteData(group)
        end
	    style.tooltip("Delete group")

        ImGui.PushID("groupBackup" .. fileName)
        drawBackupRestoreActions(fileName)
        ImGui.PopID()

        ImGui.TreePop()
        ImGui.Spacing()
    end
end

---@param obj table
---@param spawner spawner
---@param fileName string
function savedUI.drawObject(obj, spawner, fileName)
    if ImGui.TreeNodeEx(obj.name) then
        local pPos = Vector4.new(0, 0, 0, 0)
        if spawner.player then
            pPos = spawner.player:GetWorldPosition()
        end
        local posString = ("X=%.1f Y=%.1f Z=%.1f, Distance: %.1f"):format(obj.spawnable.position.x, obj.spawnable.position.y, obj.spawnable.position.z, ToVector4(obj.spawnable.position):Distance(pPos))

        if obj.newName == nil then obj.newName = obj.name end

        ImGui.SetNextItemWidth(180 * style.viewSize)
        obj.newName = ImGui.InputTextWithHint('##Name', 'Name...', obj.newName, 100)
        ImGui.PopItemWidth()

        if ImGui.IsItemDeactivatedAfterEdit() then
            savedUI.files[fileName] = nil
            savedUI.invalidFiles[fileName] = nil

            local newFileName = obj.newName .. ".json"
            os.rename("data/objects/" .. fileName, "data/objects/" .. newFileName)
            obj.name = obj.newName
            obj.lastEditedAt = os.date("%Y-%m-%d %H:%M:%S")
            config.saveFile("data/objects/" .. newFileName, obj)
            savedUI.files[newFileName] = obj
            fileName = newFileName
        end

        ImGui.PushID("objectBackup" .. fileName)
        drawBackupRestoreActions(fileName)
        ImGui.PopID()

        style.mutedText("Position:")
        ImGui.SameLine()
        ImGui.Text(posString)

        style.mutedText("Type:")
        ImGui.SameLine()
        ImGui.Text(obj.spawnable.dataType)

        local pipelineBusy = groupLoadManager.isActive() or groupAMMImportManager.isActive()
        style.pushGreyedOut(pipelineBusy)
        if ImGui.Button("Load") and not pipelineBusy then
            local o = require("modules/classes/editor/spawnableElement"):new(spawner.baseUI.spawnedUI)
            o:load(obj)
            spawner.baseUI.spawnedUI.addRootElement(o)
            history.addAction(history.getInsert({ o }))
        end
        if pipelineBusy then
            style.tooltip("Loading is disabled while another pipeline operation is active")
        else
            style.tooltip("Load object immediately")
        end
        style.popGreyedOut(pipelineBusy)

        ImGui.SameLine()
        if ImGui.Button("TP to pos") then
            Game.GetTeleportationFacility():Teleport(Game.GetPlayer(),  utils.getVector(obj.pos), GetSingleton('Quaternion'):ToEulerAngles(Game.GetPlayer():GetWorldOrientation()))
        end
        ImGui.SameLine()
        if ImGui.Button("Delete") then
            savedUI.deleteData(obj)
        end

        ImGui.TreePop()
        ImGui.Spacing()
    end
end

function savedUI.deleteData(data)
    if settings.deleteConfirm then
        savedUI.popup = true
        savedUI.deleteFile = data
        savedUI.popupDontAskAgain = not settings.deleteConfirm
    else
        os.remove("data/objects/" .. data.name .. ".json")
        savedUI.files[data.name .. ".json"] = nil
        savedUI.invalidFiles[data.name .. ".json"] = nil

        local removedFromExport = removeFromExportListIfPresent(data)
        showDeletedGroupToast(data, removedFromExport)
    end
end

function savedUI.handlePopUp()
    if savedUI.popup then
        ImGui.OpenPopup("Delete Data?")
        if ImGui.BeginPopupModal("Delete Data?", true, ImGuiWindowFlags.AlwaysAutoResize) then
            local targetName = savedUI.deleteFile and savedUI.deleteFile.name or "Unknown"
            ImGui.Text("Delete \"" .. targetName .. "\"?")
            style.mutedText("This action cannot be undone.")
            ImGui.Dummy(0, 8 * style.viewSize)
            savedUI.popupDontAskAgain = ImGui.Checkbox("Don't ask again", savedUI.popupDontAskAgain)
            ImGui.Dummy(0, 8 * style.viewSize)

            if ImGui.Button("Cancel") then
                ImGui.CloseCurrentPopup()
                savedUI.popup = false
                savedUI.deleteFile = nil
            end

            ImGui.SameLine()

            if ImGui.Button("Confirm") then
                ImGui.CloseCurrentPopup()
                -- Store user preference
                settings.deleteConfirm = not savedUI.popupDontAskAgain
                settings.save()
                -- Delete the file
                os.remove("data/objects/" .. savedUI.deleteFile.name .. ".json")
                savedUI.files[savedUI.deleteFile.name .. ".json"] = nil
                savedUI.invalidFiles[savedUI.deleteFile.name .. ".json"] = nil

                local removedFromExport = removeFromExportListIfPresent(savedUI.deleteFile)
                showDeletedGroupToast(savedUI.deleteFile, removedFromExport)

                savedUI.deleteFile = nil
                savedUI.popup = false
                savedUI.deleteFile = nil
            end
            ImGui.EndPopup()
        end
    end
end

function savedUI.reload()
    savedUI.files = {}
    savedUI.invalidFiles = {}
    savedUI.pendingReload = false

    for _, file in pairs(dir("data/objects")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            loadSavedEntry(file.name)
        end
    end
end

return savedUI
