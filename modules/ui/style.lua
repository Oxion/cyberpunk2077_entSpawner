-- Most of the colors and style has been taken from https://github.com/psiberx/cp2077-red-hot-tools

local history = require("modules/utils/history")
local settings = require("modules/utils/settings")
local utils = require("modules/utils/utils")
local dragBeingEdited = false
local maxLightChannelsWidth = nil

local style = {
    mutedColor = 0xFFA5A19B,
    extraMutedColor = 0x96A5A19B,
    highlightColor = 0xFFDCD8D1,
    activeColor = 0xFFFEB500,
    activeTextColor = 0xFF000000,
    elementIndent = 35,
    draggedColor = 0xFF00007F,
    targetedColor = 0xFF00007F,
    regularColor = 0xFFFFFFFF
}

local initialized = false

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(value, maxValue))
end

local function getDisplaySize()
    local width, height = GetDisplayResolution()
    return width, height
end

local function setNextWindowPosClamped(x, y, width, height, cond)
    local screenWidth, screenHeight = getDisplaySize()
    local margin = 8

    local maxX = math.max(margin, screenWidth - width - margin)
    local maxY = math.max(margin, screenHeight - height - margin)

    ImGui.SetNextWindowPos(clamp(x, margin, maxX), clamp(y, margin, maxY), cond or ImGuiCond.Always)
end

local function getTooltipSize(text)
    local textWidth, textHeight = ImGui.CalcTextSize(text or "")
    local padding = ImGui.GetStyle().WindowPadding

    return textWidth + (padding.x * 2), textHeight + (padding.y * 2)
end

local function placeTooltipNearCursor(text, offsetX, offsetY, cond)
    local scale = style.viewSize or 1
    local mouseX, mouseY = ImGui.GetMousePos()
    local tooltipWidth, tooltipHeight = getTooltipSize(text)

    setNextWindowPosClamped(mouseX + offsetX * scale, mouseY + offsetY * scale, tooltipWidth, tooltipHeight, cond)
end

function style.initialize(force)
    if not force and initialized then return end
    style.viewSize = ImGui.GetFontSize() / 15
    initialized = true

    local _, height = GetDisplayResolution()
    local factor = height / 1440

    style.draggingThreshold = settings.draggingThreshold * factor
end

function style.pushGreyedOut(state)
    if not state then return end

    ImGui.PushStyleColor(ImGuiCol.Button, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0xff777777)

    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 0xff777777)
end

function style.popGreyedOut(state)
    if not state then return end

    ImGui.PopStyleColor(6)
end

function style.pushStyleColor(state, style, ...)
    if not state then return end

    ImGui.PushStyleColor(style, ...)
end

function style.pushStyleVar(state, style, ...)
    if not state then return end

    ImGui.PushStyleVar(style, ...)
end

---@param state boolean
---@param count number?
function style.popStyleVar(state, count)
    if not state then return end

    ImGui.PopStyleVar(count or 1)
end

---@param state boolean
---@param count number?
function style.popStyleColor(state, count)
    if not state then return end

    ImGui.PopStyleColor(count or 1)
end

function style.tooltip(text)
    if ImGui.IsItemHovered() then
        placeTooltipNearCursor(text, 8, 8, ImGuiCond.Always)
        ImGui.BeginTooltip()
        ImGui.PushStyleColor(ImGuiCol.Text, 0xFFFFFFFF)
        ImGui.Text(text)
        ImGui.PopStyleColor()
        ImGui.EndTooltip()
    end
end

function style.setCursorRelative(x, y)
    local xC, yC = ImGui.GetMousePos()
    setNextWindowPosClamped(xC + x * style.viewSize, yC + y * style.viewSize, 1, 1, ImGuiCond.Always)
end

function style.setCursorRelativeAppearing(x, y)
    local xC, yC = ImGui.GetMousePos()
    setNextWindowPosClamped(xC + x * style.viewSize, yC + y * style.viewSize, 1, 1, ImGuiCond.Appearing)
end

function style.spawnableInfo(info)
    if ImGui.IsItemHovered() then

        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 20)

        style.mutedText("Node: ")
        ImGui.Text(info.node)
        ImGui.Spacing()
        style.mutedText("Description: ")
        ImGui.Text(info.description)
        ImGui.Spacing()
        style.mutedText("Preview Note: ")
        ImGui.Text(info.previewNote)

        ImGui.EndTooltip()
    end
