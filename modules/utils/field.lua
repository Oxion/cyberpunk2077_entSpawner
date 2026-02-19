local history = require("modules/utils/history")
local settings = require("modules/utils/settings")
local style = require("modules/ui/style")

local field = {}
local dragBeingEdited = false

local function wrapValue(value, min, max)
    local range = max - min
    if range <= 0 then
        return value
    end

    local wrapped = (value - min) % range
    if wrapped < 0 then
        wrapped = wrapped + range
    end

    return min + wrapped
end

---Advanced tracked DragFloat with optional prefix/suffix, precision modifiers and looping.
---@param element table
---@param text string
---@param value number
---@param options table?
---@return number, boolean, boolean
function field.advancedTrackedFloat(element, text, value, options)
    options = options or {}

    local step = options.step or 0.01
    local min = options.min or -99999
    local max = options.max or 99999
    local format = options.format or "%.2f"
    local shiftFormat = options.shiftFormat or "%.3f"
    local width = options.width or 74
    local prefix = options.prefix or ""
    local suffix = options.suffix or ""
    local loop = options.loop == true

    local dragStep = step
    local shiftDown = ImGui.IsKeyDown(ImGuiKey.LeftShift) or ImGui.IsKeyDown(ImGuiKey.RightShift)
    local ctrlDown = ImGui.IsKeyDown(ImGuiKey.LeftCtrl) or ImGui.IsKeyDown(ImGuiKey.RightCtrl)

    if shiftDown then
        dragStep = dragStep * 0.1 * settings.precisionMultiplier
    elseif ctrlDown then
        dragStep = dragStep * settings.coarsePrecisionMultiplier
    end

    ImGui.SetNextItemWidth(width * (style.viewSize or 1))
    local activeFormat = shiftDown and shiftFormat or format
    local displayFormat = prefix .. activeFormat .. suffix

    -- For looping fields, avoid DragFloat clamp so value can cross bounds both ways.
    local dragMin = min
    local dragMax = max
    if loop then
        dragMin = -999999999
        dragMax = 999999999
    end

    local newValue, changed = ImGui.DragFloat(text, value, dragStep, dragMin, dragMax, displayFormat)

    local finished = ImGui.IsItemDeactivatedAfterEdit()
    if finished then
        dragBeingEdited = false
    end
    if changed and element and not dragBeingEdited then
        history.addAction(history.getElementChange(element))
        dragBeingEdited = true
    end

    if loop and min ~= nil and max ~= nil then
        newValue = wrapValue(newValue, min, max)
    else
        if min ~= nil then
            newValue = math.max(newValue, min)
        end
        if max ~= nil then
            newValue = math.min(newValue, max)
        end
    end

    return newValue, changed, finished
end

return field
