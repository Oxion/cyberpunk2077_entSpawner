local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local Cron = require("modules/utils/Cron")

local minScriptVersion = "1.0.4"
local sectorCategory
local serializedGroupModulePaths = {
    ["modules/classes/editor/positionableGroup"] = true,
    ["modules/classes/editor/randomizedGroup"] = true
}

exportUI = {
    projectName = "",
    xlFormat = 0,
    groups = {},
    templates = {},
    spawner = nil,
    exportHovered = false,
    exportIssues = {
        nodeRefDuplicated = {},
        noOutlineMarkers = {},
        noSplineMarker = {},
        spotEmptyRef = {},
        spotReferencingEmpty = {},
        markingUnresolved = {},
        missingInitialPhase = {}
    },
    sectorPropertiesWidth = nil,
    mainPropertiesWidth = nil,
    templateDeletePopup = false,
    templateDeleteTarget = nil,
    templateDeleteDontAskAgain = false,
    groupsDividerHovered = false,
    groupsDividerDragging = false,
    templatesDividerHovered = false,
    templatesDividerDragging = false,
    exporting = false,
    exportProgressDone = 0,
    exportProgressTotal = 0,
    exportRuntime = nil,
    pendingToasts = {}
}

function exportUI.init(spawner)
    for _, file in pairs(dir("data/exportTemplates/")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile("data/exportTemplates/" .. file.name)

            if data.groups then
                for key, group in pairs(data.groups) do
                    if not config.fileExists("data/objects/" .. group.name .. ".json") then
                        data.groups[key] = nil
                    end
                end

                exportUI.templates[data.projectName] = data
            end
        end
    end

    exportUI.spawner = spawner
end

local function calculateExtents(center, objects)
    local maxExtent = {x = 0, y = 0, z = 0}

    for _, point in ipairs(objects) do
        if utils.isA(point.ref, "spawnableElement") and Vector4.Distance(point.ref:getPosition(), Vector4.new(0, 0, 0, 0)) > 25 then
            local pos = point.ref:getPosition()
            local range = math.min(point.ref.spawnable.primaryRange, 250)

            local dx = math.abs(pos.x - center.x) + range
            local dy = math.abs(pos.y - center.y) + range
            local dz = math.abs(pos.z - center.z) + range

            maxExtent.x = math.max(maxExtent.x, dx)
            maxExtent.y = math.max(maxExtent.y, dy)
            maxExtent.z = math.max(maxExtent.z, dz)
        end
    end

    return maxExtent
end

local function drawVariantsTooltip()
    ImGui.SameLine()
    ImGui.Text(IconGlyphs.InformationOutline)
    style.tooltip("All objects placed within the root of the group will be part of the default variant\nYou can assign to each group what variant they should belong to")
end

---@param name string
---@return table?
local function loadSavedGroupBlob(name)
    if not name then return nil end

    local path = "data/objects/" .. name .. ".json"
    if not config.fileExists(path) then
        return nil
    end

    return config.loadFile(path)
end

---@param entry table?
---@return boolean
local function isSerializedGroupEntry(entry)
    return entry ~= nil and (entry.type == "group" or serializedGroupModulePaths[entry.modulePath] == true)
end

---@param blob table?
---@param existingVariantData table?
---@return table
local function buildVariantDataFromBlob(blob, existingVariantData)
    local variants = {}

    for _, child in pairs(blob and blob.childs or {}) do
        if isSerializedGroupEntry(child) and child.name then
            local existing = existingVariantData and existingVariantData[child.name]
            variants[child.name] = {
                name = existing and existing.name or "default",
                ref = existing and existing.ref or "",
                defaultOn = existing == nil or existing.defaultOn ~= false
            }
        end
    end

    return variants
end

---@param blob table?
---@param fallback table?
---@return table
local function resolveGroupCenter(blob, fallback)
    local source = nil
    if blob and blob.pos then
        source = blob.pos
    elseif blob and blob.origin then
        source = blob.origin
    end

    if source then
        return {
            x = source.x or 0,
            y = source.y or 0,
            z = source.z or 0
        }
    end

    if fallback then
        return {
            x = fallback.x or 0,
            y = fallback.y or 0,
            z = fallback.z or 0
        }
    end

    return { x = 0, y = 0, z = 0 }
end

function exportUI.drawGroups()
    local defaultSize = 260
    local minSize = 120 * style.viewSize
    local maxSize = 800 * style.viewSize
    settings.exportGroupsHeight = math.max(minSize, math.min(maxSize, settings.exportGroupsHeight or 260))

    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)

    ImGui.BeginChildFrame(1, 0, settings.exportGroupsHeight)

    if #exportUI.groups > 0 then
        for key, group in ipairs(exportUI.groups) do
            ImGui.BeginGroup()

            local nodeFlags = ImGuiTreeNodeFlags.SpanFullWidth
            if ImGui.TreeNodeEx(group.name, nodeFlags) then
                ImGui.PopStyleColor()
                ImGui.PopStyleVar()

                if not exportUI.sectorPropertiesWidth then
                    exportUI.sectorPropertiesWidth = utils.getTextMaxWidth({ "Group file name:", "Sector Category:", "Sector Level:", "Streaming Box Extents:" }) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
                end

                if ImGui.TreeNodeEx("Variants", ImGuiTreeNodeFlags.SpanFullWidth) then
                    drawVariantsTooltip()

                    style.mutedText("Variant Node Ref")
                    ImGui.SameLine()
                    group.variantRef = ImGui.InputTextWithHint('##variantRef', '$/#foobar', group.variantRef, 100)

                    for name, _ in pairs(group.variantData) do
                        ImGui.PushID(name)
                        ImGui.SetNextItemWidth(100 * style.viewSize)
                        group.variantData[name].name = ImGui.InputTextWithHint('##variantName', 'default', group.variantData[name].name, 100)
                        ImGui.SameLine()
                        ImGui.SetNextItemWidth(185 * style.viewSize)
                        local default = group.variantData[name].name == "default"
                        style.pushGreyedOut(default)
                        group.variantData[name].defaultOn, changed = ImGui.Checkbox("Default On", group.variantData[name].defaultOn)
                        style.popGreyedOut(default)
                        if default then
                            group.variantData[name].defaultOn = true
                        end
                        if changed and not default then
                            for variant, _ in pairs(group.variantData) do
                                if group.variantData[variant].name == group.variantData[name].name then
                                    group.variantData[variant].defaultOn = group.variantData[name].defaultOn
                                end
                            end
                        end
                        ImGui.SameLine()
                        style.mutedText(name)

                        ImGui.PopID()
                    end

                    ImGui.TreePop()
                else
                    drawVariantsTooltip()
                end

                style.mutedText("Group file name:")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                ImGui.Text(group.name)

                style.mutedText("Sector Category:")
                style.tooltip("Select the type of the sector for the group, if in doubt use Interior or Exterior")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                ImGui.SetNextItemWidth(150 * style.viewSize)
                group.category = ImGui.Combo("##category", group.category, sectorCategory, #sectorCategory)

                if group.category == 3 then
                    style.mutedText("Prefab Ref:")
                    style.tooltip("Prefab NodeRef of the sector")
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                    ImGui.SetNextItemWidth(150 * style.viewSize)

                    group.prefabRef, _ = ImGui.InputTextWithHint('##prefabRef', '$/#foobar', group.prefabRef, 100)
                end

                style.mutedText("Sector Level:")
                style.tooltip("Select the level of the sector for the group")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                ImGui.SetNextItemWidth(150 * style.viewSize)
                group.level, changed = ImGui.InputInt("##level", group.level)
                if changed then
                    group.level = math.min(math.max(group.level, 0), 6)
                end

                style.mutedText("Streaming Box Extents:")
                style.tooltip("Change the size of the streaming box for the sector, extends the given amount on each axis in both directions")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                if ImGui.Button("Auto") then
                    local blob = config.loadFile("data/objects/" .. group.name .. ".json")
                    local g = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
                    g:load(blob, true)

                    local extents = calculateExtents(group.center, g:getPathsRecursive(false))
                    group.streamingX = extents.x * 1.2
                    group.streamingY = extents.y * 1.2
                    group.streamingZ = extents.z * 1.2
                end
                ImGui.SameLine()
                ImGui.PushItemWidth(90 * style.viewSize)
                group.streamingX = ImGui.DragFloat("##x", group.streamingX, 0.25, 0, 9999, "%.1f X Size")
                ImGui.SameLine()
                group.streamingY = ImGui.DragFloat("##y", group.streamingY, 0.25, 0, 9999, "%.1f Y Size")
                ImGui.SameLine()
                group.streamingZ = ImGui.DragFloat("##z", group.streamingZ, 0.25, 0, 9999, "%.1f Z Size")
                ImGui.PopItemWidth()
                ImGui.SameLine()

                local outOfBox = false

                local playerPos = GetPlayer():GetWorldPosition()
                if group.center.x + group.streamingX < playerPos.x or group.center.x - group.streamingX > playerPos.x then
                    outOfBox = true
                end
                if group.center.y + group.streamingY < playerPos.y or group.center.y - group.streamingY > playerPos.y then
                    outOfBox = true
                end
                if group.center.z + group.streamingZ < playerPos.z or group.center.z - group.streamingZ > playerPos.z then
                    outOfBox = true
                end

                local distance = utils.distanceVector(group.center, playerPos)
                style.styledText(IconGlyphs.AxisArrowInfo, outOfBox and 0xFF0000FF or 0xFF00FF00)
                style.tooltip("Distance to player: " .. string.format("%.2f", distance))

                if ImGui.Button("Remove from list") then
                    table.remove(exportUI.groups, key)
                end

                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
                ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
                ImGui.TreePop()
            end
            ImGui.EndGroup()
        end
    else
        ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
        ImGui.TextWrapped("No groups yet added, add them from the \"Saved\" tab!")
        ImGui.PopStyleColor()
    end

    ImGui.EndChildFrame()
    ImGui.PopStyleColor()
    ImGui.PopStyleVar(2)

    if exportUI.groupsDividerHovered then
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.4, 0.4, 0.4, 1.0)
    else
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.2, 0.2, 0.2, 1.0)
    end

    ImGui.BeginChild("##groupsDivider", 0, 7.5 * style.viewSize, false, ImGuiWindowFlags.NoMove)
    local wx, wy = ImGui.GetContentRegionAvail()
    local textWidth, textHeight = ImGui.CalcTextSize(IconGlyphs.DragHorizontalVariant)
    ImGui.SetCursorPosX((wx - textWidth) / 2)
    ImGui.SetCursorPosY(1 * style.viewSize + (wy - textHeight) / 2)
    ImGui.Text(IconGlyphs.DragHorizontalVariant)
    ImGui.EndChild()
    if exportUI.groupsDividerHovered and ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) then
        settings.exportGroupsHeight = defaultSize
        settings.save()
    end
    exportUI.groupsDividerHovered = ImGui.IsItemHovered()

    if exportUI.groupsDividerHovered and ImGui.IsMouseDragging(0, 0) then
        exportUI.groupsDividerDragging = true
    end
    if exportUI.groupsDividerDragging and not ImGui.IsMouseDragging(0, 0) then
        exportUI.groupsDividerDragging = false
        settings.save()
    end
    if exportUI.groupsDividerDragging then
        local _, dy = ImGui.GetMouseDragDelta(0, 0)
        settings.exportGroupsHeight = settings.exportGroupsHeight + dy
        settings.exportGroupsHeight = math.max(minSize, math.min(maxSize, settings.exportGroupsHeight))
        ImGui.ResetMouseDragDelta()
    end
    if exportUI.groupsDividerHovered or exportUI.groupsDividerDragging then
        ImGui.SetMouseCursor(ImGuiMouseCursor.ResizeNS)
    end
    ImGui.PopStyleColor()