end

function style.spacedSeparator()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

---@param text string
---@param tooltip string?
function style.sectionHeaderStart(text, tooltip)
    local useDefaultFontSize = text:match("%l") ~= nil

    ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
    if not useDefaultFontSize then
        ImGui.SetWindowFontScale(0.85)
    end
    ImGui.Text(text)

    if tooltip then
        style.tooltip(tooltip)
    end

    if not useDefaultFontSize then
        ImGui.SetWindowFontScale(1)
    end
    ImGui.PopStyleColor()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.BeginGroup()
    ImGui.AlignTextToFramePadding()
end

function style.sectionHeaderEnd(noSpacing)
    ImGui.EndGroup()

    if not noSpacing then
        ImGui.Spacing()
        ImGui.Spacing()
    end
end

function style.mutedText(text)
    style.styledText(text, style.mutedColor)
end

---@param text string
---@param color number|table?
---@param size number?
function style.styledText(text, color, size)
    style.pushStyleColor(color ~= nil, ImGuiCol.Text, color)
    ImGui.SetWindowFontScale(size or 1)

    ImGui.Text(text)

    style.popStyleColor(color ~= nil)
    ImGui.SetWindowFontScale(1)
end

function style.pushButtonNoBG(push)
    if push then
        ImGui.PushStyleColor(ImGuiCol.Button, 0)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1, 1, 1, 0.2)
        ImGui.PushStyleVar(ImGuiStyleVar.ButtonTextAlign, 0.5, 0.5)
    else
        ImGui.PopStyleColor(2)
        ImGui.PopStyleVar()
    end
end

function style.dangerButton(text, ...)
    ImGui.PushStyleColor(ImGuiCol.Button, 0.65, 0.15, 0.15, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.80, 0.20, 0.20, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.55, 0.10, 0.10, 1.0)
    local clicked = ImGui.Button(text, ...)
    ImGui.PopStyleColor(3)
    return clicked
end

function style.warnButton(text, ...)
    ImGui.PushStyleColor(ImGuiCol.Button, 1.0, 0.6, 0.0, 0.8)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1.0, 0.6, 0.0, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 1.0, 0.6, 0.0, 0.6)
    local clicked = ImGui.Button(text, ...)
    ImGui.PopStyleColor(3)
    return clicked
end

function style.toggleButton(text, state)
    local clicked

    if state then
        -- toggled on state
        ImGui.PushStyleColor(ImGuiCol.Button, 0.0, 1.0, 0.7, 0.8)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.0, 1.0, 0.7, 1.0)
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.0, 1.0, 0.7, 0.6)
        ImGui.PushStyleColor(ImGuiCol.Text, style.activeTextColor)
        clicked = ImGui.Button(text)
        ImGui.PopStyleColor(4)
    else
        -- toggled off state
        ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
        style.pushButtonNoBG(true)
        clicked = ImGui.Button(text)
        style.pushButtonNoBG(false)
        ImGui.PopStyleColor()
    end

    if clicked then
        return not state, true
    end

    return state, false
end

function style.setNextItemWidth(width)
    ImGui.SetNextItemWidth(width * style.viewSize)
end

function style.trackedCheckbox(element, text, state, disabled)
    ImGui.BeginDisabled(disabled == true)
    local newState, changed = ImGui.Checkbox(text, state)
    ImGui.EndDisabled()
    if changed then
        history.addAction(history.getElementChange(element))
    end
    return newState, changed
end

function style.trackedDragFloat(element, text, value, step, min, max, format, width)
    width = width or 80
    ImGui.SetNextItemWidth(width * style.viewSize)
    local newValue, changed = ImGui.DragFloat(text, value, step, min, max, format)

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		dragBeingEdited = false
	end
	if changed and element and not dragBeingEdited then
		history.addAction(history.getElementChange(element))
		dragBeingEdited = true
	end

    newValue = math.max(newValue, min)
    newValue = math.min(newValue, max)

    return newValue, changed, finished
end

