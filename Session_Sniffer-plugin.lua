-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for Session Sniffer project on GitHub.
-- Allows you to automatically have every usernames showing up on Session Sniffer project, by logging all players from your sessions to "Lexis\Grand Theft Auto V\scripts\Session_Sniffer-plugin\log.txt".
-- GitHub Repository: https://github.com/BUZZARDGTA/Session_Sniffer-plugin-Lexis-Lua


-- === Globals ===
local mainLoopThread = nil
local last_logger_scan_timestamp = 0
local logged_players = {}
local last_written_host_key = nil

-- === Constants ===
local SCRIPT_NAME <const> = "Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "Session Sniffer"
local SCRIPT_LOG__PATH <const> = paths.script .. "\\Session_Sniffer-plugin\\log.txt"
local SCRIPT_HOST__PATH <const> = paths.script .. "\\Session_Sniffer-plugin\\session_host.txt"
local LOGGER_SCAN_INTERVAL_SECONDS <const> = 1

-- === Utility Functions ===
local function handle_script_exit(params)
    params = params or {}
    local host_handle = file.open(SCRIPT_HOST__PATH, { create_if_not_exists = true })
    if host_handle.valid then
        host_handle.text = ""
    end

    if mainLoopThread and not params.skipThreadCleanup then
        util.remove_thread(mainLoopThread)
        mainLoopThread = nil
    end

    if params.hasScriptCrashed then
        notify.push(
            SCRIPT_TITLE,
            "Oh no... Script crashed:(\nYou gotta restart it manually.",
            { time = 10000, icon = notify.icon.hazard }
        )
    end

    this.unload()
end

local function dec_to_ipv4(ip)
    return string.format(
        "%i.%i.%i.%i",
        ip >> 24 & 255,
        ip >> 16 & 255,
        ip >> 8 & 255,
        ip & 255
    )
end

local function make_dedup_key(scid, ip, name)
    return scid .. ":" .. ip .. ":" .. name
end

local function write_session_host_file(host_key, host_entry)
    host_key = host_key or ""
    host_entry = host_entry or ""
    if host_key == last_written_host_key then
        return
    end

    local handle = file.open(SCRIPT_HOST__PATH, { create_if_not_exists = true })
    if not handle.valid then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    handle.text = host_entry
    last_written_host_key = host_key
end

local function init_log_cache()
    local dir = SCRIPT_LOG__PATH:match("^(.*)[/\\]")
    if dir and not dirs.exists(dir) then
        dirs.create(dir)
    end

    write_session_host_file("", "")

    local handle = file.open(SCRIPT_LOG__PATH, { create_if_not_exists = true })
    if not handle.valid then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    local content = handle.text
    if not content or #content == 0 then
        notify.push(SCRIPT_TITLE, "Initialized new log file.", { time = 5000, icon = notify.icon.info })
        return
    end

    local loaded_count = 0
    for line in content:gmatch("[^\r\n]+") do
        local name, scid, ip = line:match("^user:(.-), scid:(%d+), ip:([%d%.]+)")
        if name and scid and ip then
            local key = make_dedup_key(scid, ip, name)
            if not logged_players[key] then
                logged_players[key] = true
                loaded_count = loaded_count + 1
            end
        end
    end

    -- Ensure the file ends with a trailing newline if it has content
    if content:sub(-1) ~= "\n" then
        local append_handle = file.open(SCRIPT_LOG__PATH, { append = true })
        if append_handle.valid then
            append_handle.text = "\n"
        end
    end

    notify.push(
        SCRIPT_TITLE,
        string.format("Loaded %d unique player%s from log.", loaded_count, loaded_count == 1 and "" or "s"),
        { time = 5000, icon = notify.icon.info }
    )
end

local function write_to_log_file(player_entries_to_log)
    local handle = file.open(SCRIPT_LOG__PATH, { append = true })
    if not handle.valid then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    local combined_entries = table.concat(player_entries_to_log, "\n") .. "\n"
    handle.text = combined_entries
end


-- === Main Menu Features ===
local is_logging_enabled = true


-- === Initialization ===
init_log_cache()


-- === Main Loop ===
mainLoopThread = util.create_thread(function()
    if is_logging_enabled then
        local currentTimestamp = os.time()

        if currentTimestamp - last_logger_scan_timestamp >= LOGGER_SCAN_INTERVAL_SECONDS then
            last_logger_scan_timestamp = currentTimestamp

            local player_list = players.list()
            if player_list and #player_list > 0 then
                local player_entries_to_log = nil
                local host_key = ""
                local host_entry = ""
                local session_host = game.host()
                local hostPlayerID = session_host and session_host.exists and session_host.connected and session_host.id or nil

                for _, player in ipairs(player_list) do
                    if player and player ~= players.me() and type(player.ip_address) == "number" then
                        local playerSCID = player.rockstar_id
                        if playerSCID and playerSCID > 0 then
                            local playerIP = dec_to_ipv4(player.ip_address)
                            if playerIP and playerIP ~= "255.255.255.255" and playerIP ~= "0.0.0.0" then
                                local playerName = player.name
                                if playerName and playerName ~= "" and playerName ~= "**Invalid**" then
                                    local key = make_dedup_key(playerSCID, playerIP, playerName)
                                    local formatted_entry = string.format(
                                        "user:%s, scid:%d, ip:%s, timestamp:%d",
                                        playerName, playerSCID, playerIP, currentTimestamp
                                    )
                                    if not logged_players[key] then
                                        logged_players[key] = true
                                        player_entries_to_log = player_entries_to_log or {}
                                        player_entries_to_log[#player_entries_to_log + 1] = formatted_entry
                                    end
                                    if hostPlayerID ~= nil and player.id == hostPlayerID then
                                        host_key = key
                                        host_entry = formatted_entry .. "\n"
                                    end
                                end
                            end
                        end
                    end
                end

                if player_entries_to_log then
                    write_to_log_file(player_entries_to_log)
                end

                write_session_host_file(host_key, host_entry)
            else
                write_session_host_file("", "")
            end
        end
    else
        write_session_host_file("", "")
    end

    util.yield(100)
end)