end

function exportUI.loadTemplate(data)
    local existingNames = {}
    for _, existing in ipairs(exportUI.groups) do
        if existing.name then
            existingNames[existing.name] = true
        end
    end

    for _, group in pairs(data.groups or {}) do
        local blob = loadSavedGroupBlob(group.name)
        if blob then
            local mapped = {
                name = group.name,
                category = group.category or 1,
                level = group.level or 1,
                streamingX = group.streamingX or 150,
                streamingY = group.streamingY or 150,
                streamingZ = group.streamingZ or 100,
                center = resolveGroupCenter(blob, group.center),
                prefabRef = group.prefabRef or "",
                variantRef = group.variantRef or "",
                variantData = buildVariantDataFromBlob(blob, group.variantData)
            }

            if not existingNames[mapped.name] then
                table.insert(exportUI.groups, mapped)
                existingNames[mapped.name] = true
            end
        end
    end

    exportUI.xlFormat = data.xlFormat or 0
    exportUI.projectName = data.projectName
end

---@param key string
---@param data table
local function deleteTemplateEntry(key, data)
    local templateName = data and data.projectName or key
    if not templateName then return end

    os.remove("data/exportTemplates/" .. templateName .. ".json")
    exportUI.templates[key] = nil
end

---@param key string
---@param data table
function exportUI.deleteTemplate(key, data)
    if settings.skipTemplateDeleteConfirm then
        deleteTemplateEntry(key, data)
        return
    end

    exportUI.templateDeletePopup = true
    exportUI.templateDeleteTarget = { key = key, data = data }
    exportUI.templateDeleteDontAskAgain = settings.skipTemplateDeleteConfirm
end

function exportUI.handleTemplateDeletePopup()
    if exportUI.templateDeletePopup then
        ImGui.OpenPopup("Delete Template?")
        if ImGui.BeginPopupModal("Delete Template?", true, ImGuiWindowFlags.AlwaysAutoResize) then
            local targetName = exportUI.templateDeleteTarget and exportUI.templateDeleteTarget.data and exportUI.templateDeleteTarget.data.projectName or "Unknown"
            ImGui.Text("Delete \"" .. targetName .. "\"?")
            style.mutedText("This action cannot be undone.")
            ImGui.Dummy(0, 8 * style.viewSize)
            exportUI.templateDeleteDontAskAgain = ImGui.Checkbox("Don't ask again", exportUI.templateDeleteDontAskAgain)
            ImGui.Dummy(0, 8 * style.viewSize)

            if ImGui.Button("Cancel") then
                ImGui.CloseCurrentPopup()
                exportUI.templateDeletePopup = false
                exportUI.templateDeleteTarget = nil
            end

            ImGui.SameLine()

            if ImGui.Button("Confirm") then
                ImGui.CloseCurrentPopup()
                settings.skipTemplateDeleteConfirm = exportUI.templateDeleteDontAskAgain
                settings.save()

                local target = exportUI.templateDeleteTarget
                if target and target.key and target.data then
                    deleteTemplateEntry(target.key, target.data)
                end

                exportUI.templateDeletePopup = false
                exportUI.templateDeleteTarget = nil
            end

            ImGui.EndPopup()
        end
    end
end