function style.trackedDragInt(element, text, value, min, max, width)
    width = width or 80
    ImGui.SetNextItemWidth(width * style.viewSize)
    local newValue, changed = ImGui.DragFloat(text, value, 1, min, max, "%.0f")

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		dragBeingEdited = false
	end
	if changed and not dragBeingEdited then
		history.addAction(history.getElementChange(element))
		dragBeingEdited = true
	end

    newValue = math.floor(newValue)
    newValue = math.max(newValue, min)
    newValue = math.min(newValue, max)

    return newValue, changed, finished
end

function style.trackedIntInput(element, text, value, min, max, width)
    width = width or 80
    ImGui.SetNextItemWidth(width * style.viewSize)
    local newValue, changed = ImGui.InputInt(text, value, min, max)

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		dragBeingEdited = false
	end
	if changed and not dragBeingEdited then
		history.addAction(history.getElementChange(element))
		dragBeingEdited = true
	end

    newValue = math.max(newValue, min)
    newValue = math.min(newValue, max)

    return newValue, changed, finished
end

function style.trackedCombo(element, text, selected, options, width)
    width = width or 100
    ImGui.SetNextItemWidth(width * style.viewSize)

    local newValue, changed = ImGui.Combo(text, selected, options, #options)

    if changed then
        history.addAction(history.getElementChange(element))
    end
    return newValue, changed
end

function style.trackedColor(element, name, color, width)
    width = width or 80
    width = width * 3 + 2 * ImGui.GetStyle().ItemSpacing.x
    ImGui.SetNextItemWidth(width * style.viewSize)

    local newValue, changed = ImGui.ColorEdit3(name, color)

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		dragBeingEdited = false
	end
	if changed and element and not dragBeingEdited then
		history.addAction(history.getElementChange(element))
		dragBeingEdited = true
	end

    return newValue, changed, finished
end

function style.trackedTextField(element, text, value, hint, width)
    if width == -1 then
        width = (ImGui.GetWindowContentRegionWidth() - ImGui.GetCursorPosX()) / style.viewSize
        width = math.max(width, 140)
    end

    width = width or 80
    ImGui.SetNextItemWidth(width * style.viewSize)
    local newValue, changed = ImGui.InputTextWithHint(text, hint, value, 500)

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
        newValue = string.gsub(newValue, "[\128-\255]", "")
		dragBeingEdited = false
	end
	if changed and element and not dragBeingEdited then
		history.addAction(history.getElementChange(element))
		dragBeingEdited = true
	end

    return newValue, changed, finished
end

function style.getMaxWidth(min)
    local width = (ImGui.GetWindowContentRegionWidth() - ImGui.GetCursorPosX())
    width = math.max(width, min)

    return width / style.viewSize
end

---Searchable dropdown where search text follows selected value.
---Use this for legacy behavior where typing in the search field is part of element history tracking.
---@param element element
---@param text string
---@param searchHint string
---@param value string
---@param options table
---@param width number?
---@return string value
---@return boolean finished
function style.trackedSearchDropdown(element, text, searchHint, value, options, width)
    value = value or ""
    options = options or {}
    width = width or 100

    local finished = false
    local searchValue = value

    ImGui.SetNextItemWidth(width * style.viewSize)
    if (ImGui.BeginCombo(text, value)) then
        local interiorWidth = width - (2 * ImGui.GetStyle().FramePadding.x) - 30
        searchValue, _, _ = style.trackedTextField(element, "##search", searchValue, searchHint, interiorWidth)
        local x, _ = ImGui.GetItemRectSize()

        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            history.addAction(history.getElementChange(element))
            value = ""
            searchValue = ""
            finished = true
        end
        style.pushButtonNoBG(false)

        local xButton, _ = ImGui.GetItemRectSize()
        if ImGui.BeginChild("##list", x + xButton + ImGui.GetStyle().ItemSpacing.x, 120 * style.viewSize) then
            for _, option in pairs(options) do
                local optionText = tostring(option)
                if optionText:lower():match(searchValue:lower()) and ImGui.Selectable(optionText) then
                    history.addAction(history.getElementChange(element))
                    value = optionText
                    finished = true
                    ImGui.CloseCurrentPopup()
                end
            end

            ImGui.EndChild()
        end

        ImGui.EndCombo()
    end

    return value, finished
end

---Searchable dropdown with decoupled search text state.
---Use this when selected value and typed filter must be independent.
---@param element element
---@param text string
---@param searchHint string
---@param value string
---@param searchValue string
---@param options table
---@param width number?
---@return string value
---@return string searchValue
---@return boolean finished
function style.trackedSearchDropdownWithSearch(element, text, searchHint, value, searchValue, options, width)
    value = value or ""
    searchValue = searchValue or ""
    options = options or {}
    width = width or 100

    local finished = false

    ImGui.SetNextItemWidth(width * style.viewSize)
    if (ImGui.BeginCombo(text, value)) then
        local interiorWidth = width - (2 * ImGui.GetStyle().FramePadding.x) - 30
        searchValue, _, _ = style.trackedTextField(nil, "##search", searchValue, searchHint, interiorWidth)
        local x, _ = ImGui.GetItemRectSize()

        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            searchValue = ""
        end
        style.pushButtonNoBG(false)

        local xButton, _ = ImGui.GetItemRectSize()
        if ImGui.BeginChild("##list", x + xButton + ImGui.GetStyle().ItemSpacing.x, 120 * style.viewSize) then
            for _, option in pairs(options) do
                local optionText = tostring(option)
                if optionText:lower():match(searchValue:lower()) and ImGui.Selectable(optionText) then
                    history.addAction(history.getElementChange(element))
                    value = optionText
                    finished = true
                    ImGui.CloseCurrentPopup()
                end
            end

            ImGui.EndChild()
        end

        ImGui.EndCombo()
    end

    return value, searchValue, finished
end

function style.drawNoBGConditionalButton(condition, text, greyed)
    local push = false
    local greyed = greyed ~= nil and greyed or false

    if condition then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        style.pushGreyedOut(greyed)
        if ImGui.Button(text) then
            push = true
        end
        style.popGreyedOut(greyed)
        style.pushButtonNoBG(false)
    end

    return push
end

style.lightChannelEnum = {
    "LC_Channel1",
    "LC_Channel2",
    "LC_Channel3",
    "LC_Channel4",
    "LC_Channel5",
    "LC_Channel6",
    "LC_Channel7",
    "LC_Channel8",
    "LC_ChannelWorld",
    "LC_Character",
    "LC_Player",
    "LC_Automated"
}

function style.drawLightChannelsSelector(object, lightChannels)
    if not maxLightChannelsWidth then
        maxLightChannelsWidth = utils.getTextMaxWidth(style.lightChannelEnum) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.PlusBoxMultipleOutline) then
        if object then history.addAction(history.getElementChange(object)) end
        for i = 1, #lightChannels do
            lightChannels[i] = true
        end
    end
    style.tooltip("Select all light channels")
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.MinusBoxMultipleOutline) then
        if object then history.addAction(history.getElementChange(object)) end
        for i = 1, #lightChannels do
            lightChannels[i] = false
        end
    end
    style.tooltip("Deselect all light channels")
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.ContentCopy) then
        utils.insertClipboardValue("lightChannels", utils.deepcopy(lightChannels))
        ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, "Copied light channels to the clipboard"))
    end
    style.tooltip("Copy light channels to clipboard")

    ImGui.SameLine()
    local channels = utils.getClipboardValue("lightChannels")
    style.pushGreyedOut(channels == nil)
    if ImGui.Button(IconGlyphs.ContentPaste) and channels ~= nil then
        if object then history.addAction(history.getElementChange(object)) end
        lightChannels = utils.deepcopy(channels)
    end
    style.tooltip("Paste light channels from clipboard")
    style.popGreyedOut(channels == nil)
    style.pushButtonNoBG(false)

    for key, channel in ipairs(style.lightChannelEnum) do
        style.mutedText(channel)
        ImGui.SameLine()
        ImGui.SetCursorPosX(maxLightChannelsWidth)

        if object then
            lightChannels[key], _ = style.trackedCheckbox(object, "##lightChannel" .. key, lightChannels[key])
        else
            lightChannels[key], _ = ImGui.Checkbox("##lightChannel" .. key, lightChannels[key])
        end
    end

    return lightChannels
end

return style

