-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for Session Sniffer project on GitHub.
-- Allows you to automatically have every usernames showing up on Session Sniffer project, by logging all players from your sessions to "Lexis\Grand Theft Auto V\scripts\Session_Sniffer-plugin\log.txt".
-- GitHub Repository: https://github.com/Illegal-Services/Session_Sniffer-plugin-Lexis-Lua

-- === Globals ===
local main_loop_thread = nil
local logged_players = {}  -- map: scid -> { [ip] = true }
local initialization_done = false

-- === Constants ===
local SCRIPT_NAME <const> = "Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "Session Sniffer"
local LOG_FILE_PATH <const> = paths.script .. "\\Session_Sniffer-plugin\\log.txt"
local NATIVES <const> = require('natives')

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

local function handle_script_exit(params)
    params = params or {}
    if params.hasScriptCrashed == nil then params.hasScriptCrashed = false end

    if main_loop_thread and not params.skipThreadCleanup then
        util.remove_thread(main_loop_thread)
        main_loop_thread = nil
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

local function dec_to_ipv4(ip)
    return string.format("%i.%i.%i.%i", ip >> 24 & 255, ip >> 16 & 255, ip >> 8 & 255, ip & 255)
end

local function extract_valid_player_data(player)
    if not player
        or not player.connected
        or not player.exists
        or player == players.me()
        or type(player.ip_address) ~= "number" then
        return nil
    end

    local scid = player.rockstar_id
    if not scid or scid <= 0 then return nil end

    local ip = dec_to_ipv4(player.ip_address)
    if ip == "0.0.0.0" or ip == "255.255.255.255" then return nil end

    local name = player.name
    if not name or name == "" or name == "**Invalid**" then return nil end

    return scid, name, ip
end

-- === Initialization Job ===
util.create_job(function()
    -- Ensure log file exists
    if not file.exists(LOG_FILE_PATH) and not create_empty_file(LOG_FILE_PATH) then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    -- Load log content
    local log_content, err = read_file(LOG_FILE_PATH)
    if err then
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    -- Fix missing newline
    if is_file_string_need_newline_ending(log_content) then
        local handle = file.open(LOG_FILE_PATH, { append = true })
        if handle.valid then
            handle.text = handle.text .. "\n"
            log_content = log_content .. "\n"
        end
    end

    -- Sets for stats
    local unique_scids, unique_ips, unique_names = {}, {}, {}
    local total_lines, total_loaded = 0, 0

    -- Populate logged_players
    for line in log_content:gmatch("[^\r\n]+") do
        total_lines = total_lines + 1

        local name, scid, ip = line:match("user:([^,]+),%s*scid:(%d+),%s*ip:([%d%.]+)")
        if not scid or not ip then
            scid, ip = line:match("scid:(%d+), ip:([%d%.]+)")
        end

        if scid and ip then
            local scid_num = tonumber(scid)
            if scid_num and scid_num > 0 and ip ~= "0.0.0.0" and ip ~= "255.255.255.255" then
                total_loaded = total_loaded + 1
                logged_players[scid_num] = logged_players[scid_num] or {}
                logged_players[scid_num][ip] = true

                unique_scids[scid_num] = true
                unique_ips[ip] = true
                if name and name ~= "" then unique_names[name] = true end
            end
        end
    end

    initialization_done = true

    local function count(tbl)
        local n = 0
        for _ in pairs(tbl) do n = n + 1 end
        return n
    end

    notify.push(
        SCRIPT_TITLE,
        string.format(
            "Loaded %d players (%d names, %d IPs)\nLines: %d/%d\nLog: %s",
            count(unique_scids),
            count(unique_names),
            count(unique_ips),
            total_loaded,
            total_lines,
            LOG_FILE_PATH
        ),
        { time = 8000, icon = notify.icon.info }
    )
end)

-- === Logging Helpers ===
local function add_player_to_log_buffer(player_entries_to_log, currentTimestamp, playerSCID, playerName, playerIP)
    logged_players[playerSCID] = logged_players[playerSCID] or {}
    if not logged_players[playerSCID][playerIP] then
        logged_players[playerSCID][playerIP] = true
        player_entries_to_log[#player_entries_to_log + 1] = string.format(
            "user:%s, scid:%d, ip:%s, timestamp:%d",
            playerName, playerSCID, playerIP, currentTimestamp
        )
    end
end

local function write_log_buffer_to_file(player_entries_to_log)
    local handle = file.open(LOG_FILE_PATH, { append = true })
    if not handle.valid then
        notify.push(
            SCRIPT_TITLE,
            "Cannot write to log file.\nScript is useless without logging.",
            { time = 10000, icon = notify.icon.hazard }
        )
        handle_script_exit({ hasScriptCrashed = true })
        return
    end

    handle.text = table.concat(player_entries_to_log, "\n") .. "\n"
end

-- === Event Listeners ===
events.subscribe(events.event.player_join, function(data)
    while not initialization_done do
        util.yield()
    end

    local player_entries_to_log = {}
    local player = data.player

    local scid, name, ip = extract_valid_player_data(player)
    if scid then
        add_player_to_log_buffer(player_entries_to_log, os.time(), scid, name, ip)
    end

    if #player_entries_to_log > 0 then
        write_log_buffer_to_file(player_entries_to_log)
    end
end)

-- === Main Loop ===
main_loop_thread = util.create_thread(function()
    while not initialization_done do
        util.yield()
    end

    if NATIVES.network_is_session_started() then
        local player_entries_to_log = {}

        for _, player in ipairs(players.list()) do
            local scid, name, ip = extract_valid_player_data(player)
            if scid then
                add_player_to_log_buffer(player_entries_to_log, os.time(), scid, name, ip)
            end
            util.yield()
        end

        if #player_entries_to_log > 0 then
            write_log_buffer_to_file(player_entries_to_log)
        end
    end
end)
