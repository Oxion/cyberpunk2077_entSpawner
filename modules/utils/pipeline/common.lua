local pipelineCommon = {}

---@return number
function pipelineCommon.nowMs()
    return os.clock() * 1000
end

---@param data table?
---@param clearLocks boolean?
---@return table
function pipelineCommon.copyNodeDataWithoutChildren(data, clearLocks)
    local copied = {}

    for key, value in pairs(data or {}) do
        if key ~= "childs" then
            copied[key] = value
        end
    end

    if clearLocks then
        copied.locked = false
        copied.lockedByParent = false
    end

    return copied
end

---@param kind "info"|"warning"|"error"|"success"|string
---@return integer
function pipelineCommon.resolveToastType(kind)
    local toastType = ImGui and ImGui.ToastType
    if not toastType then
        return 0
    end

    if kind == "info" and toastType.Info then
        return toastType.Info
    end

    if kind == "warning" and toastType.Warning then
        return toastType.Warning
    end

    if kind == "error" and toastType.Error then
        return toastType.Error
    end

    return toastType.Success or toastType.Info or 0
end

---@param queue table
---@param kind "info"|"warning"|"error"|"success"|string
---@param duration number?
---@param text string
function pipelineCommon.queueToast(queue, kind, duration, text)
    table.insert(queue, {
        type = pipelineCommon.resolveToastType(kind),
        duration = duration or 3000,
        text = text
    })
end

---@param queue table
---@return boolean shown
function pipelineCommon.drawQueuedToasts(queue)
    if #queue > 0 then
        local toast = table.remove(queue, 1)
        if ImGui and ImGui.ShowToast and ImGui.Toast and ImGui.Toast.new then
            ImGui.ShowToast(ImGui.Toast.new(toast.type, toast.duration, toast.text))
        end
        return true
    end

    return false
end

---@class pipelineProgressOptions
---@field phaseText string
---@field progress number
---@field counterText string?
---@field helpText string?
---@field cancelText string?
---@field barWidth number?
---@field barHeight number?
---@field barOverlay string?
---@field showSeparator boolean?
---@field onCancel function?
---@field style any

---@param options pipelineProgressOptions
function pipelineCommon.drawCancelableProgress(options)
    local style = options.style
    local phaseText = options.phaseText or ""
    local progress = math.max(0, math.min(1, options.progress or 0))
    local counterText = options.counterText or ""
    local helpText = options.helpText or ""
    local cancelText = options.cancelText or "Cancel"
    local barWidth = options.barWidth or (260 * style.viewSize)
    local barHeight = options.barHeight or (13 * style.viewSize)
    local barOverlay = options.barOverlay or ""
    local showSeparator = options.showSeparator ~= false

    ImGui.BeginGroup()
    style.mutedText(phaseText)
    ImGui.ProgressBar(progress, barWidth, barHeight, barOverlay)
    if counterText ~= "" then
        ImGui.SameLine()
        style.mutedText(counterText)
    end
    if helpText ~= "" then
        style.mutedText(helpText)
    end
    ImGui.EndGroup()

    if options.onCancel then
        local cancelTextWidth, _ = ImGui.CalcTextSize(cancelText)
        local cancelButtonWidth = cancelTextWidth + 2 * ImGui.GetStyle().FramePadding.x
        local rightX = ImGui.GetWindowWidth() - ImGui.GetStyle().WindowPadding.x - cancelButtonWidth

        ImGui.SameLine()
        if rightX > ImGui.GetCursorPosX() then
            ImGui.SetCursorPosX(rightX)
        end

        if ImGui.Button(cancelText) then
            options.onCancel()
        end
    end

    if showSeparator then
        style.spacedSeparator()
    end
end

return pipelineCommon