function exportUI.drawTemplates()
    local defaultSize = 160
    local minSize = 80 * style.viewSize
    local maxSize = 500 * style.viewSize
    settings.exportTemplatesHeight = math.max(minSize, math.min(maxSize, settings.exportTemplatesHeight or 160))

    if utils.tableLength(exportUI.templates) > 0 then
        ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)

        ImGui.BeginChildFrame(2, 0, settings.exportTemplatesHeight)

        local sortedTemplates = {}
        for key, data in pairs(exportUI.templates) do
            table.insert(sortedTemplates, { key = key, data = data })
        end

        table.sort(sortedTemplates, function(a, b)
            local aName = tostring(a.data.projectName or a.key or ""):lower()
            local bName = tostring(b.data.projectName or b.key or ""):lower()

            if aName == bName then
                return tostring(a.key) < tostring(b.key)
            end

            return aName < bName
        end)

        for _, entry in ipairs(sortedTemplates) do
            local key = entry.key
            local data = entry.data
            ImGui.BeginGroup()

            local nodeFlags = ImGuiTreeNodeFlags.SpanFullWidth
            if ImGui.TreeNodeEx(data.projectName, nodeFlags) then
                ImGui.PopStyleColor()
                ImGui.PopStyleVar()

                style.mutedText("Groups:")
                ImGui.SameLine()
                ImGui.Text(tostring(#data.groups))

                if ImGui.Button("Load") then
                    exportUI.loadTemplate(data)
                end
                ImGui.SameLine()
                if ImGui.Button("Delete") then
                    exportUI.deleteTemplate(key, data)
                end

                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
                ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
                ImGui.TreePop()
            end
            ImGui.EndGroup()
        end

        ImGui.EndChildFrame()
        ImGui.PopStyleColor()
        ImGui.PopStyleVar(2)
    else
        ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
        ImGui.BeginChildFrame(2, 0, settings.exportTemplatesHeight)
        ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
        ImGui.TextWrapped("No templates created yet.")
        ImGui.PopStyleColor()
        ImGui.EndChildFrame()
        ImGui.PopStyleColor()
        ImGui.PopStyleVar(2)
    end

    if exportUI.templatesDividerHovered then
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.4, 0.4, 0.4, 1.0)
    else
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0.2, 0.2, 0.2, 1.0)
    end

    ImGui.BeginChild("##templatesDivider", 0, 7.5 * style.viewSize, false, ImGuiWindowFlags.NoMove)
    local wx, wy = ImGui.GetContentRegionAvail()
    local textWidth, textHeight = ImGui.CalcTextSize(IconGlyphs.DragHorizontalVariant)
    ImGui.SetCursorPosX((wx - textWidth) / 2)
    ImGui.SetCursorPosY(1 * style.viewSize + (wy - textHeight) / 2)
    ImGui.Text(IconGlyphs.DragHorizontalVariant)
    ImGui.EndChild()
    if exportUI.templatesDividerHovered and ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) then
        settings.exportTemplatesHeight = defaultSize
        settings.save()
    end
    exportUI.templatesDividerHovered = ImGui.IsItemHovered()

    if exportUI.templatesDividerHovered and ImGui.IsMouseDragging(0, 0) then
        exportUI.templatesDividerDragging = true
    end
    if exportUI.templatesDividerDragging and not ImGui.IsMouseDragging(0, 0) then
        exportUI.templatesDividerDragging = false
        settings.save()
    end
    if exportUI.templatesDividerDragging then
        local _, dy = ImGui.GetMouseDragDelta(0, 0)
        settings.exportTemplatesHeight = settings.exportTemplatesHeight + dy
        settings.exportTemplatesHeight = math.max(minSize, math.min(maxSize, settings.exportTemplatesHeight))
        ImGui.ResetMouseDragDelta()
    end
    if exportUI.templatesDividerHovered or exportUI.templatesDividerDragging then
        ImGui.SetMouseCursor(ImGuiMouseCursor.ResizeNS)
    end
    ImGui.PopStyleColor()
end

function exportUI.getCurrentIssue()
    for key, value in pairs(exportUI.exportIssues) do
        if #value ~= 0 then
            return key
        end
    end
end

function exportUI.resetIssues()
    for key, _ in pairs(exportUI.exportIssues) do
        exportUI.exportIssues[key] = {}
    end
end

local function nowMs()
    return os.clock() * 1000
end

local function copyNodeDataWithoutChildren(data)
    local copied = {}

    for key, value in pairs(data or {}) do
        if key ~= "childs" then
            copied[key] = value
        end
    end

    return copied
end

local function addChildFast(parent, child)
    if not parent or not child then
        return
    end

    child.parent = parent
    parent.childs = parent.childs or {}
    table.insert(parent.childs, child)
end

local function queueBuildEntry(current, data, parent)
    current.buildTail = current.buildTail + 1
    current.buildQueue[current.buildTail] = { data = data, parent = parent }
    current.buildTotal = current.buildTotal + 1
end

local function createExportRuntime(previous)
    local buildChunkSize = previous and previous.buildChunkSize or 220
    local buildTimeBudgetMs = previous and previous.buildTimeBudgetMs or 6
    local exportChunkSize = previous and previous.exportChunkSize or 90
    local exportTimeBudgetMs = previous and previous.exportTimeBudgetMs or 6

    return {
        active = false,
        phase = "idle", -- idle|build|export|finalize
        timer = nil,
        groups = {},
        totalGroups = 0,
        groupIndex = 1,
        completedGroups = 0,
        current = nil,
        project = nil,
        state = nil,
        buildChunkSize = buildChunkSize,
        buildTimeBudgetMs = buildTimeBudgetMs,
        exportChunkSize = exportChunkSize,
        exportTimeBudgetMs = exportTimeBudgetMs
    }
end

local clearCurrentGroup

local function syncExportProgress(runtime)
    exportUI.exporting = runtime and runtime.active == true or false
    if runtime and runtime.active then
        exportUI.exportProgressDone = runtime.completedGroups or 0
        exportUI.exportProgressTotal = runtime.totalGroups or 0
    else
        exportUI.exportProgressDone = 0
        exportUI.exportProgressTotal = 0
    end
end

local function haltRuntimeTimer(runtime)
    if runtime and runtime.timer then
        Cron.Halt(runtime.timer)
        runtime.timer = nil
    end
end

local function resolveToastType(kind)
    if kind == "info" and ImGui.ToastType and ImGui.ToastType.Info then
        return ImGui.ToastType.Info
    end

    if kind == "warning" and ImGui.ToastType and ImGui.ToastType.Warning then
        return ImGui.ToastType.Warning
    end

    if kind == "error" and ImGui.ToastType and ImGui.ToastType.Error then
        return ImGui.ToastType.Error
    end

    return ImGui.ToastType.Success
end

local function queueToast(kind, duration, text)
    table.insert(exportUI.pendingToasts, {
        type = resolveToastType(kind),
        duration = duration or 3000,
        text = text
    })
end

function exportUI.drawToasts()
    if #exportUI.pendingToasts > 0 then
        local toast = table.remove(exportUI.pendingToasts, 1)
        ImGui.ShowToast(ImGui.Toast.new(toast.type, toast.duration, toast.text))
    end
end

function exportUI.cancelExport(reason, suppressToast)
    local runtime = exportUI.exportRuntime
    if not runtime or not runtime.active then
        return false
    end

    haltRuntimeTimer(runtime)
    clearCurrentGroup(runtime)
    exportUI.exportRuntime = createExportRuntime(runtime)
    syncExportProgress(exportUI.exportRuntime)

    if not suppressToast then
        local message = "Export cancelled"
        if reason and reason ~= "" then
            message = message .. " (" .. reason .. ")"
        end
        queueToast("warning", 3500, message)
    end

    return true
end

function exportUI.drawExportProgress()
    local runtime = exportUI.exportRuntime
    if not runtime or not runtime.active then
        return false
    end

    local phaseProgress = 0
    local phaseText = ""
    local counterText = ""
    local helpText = ""

    if runtime.phase == "build" and runtime.current then
        local current = runtime.current
        local total = math.max(1, current.buildTotal or 0)
        phaseProgress = (current.buildProcessed or 0) / total
        phaseText = string.format("Preparing \"%s\"", current.name or "Group")
        counterText = string.format("%d/%d", current.buildProcessed or 0, current.buildTotal or 0)
        helpText = "Building group hierarchy in chunks."
    elseif runtime.phase == "export" and runtime.current then
        local current = runtime.current
        local total = math.max(1, current.totalNodes or 0)
        local completed = math.max(0, (current.nodeIndex or 1) - 1)
        phaseProgress = completed / total
        phaseText = string.format("Exporting \"%s\"", current.name or "Group")
        counterText = string.format("%d/%d", completed, current.totalNodes or 0)
        helpText = "Serializing nodes in chunks."
    else
        phaseProgress = 1
        phaseText = "Finalizing export"
        counterText = ""
        helpText = "Writing final export file."
    end

    local totalGroups = math.max(1, runtime.totalGroups or 0)
    local overall = math.min(1, ((runtime.completedGroups or 0) + phaseProgress) / totalGroups)

    ImGui.BeginGroup()
    style.mutedText(phaseText)
    ImGui.ProgressBar(overall, 260 * style.viewSize, 13 * style.viewSize, "")
    ImGui.SameLine()
    style.mutedText(string.format("%d/%d", runtime.completedGroups or 0, runtime.totalGroups or 0))
    if counterText ~= "" then
        style.mutedText(counterText)
    end
    style.mutedText(helpText)
    ImGui.EndGroup()

    local cancelText = "Cancel"
    local cancelTextWidth, _ = ImGui.CalcTextSize(cancelText)
    local cancelButtonWidth = cancelTextWidth + 2 * ImGui.GetStyle().FramePadding.x
    local rightX = ImGui.GetWindowWidth() - ImGui.GetStyle().WindowPadding.x - cancelButtonWidth

    ImGui.SameLine()
    if rightX > ImGui.GetCursorPosX() then
        ImGui.SetCursorPosX(rightX)
    end

    if ImGui.Button(cancelText) then
        exportUI.cancelExport("user request")
    end

    style.spacedSeparator()
    return true
