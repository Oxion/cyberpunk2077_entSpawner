local utils = require("modules/utils/utils")
config = {}

function config.fileExists(filename)
    local f=io.open(filename,"r")
    if (f~=nil) then io.close(f) return true else return false end
end

local function readAll(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()
    return content
end

local function writeAll(path, content)
    local file = io.open(path, "w")
    if not file then
        return false, "open_failed"
    end

    local ok, err = pcall(function ()
        file:write(content)
    end)
    file:close()

    if not ok then
        os.remove(path)
        return false, tostring(err)
    end

    return true
end

local function replaceFile(path, tmpPath)
    if os.rename(tmpPath, path) then
        return true
    end

    local swapPath = path .. ".swap"
    local hasTarget = config.fileExists(path)

    if hasTarget then
        if config.fileExists(swapPath) then
            os.remove(swapPath)
        end

        if not os.rename(path, swapPath) then
            return false, "swap_failed"
        end
    end

    if os.rename(tmpPath, path) then
        if hasTarget then
            os.remove(swapPath)
        end
        return true
    end

    if hasTarget and config.fileExists(swapPath) then
        os.rename(swapPath, path)
    end

    return false, "promote_failed"
end

local function recoverSwapFile(path)
    local swapPath = path .. ".swap"
    if not config.fileExists(swapPath) then
        return
    end

    if config.fileExists(path) then
        os.remove(swapPath)
        return
    end

    os.rename(swapPath, path)
end

function config.tryCreateConfig(path, data)
	if not config.fileExists(path) then
        config.saveFile(path, data)
    end
end

function config.loadFile(path)
    recoverSwapFile(path)

    local raw = readAll(path)
    if raw == nil then
        print("Failed to load file: " .. path .. ", restoring empty state")
        return {}
    end

    local decoded = {}
    local success = pcall(function ()
        decoded = json.decode(raw)
    end)
    if not success then
        print("Failed to load file: " .. path .. ", restoring empty state")
        return {}
    end
    if type(decoded) ~= "table" then
        print("Failed to load file: " .. path .. ", restoring empty state")
        return {}
    end

    return decoded
end

function config.saveFile(path, data)
    recoverSwapFile(path)

    local encoded
    local encodedOk, encodedErr = pcall(function ()
        encoded = json.encode(data)
    end)
    if not encodedOk then
        print("Failed to encode file: " .. path .. " (" .. tostring(encodedErr) .. ")")
        return false, tostring(encodedErr)
    end
    if type(encoded) ~= "string" then
        print("Failed to encode file: " .. path .. " (invalid payload)")
        return false, "invalid_payload"
    end

    local tmpPath = path .. ".tmp"
    if config.fileExists(tmpPath) then
        os.remove(tmpPath)
    end

    local written, writeErr = writeAll(tmpPath, encoded)
    if not written then
        os.remove(tmpPath)
        print("Failed to write temp file: " .. tmpPath .. " (" .. tostring(writeErr) .. ")")
        return false, tostring(writeErr)
    end

    local replaced, replaceErr = replaceFile(path, tmpPath)
    if not replaced then
        os.remove(tmpPath)
        print("Failed to replace file: " .. path .. " (" .. tostring(replaceErr) .. ")")
        return false, tostring(replaceErr)
    end

    return true
end

function config.loadFiles(path, files)
    local files = files or {}

    for _, file in pairs(dir(path)) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile(path .. file.name)
            table.insert(files, {data = data.spawnable, lastSpawned = nil, name = data.name, fileName = data.name })
        elseif file.type == "directory" then
            config.loadFiles(path .. file.name .. "/", files)
        end
    end

    table.sort(files, function(a, b) return a.name < b.name end)

    return files
end

function config.loadLists(path, paths)
    local paths = paths or {}

    for _, file in pairs(dir(path)) do
        local extension = file.name:match("^.+(%..+)$")
        if extension and extension:lower() == ".txt" then
            local data = io.open(path .. file.name)
            for line in data:lines() do
                table.insert(paths, {data = { spawnData = line }, lastSpawned = nil, name = line, fileName = utils.getFileName(line) })
            end

            data:close()
        elseif file.type == "directory" then
            config.loadLists(path .. file.name .. "/", paths)
        end
    end

    table.sort(paths, function(a, b) return a.name < b.name end)

    return paths
end

local function recursiveAddMissingKeys(source, target)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            recursiveAddMissingKeys(v, target[k])
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function config.backwardComp(path, data)
    local f = config.loadFile(path)

    recursiveAddMissingKeys(data, f)

    config.saveFile(path, f)
end

function config.loadText(path)
    local lines = {}
    for line in io.lines(path) do
        table.insert(lines, line)
    end
    return lines
end

function config.loadRaw(path)
    local file = io.open(path, "r")
    local content = file:read("*a")
    file:close()
    return content
end

function config.saveRaw(path, data)
    local file = io.open(path, "w")
    file:write(data)
    file:close()
end

function config.saveRawTable(path, data)
    local file = io.open(path, "w")
    for _, line in pairs(data) do
        file:write(line .. "\n")
    end
    file:close()
end

return config
