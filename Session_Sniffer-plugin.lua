-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for Session Sniffer project on GitHub.
-- Allows you to automatically have every usernames showing up on Session Sniffer project, by logging all players from your sessions to "Lexis\Grand Theft Auto V\scripts\Session_Sniffer-plugin\log.txt".
-- GitHub Repository: https://github.com/Illegal-Services/Session_Sniffer-plugin-Lexis-Lua

-- === Globals ===
local mainLoopThread = nil
local logged_players = {}  -- map: scid -> { [ip] = true }
local initialization_done = false

---- Global constants START
local SCRIPT_NAME <const> = "Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "Session Sniffer"
local SCRIPT_LOG__PATH <const> = paths.script .. "\\Session_Sniffer-plugin\\log.txt"
local natives <const> = require('natives')

-- === Utility Functions ===
local function is_file_string_need_newline_ending(str)
    return #str > 0 and str:sub(-1) ~= "\n"
end

local function read_file(file_path)
    local handle = file.open(file_path, { create_if_not_exists = false })
    if not handle.valid then
        return nil, "Failed to open file"
    end
    return handle.text, nil
end

local function handle_script_exit(params)
    params = params or {}
    if params.hasScriptCrashed == nil then params.hasScriptCrashed = false end

    if mainLoopThread and not params.skipThreadCleanup then
        util.remove_thread(mainLoopThread)
        mainLoopThread = nil
    end

    if params.hasScriptCrashed then
        notify.push(
            SCRIPT_TITLE,
            "Oh no... Script crashed:(\nYou gotta restart it manually.",
            { time = 10000 }
        )
    end

    this.unload()
end

local function create_empty_file(filepath)
    local dir = filepath:match("^(.*)[/\\]")
    if dir and not dirs.exists(dir) then dirs.create(dir) end

    local handle = file.open(filepath, { create_if_not_exists = true })
    if not handle.valid then
        notify.push(
            SCRIPT_TITLE,
            "Failed to create log file at:\n" .. filepath,
            { time = 15000 }
        )
        return false
    end
    return true
end

local function dec_to_ipv4(ip)
    return string.format("%i.%i.%i.%i", ip >> 24 & 255, ip >> 16 & 255, ip >> 8 & 255, ip & 255)
end

-- === Initialization Job ===
util.create_job(function()
    -- Ensure log file exists
    if not file.exists(SCRIPT_LOG__PATH) then
        if not create_empty_file(SCRIPT_LOG__PATH) then
            handle_script_exit({ hasScriptCrashed = true })
            return
        end
    end

    -- Load log file content
    local log__content, err = read_file(SCRIPT_LOG__PATH)
    if err then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    -- Fix newline if missing
    if is_file_string_need_newline_ending(log__content) then
        local handle = file.open(SCRIPT_LOG__PATH, { append = true })
        if handle.valid then
            handle.text = handle.text .. "\n"
            log__content = log__content .. "\n"
        end
    end

    -- Populate logged_players set from existing log
    for line in log__content:gmatch("[^\r\n]+") do
        local scid, ip = line:match("scid:(%d+), ip:([%d%.]+)")
        if scid and ip then
            local scid_num = tonumber(scid)
            if scid_num then
                logged_players[scid_num] = logged_players[scid_num] or {}
                logged_players[scid_num][ip] = true
            end
        end
    end

    initialization_done = true
end)

-- === Logging Helpers ===
local function loggerPreTask(player_entries_to_log, currentTimestamp, playerSCID, playerName, playerIP)
    logged_players[playerSCID] = logged_players[playerSCID] or {}
    if not logged_players[playerSCID][playerIP] then
        logged_players[playerSCID][playerIP] = true
        table.insert(player_entries_to_log,
            string.format(
                "user:%s, scid:%d, ip:%s, timestamp:%d",
                playerName, playerSCID, playerIP, currentTimestamp
            )
        )
    end
end

local function write_to_log_file(player_entries_to_log)
    local handle = file.open(SCRIPT_LOG__PATH, { append = true })
    if not handle.valid then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    handle.text = table.concat(player_entries_to_log, "\n") .. "\n"
end

-- === Main Loop ===
mainLoopThread = util.create_thread(function()
    -- Wait until initialization completes
    while not initialization_done do
        util.yield()
    end

    if natives.network_is_session_started() then
        local player_entries_to_log = {}
        local currentTimestamp = os.time()

        for _, player in ipairs(players.list()) do
            if player.connected and player.exists and player ~= players.me() then
                local playerSCID = player.rockstar_id
                local playerName = player.name
                local playerIP = dec_to_ipv4(player.ip_address)

                if playerSCID and playerName and playerIP and playerIP ~= "255.255.255.255" then
                    loggerPreTask(player_entries_to_log, currentTimestamp, playerSCID, playerName, playerIP)
                end
            end
            util.yield()
        end

        if #player_entries_to_log > 0 then
            write_to_log_file(player_entries_to_log)
        end
    end
end)