end

function exportUI.drawIssues()
    if exportUI.getCurrentIssue() == "nodeRefDuplicated" then
        ImGui.OpenPopup("Duplicated NodeRefs")
        if ImGui.BeginPopupModal("Duplicated NodeRefs", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("Duplicated nodeRefs found, please fix them before exporting!")

            ImGui.Separator()

            for _, duplicate in pairs(exportUI.exportIssues.nodeRefDuplicated) do
                style.mutedText("NodeRef:")
                ImGui.SameLine()
                ImGui.Text(duplicate.nodeRef)

                style.mutedText("Node 1: ")
                ImGui.SameLine()
                ImGui.Text(duplicate.name1)

                style.mutedText("Node 2: ")
                ImGui.SameLine()
                ImGui.Text(duplicate.name2)
            end

            ImGui.Separator()

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.nodeRefDuplicated = {}
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "noOutlineMarkers" then
        ImGui.OpenPopup("Missing Outline Markers")
        if ImGui.BeginPopupModal("Missing Outline Markers", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following area nodes have no outline, possibly due to a broken outline group link!")

            ImGui.Separator()

            for _, area in pairs(exportUI.exportIssues.noOutlineMarkers) do
                style.mutedText("Area Name:")
                ImGui.SameLine()
                ImGui.Text(area)

                ImGui.Separator()
            end

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.noOutlineMarkers = {}
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "noSplineMarker" then
        ImGui.OpenPopup("Missing Spline Points")
        if ImGui.BeginPopupModal("Missing Spline Points", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following spline nodes have no points, possibly due to a broken spline group link!")

            ImGui.Separator()

            for _, spline in pairs(exportUI.exportIssues.noSplineMarker) do
                style.mutedText("Spline Name:")
                ImGui.SameLine()
                ImGui.Text(spline)

                ImGui.Separator()
            end

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.noSplineMarker = {}
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "spotEmptyRef" then
        ImGui.OpenPopup("Empty AISpot NodeRef")
        if ImGui.BeginPopupModal("Empty AISpot NodeRef", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following AISpot's do not have a NodeRef assigned to them, making them unusable!")

            ImGui.Separator()

            for _, name in pairs(exportUI.exportIssues.spotEmptyRef) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(name)
            end

            ImGui.Separator()

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.spotEmptyRef = {}
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "spotReferencingEmpty" then
        ImGui.OpenPopup("Community Referencing Missing NodeRef")
        if ImGui.BeginPopupModal("Community Referencing Missing NodeRef", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following Community Entries reference a NodeRef that is not part of this export. (Might still work, if the NodeRef is part of another export)")

            ImGui.Separator()

            for _, entry in pairs(exportUI.exportIssues.spotReferencingEmpty) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(entry.name)

                style.mutedText("Community Entry:")
                ImGui.SameLine()
                ImGui.Text(entry.entry)

                style.mutedText("Entry Phase:")
                ImGui.SameLine()
                ImGui.Text(entry.phase)

                style.mutedText("Phase Period:")
                ImGui.SameLine()
                ImGui.Text(entry.period)

                style.mutedText("Missing spotNodeRef:")
                ImGui.SameLine()
                ImGui.Text(entry.ref)

                ImGui.Separator()
            end

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.spotReferencingEmpty = {}
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "markingUnresolved" then
        ImGui.OpenPopup("Unresolved Marking")
        if ImGui.BeginPopupModal("Unresolved Marking", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following markings have no AISpots associated with them.")

            ImGui.Separator()

            for _, entry in pairs(exportUI.exportIssues.markingUnresolved) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(entry.name)

                style.mutedText("Community Entry:")
                ImGui.SameLine()
                ImGui.Text(entry.entry)

                style.mutedText("Entry Phase:")
                ImGui.SameLine()
                ImGui.Text(entry.phase)

                style.mutedText("Phase Period:")
                ImGui.SameLine()
                ImGui.Text(entry.period)

                style.mutedText("Marking:")
                ImGui.SameLine()
                ImGui.Text(entry.marking)

                ImGui.Separator()
            end

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.markingUnresolved = {}
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "missingInitialPhase" then
        ImGui.OpenPopup("Missing Initial Phase")
        if ImGui.BeginPopupModal("Missing Initial Phase", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following Community Entries reference non-existing phases as their initial phase.")

            ImGui.Separator()

            for _, entry in pairs(exportUI.exportIssues.missingInitialPhase) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(entry.name)

                style.mutedText("Community Entry:")
                ImGui.SameLine()
                ImGui.Text(entry.entry)

                style.mutedText("Missing Phase:")
                ImGui.SameLine()
                ImGui.Text(entry.phase)

                ImGui.Separator()
            end

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.missingInitialPhase = {}
            end
            ImGui.EndPopup()
        end
    end
end

function exportUI.draw()
    exportUI.drawToasts()

    if not exportUI.exporting then
        exportUI.drawIssues()
    end

    if not sectorCategory then
        sectorCategory = utils.enumTable("worldStreamingSectorCategory")
    end

    style.sectionHeaderStart("EXPORT TEMPLATES", "Templates let you save an export setup for later usage, without having to setup what groups/settings to use each time.")

    exportUI.drawTemplates()
    exportUI.handleTemplateDeletePopup()

    style.sectionHeaderEnd()

    style.sectionHeaderStart("PROPERTIES")

    if not exportUI.mainPropertiesWidth then
        exportUI.mainPropertiesWidth = utils.getTextMaxWidth({ "Project Name", "XL Format" }) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    style.pushStyleColor(exportUI.projectName == "" and exportUI.exportHovered, ImGuiCol.Text, 0xFF0000FF)
    ImGui.Text("Project Name")
    style.popStyleColor(exportUI.projectName == "" and exportUI.exportHovered)
    ImGui.SameLine()
    ImGui.SetNextItemWidth(200 * style.viewSize)
    ImGui.SetCursorPosX(exportUI.mainPropertiesWidth)
    exportUI.projectName = ImGui.InputTextWithHint('##name', 'Export name...', exportUI.projectName, 100)
    if exportUI.projectName ~= "" then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close .. "##clearExportProjectName") then
            exportUI.projectName = ""
        end
        style.pushButtonNoBG(false)
    end

    ImGui.Text("XL Format")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(150 * style.viewSize)
    ImGui.SetCursorPosX(exportUI.mainPropertiesWidth)
    exportUI.xlFormat, _ = ImGui.Combo("##xlFormat", exportUI.xlFormat, { "JSON", "YAML" }, 2)
    style.tooltip("Select the format in which the contents of the generated .xl file should be.")

    style.pushGreyedOut(#exportUI.groups == 0 or exportUI.exporting)
    if ImGui.Button("Clear group list") and not exportUI.exporting then
        exportUI.groups = {}
    end
    style.popGreyedOut(#exportUI.groups == 0 or exportUI.exporting)
    style.tooltip("Remove all groups from the current export list")

    style.sectionHeaderEnd()
    style.sectionHeaderStart(string.format("GROUPS (%d)", #exportUI.groups))

    exportUI.drawGroups()

    style.sectionHeaderEnd()
    style.sectionHeaderStart("EXPORT AND SAVE")

    local groupNameCounts = {}
    local duplicateGroupNames = {}
    for _, group in ipairs(exportUI.groups) do
        local name = group.name or ""
        groupNameCounts[name] = (groupNameCounts[name] or 0) + 1
    end
    for name, count in pairs(groupNameCounts) do
        if name ~= "" and count > 1 then
            table.insert(duplicateGroupNames, name)
        end
    end

    if #duplicateGroupNames > 0 then
        table.sort(duplicateGroupNames)
        style.styledText(IconGlyphs.AlertOutline .. " Duplicate group names detected", 0xFF0088FF)
        style.tooltip("Duplicated group names:\n- " .. table.concat(duplicateGroupNames, "\n- "))
        ImGui.Spacing()
    end

    style.pushGreyedOut(#exportUI.groups == 0 or exportUI.projectName == "" or exportUI.exporting)
    local exportLabel = "Export"
    if exportUI.exporting then
        exportLabel = string.format("Exporting... (%d/%d)", exportUI.exportProgressDone, exportUI.exportProgressTotal)
    end
    if ImGui.Button(exportLabel) and #exportUI.groups > 0 and exportUI.projectName ~= "" and not exportUI.exporting then
        exportUI.export()
    end
    style.tooltip("Export the currently selected groups to a .json file, ready for import into WKit")
    exportUI.exportHovered = ImGui.IsItemHovered()

    ImGui.SameLine()
    if ImGui.Button("Save as Template") and #exportUI.groups > 0 and exportUI.projectName ~= "" and not exportUI.exporting then
        local data = {
            projectName = exportUI.projectName,
            xlFormat = exportUI.xlFormat,
            groups = utils.deepcopy(exportUI.groups)
        }
        exportUI.templates[exportUI.projectName] = data
        config.saveFile("data/exportTemplates/" .. exportUI.projectName .. ".json", data)
    end
    style.tooltip("Save the current export setup as a template for later (re)usage")

    style.popGreyedOut(#exportUI.groups == 0 or exportUI.projectName == "" or exportUI.exporting)

    exportUI.drawExportProgress()

    style.sectionHeaderEnd(true)
end

function exportUI.addGroup(name)
    for _, data in pairs(exportUI.groups) do
        if data.name == name then return end
    end

    local data = {
        name = name,
        category = 1,
        level = 1,
        streamingX = 150,
        streamingY = 150,
        streamingZ = 100,
        center = nil,
        prefabRef = "",
        variantRef = "",
        variantData = {}
    }

    table.insert(exportUI.groups, data)
    local blob = loadSavedGroupBlob(name)
    if not blob then return end

    data.variantData = buildVariantDataFromBlob(blob, nil)
    data.center = resolveGroupCenter(blob, nil)
end

---Remove groups from export list by group name
---@param name string
---@return integer
function exportUI.removeGroupByName(name)
    local removed = 0

    for i = #exportUI.groups, 1, -1 do
        if exportUI.groups[i].name == name then
            table.remove(exportUI.groups, i)
            removed = removed + 1
        end
    end

    return removed
end

---Sync group data in export list from saved group file
---Keeps export-specific settings (streaming/category/level/refs) while refreshing center + variants
---@param name string
---@return integer
function exportUI.syncGroup(name)
    local blob = loadSavedGroupBlob(name)
    if not blob then return 0 end

    local updated = 0

    for _, group in ipairs(exportUI.groups) do
        if group.name == name then
            group.variantData = buildVariantDataFromBlob(blob, group.variantData)
            group.center = resolveGroupCenter(blob, group.center)
            updated = updated + 1
        end
    end

    return updated
end

function exportUI.getSpawnableByNodeRef(nodeRefMap, nodeRef)
    if not nodeRef or nodeRef == "" then
        return nil
    end

    return nodeRefMap[nodeRef]
end

function exportUI.handleDevice(object, devices, psEntries, childs, nodeRefMap)
    local hash = utils.nodeRefStringToHashString(object.ref.spawnable.nodeRef)

    local childHashes = {}
    for _, child in pairs(object.ref.spawnable.deviceConnections) do
        table.insert(childHashes, utils.nodeRefStringToHashString(child.nodeRef))

        -- Remember what childs exist, so that we can also add those to the devices file which are entityNodes, not deviceNodes

        local childRef = exportUI.getSpawnableByNodeRef(nodeRefMap, child.nodeRef)
        if childRef and childRef.ref.spawnable.deviceConnections == nil then
            table.insert(childs, {
                className = child.deviceClassName,
                nodePosition = utils.fromVector(childRef ~= nil and childRef.ref:getPosition() or object.ref:getPosition()),
                ref = child.nodeRef,
                parent = hash
            })
        end
    end

    devices[hash] = {
        hash = hash,
        className = object.ref.spawnable.deviceClassName,
        nodePosition = utils.fromVector(object.ref:getPosition()),
        parents = {},
        children = childHashes
    }

    if object.ref.spawnable.persistent and object.ref.spawnable.nodeRef ~= "" then
        local PSID = PersistentID.ForComponent(entEntityID.new({ hash = loadstring("return " .. hash .. "ULL", "")() }), object.ref.spawnable.controllerComponent):ToHash()
        PSID = tostring(PSID):gsub("ULL", "")

        local psData = object.ref.spawnable:getPSData()

        if psData then
            psEntries[PSID] = {
                PSID = PSID,
                instanceData = psData
            }
        end
    end
end

local function buildMarkingRefMap(spotNodes)
    local markingRefMap = {}

    for _, node in pairs(spotNodes) do
        for _, marking in pairs(node.markings or {}) do
            if not markingRefMap[marking] then
                markingRefMap[marking] = {}
            end
            table.insert(markingRefMap[marking], node.ref)
        end
    end

    return markingRefMap
end

local function hasEntryPhase(entry, phase)
    for _, entryPhase in pairs(entry.phases) do
        if entryPhase.phaseName == phase then
            return true
        end
    end

    return false
end

function exportUI.handleCommunities(projectName, communities, spotNodes, nodeRefs)
    local wsPersistentData = {}
    local registryEntries = {}
    local periodEnums = utils.enumTable("communityECommunitySpawnTime")
    local markingRefMap = buildMarkingRefMap(spotNodes)

    -- Collect all spots for workspotsPersistentData
    for _, node in pairs(spotNodes) do
        table.insert(wsPersistentData, {
            ["$type"] = "AISpotPersistentData",
            ["globalNodeId"] = {
                ["$type"] = "worldGlobalNodeID",
                ["hash"] = utils.nodeRefStringToHashString(node.ref)
            },
            ["isEnabled"] = 1,
            ["worldPosition"] = {
                ["$type"] = "WorldPosition",
                ["x"] = {
                    ["$type"] = "FixedPoint",
                    ["Bits"] = math.floor(node.position.x * 131072)
                },
                ["y"] = {
                    ["$type"] = "FixedPoint",
                    ["Bits"] = math.floor(node.position.y * 131072)
                },
                ["z"] = {
                    ["$type"] = "FixedPoint",
                    ["Bits"] = math.floor(node.position.z * 131072)
                }
            },
            ["yaw"] = node.yaw
        })

        if node.ref == "" then
            table.insert(exportUI.exportIssues.spotEmptyRef, node.name)
        end
    end

    -- Generate registry entry, and resolve markings to nodeRefs
    for _, community in pairs(communities) do
        local initialStates = {}
        local entries = {}

        for entryKey, entry in pairs(community.data) do
            table.insert(initialStates, {
                ["$type"] = "worldCommunityEntryInitialState",
                ["entryActiveOnStart"] = entry.entryActiveOnStart and 1 or 0,
                ["entryName"] = {
                    ["$type"] = "CName",
                    ["$storage"] = "string",
                    ["$value"] = entry.entryName
                },
                ["initialPhaseName"] = {
                    ["$type"] = "CName",
                    ["$storage"] = "string",
                    ["$value"] = entry.initialPhaseName
                }
            })

            if not hasEntryPhase(entry, entry.initialPhaseName) then
                table.insert(exportUI.exportIssues.missingInitialPhase, {
                    name = community.node.name,
                    entry = entry.entryName,
                    phase = entry.initialPhaseName
                })
            end

            local phases = {}

            for phaseKey, phase in pairs(entry.phases) do
                local appearances = {}
                for _, appearance in pairs(phase.appearances) do
                    table.insert(appearances, {
                        ["$type"] = "CName",
                        ["$storage"] = "string",
                        ["$value"] = appearance
                    })
                end

                local periods = {}

                for periodKey, period in pairs(phase.timePeriods) do
                    local markings = {}
                    local spotRefs = {}
                    if #period.markings > 0 then
                        for _, marking in pairs(period.markings) do
                            table.insert(markings, {
                                ["$type"] = "CName",
                                ["$storage"] = "string",
                                ["$value"] = marking
                            })

                            -- Update spotRefs on communityAreaNode, resolved from cached marking lookup.
                            local refs = markingRefMap[marking] or {}
                            for _, refValue in pairs(refs) do
                                table.insert(spotRefs, {
                                    ["$type"] = "NodeRef",
                                    ["$storage"] = "string",
                                    ["$value"] = refValue
                                })
                                table.insert(community.node.data.area.Data.entriesData[entryKey].phasesData[phaseKey].timePeriodsData[periodKey].spotNodeIds, {
                                    ["$type"] = "worldGlobalNodeID",
                                    ["hash"] = utils.nodeRefStringToHashString(refValue)
                                })
                            end

                            if #refs == 0 then
                                table.insert(exportUI.exportIssues.markingUnresolved, {
                                    name = community.node.name,
                                    entry = entry.entryName,
                                    phase = phase.phaseName,
                                    period = periodEnums[period.hour + 1],
                                    marking = marking
                                })
                            end
                        end
                    else
                        for _, ref in pairs(period.spotNodeRefs) do
                            table.insert(spotRefs, {
                                ["$type"] = "NodeRef",
                                ["$storage"] = "string",
                                ["$value"] = ref
                            })
                            if not nodeRefs[ref] then
                                table.insert(exportUI.exportIssues.spotReferencingEmpty, {
                                    name = community.node.name,
                                    entry = entry.entryName,
                                    phase = phase.phaseName,
                                    period = periodEnums[period.hour + 1],
                                    ref = ref
                                })
                            end
                        end
                    end

                    table.insert(periods, {
                        ["$type"] = "communityPhaseTimePeriod",
                        ["hour"] = periodEnums[period.hour + 1],
                        ["isSequence"] = period.isSequence and 1 or 0,
                        ["markings"] = markings,
                        ["quantity"] = period.quantity,
                        ["spotNodeRefs"] = spotRefs
                    })
                end

                table.insert(phases, {
                    ["Data"] = {
                        ["$type"] = "communitySpawnPhase",
                        ["appearances"] = appearances,
                        ["phaseName"] = {
                            ["$type"] = "CName",
                            ["$storage"] = "string",
                            ["$value"] = phase.phaseName
                        },
                        ["timePeriods"] = periods
                    }
                  })
            end

            table.insert(entries, {
                ["Data"] = {
                    ["$type"] = "communitySpawnEntry",
                    ["characterRecordId"] = {
                        ["$type"] = "TweakDBID",
                        ["$storage"] = "string",
                        ["$value"] = entry.characterRecordId
                    },
                    ["entryName"] = {
                        ["$type"] = "CName",
                        ["$storage"] = "string",
                        ["$value"] = entry.entryName
                    },
                    ["phases"] = phases,
                }
            })
        end

        table.insert(registryEntries, {
            ["$type"] = "worldCommunityRegistryItem",
            ["communityAreaType"] = "Regular",
            ["communityId"] = {
                ["$type"] = "gameCommunityID",
                ["entityId"] = {
                    ["$type"] = "entEntityID",
                    ["hash"] = utils.nodeRefStringToHashString(community.node.nodeRef)
                }
            },
            ["entriesInitialState"] = initialStates,
            ["template"] = {
                ["Data"] = {
                    ["$type"] = "communityCommunityTemplateData",
                    ["entries"] = entries
                }
            }
        })
    end

    if #wsPersistentData == 0 and #registryEntries == 0 then return end

    return {
        name = projectName .. "_always_loaded",
        min = { x = -99999, y = -99999, z = -99999 },
        max = { x = 99999, y = 99999, z = 99999 },
        category = "AlwaysLoaded",
        level = 1,
        nodes = {
            {
                ["scale"] = {
                    ["x"] = 1,
                    ["y"] = 1,
                    ["z"] = 1
                },
                ["data"] = {
                    ["workspotsPersistentData"] = wsPersistentData,
                    ["communitiesData"] = registryEntries
                },
                ["name"] = "registry",
                ["position"] = {
                    ["x"] = 0,
                    ["y"] = 0,
                    ["w"] = 0,
                    ["z"] = 0
                },
                ["rotation"] = {
                    ["j"] = 0,
                    ["k"] = 0,
                    ["i"] = 0,
                    ["r"] = 0
                },
                ["primaryRange"] = 99999999,
                ["secondaryRange"] = 17.320507,
                ["uk11"] = 512,
                ["type"] = "worldCommunityRegistryNode",
                ["nodeRef"] = "",
                ["uk10"] = 32
            }
        }
    }
end

local function shouldExportNode(node)
    return not settings.ignoreHiddenDuringExport and (not utils.isA(node.parent, "randomizedGroup") or node.visible) or node.visible
end

function exportUI.exportGroup(group)
    if not config.fileExists("data/objects/" .. group.name .. ".json") then return end

    local data = config.loadFile("data/objects/" .. group.name .. ".json")

    local g = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
    g:load(data, true)

    local center = g:getPosition()
    local min = { x = center.x - group.streamingX, y = center.y - group.streamingY, z = center.z - group.streamingZ }
    local max = { x = center.x + group.streamingX, y = center.y + group.streamingY, z = center.z + group.streamingZ }

    local exported = {
        name = utils.createFileName(group.name):lower():gsub(" ", "_"),
        min = min,
        max = max,
        category = sectorCategory[group.category + 1],
        level = group.level,
        nodes = {},
        prefabRef = group.prefabRef,
        variantIndices = { 0 },
        variants = {}
    }

    local devices = {}
    local psEntries = {}
    local childs = {}
    local communities = {}
    local spotNodes = {}

    local variantNodes = {
        default = {}
    }
    local variantInfo = {}
    local nodes = {}
    local rootChildByName = {}

    for _, node in pairs(g.childs) do
        rootChildByName[node.name] = node
    end

    -- Group and bring the nodes in order, based on their variant, starting with default
    for groupName, variant in pairs(group.variantData) do
        if not variantNodes[variant.name] then
            variantNodes[variant.name] = {}
            variantInfo[variant.name] = {
                defaultOn = variant.defaultOn
            }
        end

        local node = rootChildByName[groupName]
        if node then
            for _, entry in pairs(node:getPathsRecursive(false)) do
                if utils.isA(entry.ref, "spawnableElement") and not entry.ref.spawnable.noExport and shouldExportNode(entry.ref) then
                    table.insert(variantNodes[variant.name], entry)
                end
            end
        end
    end

    for _, node in pairs(g.childs) do
        if utils.isA(node, "spawnableElement") and not node.spawnable.noExport and shouldExportNode(node) then
            table.insert(variantNodes["default"], { ref = node })
        end
    end

    nodes = variantNodes["default"]

    local index = 1
    for key, variant in pairs(variantNodes) do
        if key ~= "default" then
            table.insert(exported.variantIndices, #nodes)
            utils.combine(nodes, variant)

            table.insert(exported.variants, {
                name = key,
                index = index,
                defaultOn = variantInfo[key].defaultOn and 1 or 0,
                ref = group.variantRef
            })

            index = index + 1
        end
    end

    local nodeRefMap = {}
    for _, object in ipairs(nodes) do
        if utils.isA(object.ref, "spawnableElement") and object.ref.spawnable and object.ref.spawnable.nodeRef and object.ref.spawnable.nodeRef ~= "" then
            nodeRefMap[object.ref.spawnable.nodeRef] = object
        end
    end

    local nodeCount = #nodes
    for key, object in ipairs(nodes) do
        if utils.isA(object.ref, "spawnableElement") and not object.ref.spawnable.noExport and shouldExportNode(object.ref) then
            table.insert(exported.nodes, object.ref.spawnable:export(key, nodeCount))

            -- Handle device nodes
            if object.ref.spawnable.node == "worldDeviceNode" then
                exportUI.handleDevice(object, devices, psEntries, childs, nodeRefMap)
            elseif object.ref.spawnable.node == "worldCompiledCommunityAreaNode_Streamable" then
                table.insert(communities, { data = object.ref.spawnable.entries, node = exported.nodes[#exported.nodes] })
            elseif object.ref.spawnable.node == "worldAISpotNode" then
                table.insert(spotNodes, {
                    ref = object.ref.spawnable.nodeRef,
                    position = utils.fromVector(object.ref:getPosition()),
                    yaw = object.ref.spawnable.rotation.yaw,
                    markings = object.ref.spawnable.markings,
                    name = object.ref.name
                })
            end
        end
    end

    return exported, devices, psEntries, childs, communities, spotNodes
end

local function collectDuplicateNodeRefs(nodeRefs, nodes)
    for _, node in ipairs(nodes or {}) do
        if not nodeRefs[node.nodeRef] then
            nodeRefs[node.nodeRef] = node.name
        elseif node.nodeRef ~= "" then
            table.insert(exportUI.exportIssues.nodeRefDuplicated, {
                nodeRef = node.nodeRef,
                name1 = nodeRefs[node.nodeRef],
                name2 = node.name
            })
            break
        end
    end
end

local function mergeGroupExportData(project, state, data, devices, psEntries, subChilds, comms, spots)
    table.insert(project.sectors, data)

    for hash, device in pairs(devices) do
        project.devices[hash] = device
    end

    for PSID, entry in pairs(psEntries) do
        project.psEntries[PSID] = entry
    end

    utils.combine(state.communities, comms)
    utils.combine(state.spotNodes, spots)
    utils.combine(state.childs, subChilds)

    collectDuplicateNodeRefs(state.nodeRefs, data.nodes)
end

local function finalizeDeviceParents(project, childs)
    for hash, device in pairs(project.devices) do
        for _, childHash in pairs(device.children) do
            if project.devices[childHash] then
                table.insert(project.devices[childHash].parents, hash)
            end
        end
    end

    -- TODO: Aggregate all parents of double entries, so a device that isnt a device can be linked to multiple parents
    local additionalEntries = {}
    for _, child in pairs(childs) do
        local hash = utils.nodeRefStringToHashString(child.ref)
        if not additionalEntries[hash] then
            additionalEntries[hash] = {
                hash = hash,
                className = child.className,
                nodePosition = child.nodePosition,
                parents = { child.parent },
                children = {}
            }
        else
            table.insert(additionalEntries[hash].parents, child.parent)
        end
    end

    for _, child in pairs(additionalEntries) do
        project.devices[child.hash] = child
    end
end

local function getTopRootChild(root, element)
    if not root or not element then
        return nil
    end

    local current = element
    while current and current.parent and current.parent ~= root do
        current = current.parent
    end

    if current and current.parent == root then
        return current
    end

    return nil
end

local function prepareCurrentGroupForExport(runtime)
    local current = runtime.current
    if not current or not current.root then
        return
    end

    local group = current.group
    local root = current.root
    local center = root:getPosition()

    current.exported = {
        name = utils.createFileName(group.name):lower():gsub(" ", "_"),
        min = {
            x = center.x - group.streamingX,
            y = center.y - group.streamingY,
            z = center.z - group.streamingZ
        },
        max = {
            x = center.x + group.streamingX,
            y = center.y + group.streamingY,
            z = center.z + group.streamingZ
        },
        category = sectorCategory[group.category + 1],
        level = group.level,
        nodes = {},
        prefabRef = group.prefabRef,
        variantIndices = { 0 },
        variants = {}
    }

    current.devices = {}
    current.psEntries = {}
    current.childs = {}
    current.communities = {}
    current.spotNodes = {}

    local variantNodes = {
        default = {}
    }
    local variantInfo = {}
    local variantOrder = {}
    local variantSeen = {}

    for _, variant in pairs(group.variantData or {}) do
        local variantName = variant.name or "default"
        if not variantNodes[variantName] then
            variantNodes[variantName] = {}
        end
        if not variantInfo[variantName] then
            variantInfo[variantName] = {
                defaultOn = variant.defaultOn
            }
        end
        if variantName ~= "default" and not variantSeen[variantName] then
            variantSeen[variantName] = true
            table.insert(variantOrder, variantName)
        end
    end

    for _, node in ipairs(current.spawnables) do
        if utils.isA(node, "spawnableElement") and not node.spawnable.noExport and shouldExportNode(node) then
            if node.parent == root then
                table.insert(variantNodes.default, { ref = node })
            else
                local top = getTopRootChild(root, node)
                local variant = top and group.variantData and group.variantData[top.name]
                if variant then
                    local variantName = variant.name or "default"
                    if not variantNodes[variantName] then
                        variantNodes[variantName] = {}
                    end
                    table.insert(variantNodes[variantName], { ref = node })
                end
            end
        end
    end

    current.nodes = variantNodes.default

    local index = 1
    for _, variantName in ipairs(variantOrder) do
        local variantList = variantNodes[variantName] or {}
        table.insert(current.exported.variantIndices, #current.nodes)
        utils.combine(current.nodes, variantList)

        table.insert(current.exported.variants, {
            name = variantName,
            index = index,
            defaultOn = variantInfo[variantName] and variantInfo[variantName].defaultOn and 1 or 0,
            ref = group.variantRef
        })
        index = index + 1
    end

    current.nodeRefMap = {}
    for _, object in ipairs(current.nodes) do
        if utils.isA(object.ref, "spawnableElement") and object.ref.spawnable and object.ref.spawnable.nodeRef and object.ref.spawnable.nodeRef ~= "" then
            current.nodeRefMap[object.ref.spawnable.nodeRef] = object
        end
    end

    current.totalNodes = #current.nodes
    current.nodeIndex = 1
end

clearCurrentGroup = function (runtime)
    if not runtime then
        return
    end

    if runtime.current then
        runtime.current.root = nil
        runtime.current.nodes = nil
        runtime.current.nodeRefMap = nil
        runtime.current.spawnables = nil
        runtime.current.buildQueue = nil
        runtime.current = nil
    end
end

local function finalizeExportRuntime(runtime)
    runtime.phase = "finalize"
    haltRuntimeTimer(runtime)
    clearCurrentGroup(runtime)

    local function completeFinalize()
        if exportUI.exportRuntime ~= runtime then
            return
        end

        exportUI.exportRuntime = createExportRuntime(runtime)
        syncExportProgress(exportUI.exportRuntime)
    end

    -- Safety net: ensure UI does not stay stuck in finalize state if anything below errors unexpectedly.
    Cron.NextTick(function ()
        if exportUI.exportRuntime == runtime and runtime.phase == "finalize" then
            completeFinalize()
        end
    end)

    local ok, err = pcall(function ()
        finalizeDeviceParents(runtime.project, runtime.state.childs)

        local always_loaded = exportUI.handleCommunities(runtime.project.name, runtime.state.communities, runtime.state.spotNodes, runtime.state.nodeRefs)
        if always_loaded then
            table.insert(runtime.project.sectors, always_loaded)
        end

        local saved, saveErr = config.saveFile("export/" .. runtime.project.name .. "_exported.json", runtime.project)
        if saved then
            queueToast("success", 2500, string.format("Exported \"%s\"", exportUI.projectName))
            print("[entSpawner] Exported project " .. runtime.project.name)
        else
            local message = string.format("Export failed: %s", tostring(saveErr or "unknown_error"))
            queueToast("warning", 3500, message)
            print("[entSpawner] " .. message)
        end
    end)

    if not ok then
        local message = string.format("Export failed: %s", tostring(err))
        queueToast("warning", 3500, message)
        print("[entSpawner] " .. message)
    end

    completeFinalize()
end

local function beginNextGroup(runtime)
    if not runtime.active then
        return
    end

    if runtime.groupIndex > runtime.totalGroups then
        finalizeExportRuntime(runtime)
        return
    end

    local group = runtime.groups[runtime.groupIndex]
    if not group then
        runtime.groupIndex = runtime.groupIndex + 1
        runtime.completedGroups = runtime.completedGroups + 1
        syncExportProgress(runtime)
        Cron.NextTick(function ()
            if exportUI.exportRuntime == runtime then
                beginNextGroup(runtime)
            end
        end)
        return
    end

    local path = "data/objects/" .. group.name .. ".json"
    if not config.fileExists(path) then
        runtime.groupIndex = runtime.groupIndex + 1
        runtime.completedGroups = runtime.completedGroups + 1
        syncExportProgress(runtime)
        Cron.NextTick(function ()
            if exportUI.exportRuntime == runtime then
                beginNextGroup(runtime)
            end
        end)
        return
    end

    local blob = config.loadFile(path)
    runtime.current = {
        group = group,
        name = group.name,
        buildQueue = {},
        buildHead = 1,
        buildTail = 0,
        buildTotal = 0,
        buildProcessed = 0,
        spawnables = {}
    }

    local ok, err = pcall(function ()
        local root = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
        root:load(copyNodeDataWithoutChildren(blob), true)
        runtime.current.root = root

        for _, child in pairs(blob.childs or {}) do
            queueBuildEntry(runtime.current, child, root)
        end
    end)

    if not ok then
        print(string.format("[entSpawner] Export failed while preparing group \"%s\": %s", tostring(group.name), tostring(err)))
        clearCurrentGroup(runtime)
        runtime.groupIndex = runtime.groupIndex + 1
        runtime.completedGroups = runtime.completedGroups + 1
        syncExportProgress(runtime)
        Cron.NextTick(function ()
            if exportUI.exportRuntime == runtime then
                beginNextGroup(runtime)
            end
        end)
        return
    end

    runtime.phase = "build"
    runtime.timer = Cron.OnUpdate(function (timer)
        local currentRuntime = exportUI.exportRuntime
        if currentRuntime ~= runtime or not runtime.active or runtime.phase ~= "build" or not runtime.current then
            timer:Halt()
            return
        end

        local current = runtime.current
        local processed = 0
        local startedAt = nowMs()
        local maxPerTick = math.max(1, runtime.buildChunkSize or 1)
        local budgetMs = math.max(0.1, runtime.buildTimeBudgetMs or 1)

        while processed < maxPerTick and current.buildHead <= current.buildTail do
            local entry = current.buildQueue[current.buildHead]
            current.buildQueue[current.buildHead] = nil
            current.buildHead = current.buildHead + 1

            local okBuild, buildErr = pcall(function ()
                local modulePath = entry.data.modulePath or entry.parent:getModulePathByType(entry.data)
                local new = require(modulePath):new(exportUI.spawner.baseUI.spawnedUI)
                new:load(copyNodeDataWithoutChildren(entry.data), true)
                addChildFast(entry.parent, new)

                if utils.isA(new, "spawnableElement") then
                    table.insert(current.spawnables, new)
                end

                for _, child in pairs(entry.data.childs or {}) do
                    queueBuildEntry(current, child, new)
                end
            end)

            current.buildProcessed = current.buildProcessed + 1
            if not okBuild then
                print(string.format("[entSpawner] Export build failed for \"%s\": %s", tostring(entry.data and entry.data.name), tostring(buildErr)))
                for _, child in pairs(entry.data.childs or {}) do
                    queueBuildEntry(current, child, entry.parent)
                end
            end

            processed = processed + 1
            if (nowMs() - startedAt) >= budgetMs then
                break
            end
        end

        if current.buildHead > current.buildTail then
            timer:Halt()
            runtime.timer = nil

            local okPrepare, prepareErr = pcall(function ()
                prepareCurrentGroupForExport(runtime)
            end)
            if not okPrepare then
                print(string.format("[entSpawner] Export prepare failed for \"%s\": %s", tostring(current.name), tostring(prepareErr)))
                clearCurrentGroup(runtime)
                runtime.groupIndex = runtime.groupIndex + 1
                runtime.completedGroups = runtime.completedGroups + 1
                syncExportProgress(runtime)
                Cron.NextTick(function ()
                    if exportUI.exportRuntime == runtime then
                        beginNextGroup(runtime)
                    end
                end)
                return
            end

            runtime.phase = "export"

            if (runtime.current.totalNodes or 0) == 0 then
                mergeGroupExportData(runtime.project, runtime.state, runtime.current.exported, runtime.current.devices, runtime.current.psEntries, runtime.current.childs, runtime.current.communities, runtime.current.spotNodes)
                clearCurrentGroup(runtime)
                runtime.groupIndex = runtime.groupIndex + 1
                runtime.completedGroups = runtime.completedGroups + 1
                syncExportProgress(runtime)
                Cron.NextTick(function ()
                    if exportUI.exportRuntime == runtime then
                        beginNextGroup(runtime)
                    end
                end)
                return
            end

            runtime.timer = Cron.OnUpdate(function (exportTimer)
                local exportRuntime = exportUI.exportRuntime
                if exportRuntime ~= runtime or not runtime.active or runtime.phase ~= "export" or not runtime.current then
                    exportTimer:Halt()
                    return
                end

                local exportCurrent = runtime.current
                local exportProcessed = 0
                local exportStartedAt = nowMs()
                local exportMaxPerTick = math.max(1, runtime.exportChunkSize or 1)
                local exportBudgetMs = math.max(0.1, runtime.exportTimeBudgetMs or 1)

                while exportProcessed < exportMaxPerTick and exportCurrent.nodeIndex <= exportCurrent.totalNodes do
                    local key = exportCurrent.nodeIndex
                    local object = exportCurrent.nodes[key]

                    if object and utils.isA(object.ref, "spawnableElement") and not object.ref.spawnable.noExport and shouldExportNode(object.ref) then
                        table.insert(exportCurrent.exported.nodes, object.ref.spawnable:export(key, exportCurrent.totalNodes))

                        if object.ref.spawnable.node == "worldDeviceNode" then
                            exportUI.handleDevice(object, exportCurrent.devices, exportCurrent.psEntries, exportCurrent.childs, exportCurrent.nodeRefMap)
                        elseif object.ref.spawnable.node == "worldCompiledCommunityAreaNode_Streamable" then
                            table.insert(exportCurrent.communities, { data = object.ref.spawnable.entries, node = exportCurrent.exported.nodes[#exportCurrent.exported.nodes] })
                        elseif object.ref.spawnable.node == "worldAISpotNode" then
                            table.insert(exportCurrent.spotNodes, {
                                ref = object.ref.spawnable.nodeRef,
                                position = utils.fromVector(object.ref:getPosition()),
                                yaw = object.ref.spawnable.rotation.yaw,
                                markings = object.ref.spawnable.markings,
                                name = object.ref.name
                            })
                        end
                    end

                    exportCurrent.nodeIndex = exportCurrent.nodeIndex + 1
                    exportProcessed = exportProcessed + 1

                    if (nowMs() - exportStartedAt) >= exportBudgetMs then
                        break
                    end
                end

                if exportCurrent.nodeIndex > exportCurrent.totalNodes then
                    exportTimer:Halt()
                    runtime.timer = nil

                    mergeGroupExportData(runtime.project, runtime.state, exportCurrent.exported, exportCurrent.devices, exportCurrent.psEntries, exportCurrent.childs, exportCurrent.communities, exportCurrent.spotNodes)
                    clearCurrentGroup(runtime)
                    runtime.groupIndex = runtime.groupIndex + 1
                    runtime.completedGroups = runtime.completedGroups + 1
                    syncExportProgress(runtime)

                    Cron.NextTick(function ()
                        if exportUI.exportRuntime == runtime then
                            beginNextGroup(runtime)
                        end
                    end)
                end
            end)
        end
    end)
end

function exportUI.export()
    if exportUI.exporting then
        return
    end

    exportUI.resetIssues()

    if not exportUI.exportRuntime then
        exportUI.exportRuntime = createExportRuntime()
    end

    local runtime = createExportRuntime(exportUI.exportRuntime)
    runtime.active = true
    runtime.phase = "build"
    runtime.groups = {}
    runtime.totalGroups = #exportUI.groups
    runtime.groupIndex = 1
    runtime.completedGroups = 0
    runtime.project = {
        name = utils.createFileName(exportUI.projectName):lower():gsub(" ", "_"),
        xlFormat = exportUI.xlFormat,
        sectors = {},
        devices = {},
        psEntries = {},
        version = minScriptVersion
    }
    runtime.state = {
        nodeRefs = {},
        spotNodes = {},
        communities = {},
        childs = {}
    }

    for _, group in ipairs(exportUI.groups) do
        table.insert(runtime.groups, {
            name = group.name,
            category = group.category,
            level = group.level,
            streamingX = group.streamingX,
            streamingY = group.streamingY,
            streamingZ = group.streamingZ,
            prefabRef = group.prefabRef,
            variantRef = group.variantRef,
            variantData = utils.deepcopy(group.variantData or {})
        })
    end

    exportUI.exportRuntime = runtime
    syncExportProgress(runtime)

    if runtime.totalGroups == 0 then
        exportUI.exportRuntime = createExportRuntime(runtime)
        syncExportProgress(exportUI.exportRuntime)
        return
    end

    Cron.NextTick(function ()
        if exportUI.exportRuntime == runtime and runtime.active then
            beginNextGroup(runtime)
        end
    end)
end

return exportUI
