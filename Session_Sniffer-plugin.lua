-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for Session Sniffer project on GitHub.
-- Enables username resolution in the Session Sniffer project by logging all players from your sessions to "Lexis\Grand Theft Auto V\scripts\Session_Sniffer-plugin\log.txt".
-- GitHub Repository: https://github.com/Illegal-Services/Session_Sniffer-plugin-Lexis-Lua

-- === Globals ===
local mainLoopThread = nil
local loggedPlayers = {}  -- map: scid -> { [ip] = true }
local initializationDone = false

-- === Constants ===
local SCRIPT_NAME <const> = "Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "Session Sniffer"
local LOG_FILE_PATH <const> = paths.script .. "\\Session_Sniffer-plugin\\log.txt"
local Natives <const> = require("natives")

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
    if params.has_script_crashed == nil then params.has_script_crashed = false end

    if mainLoopThread and not params.skip_thread_cleanup then
        util.remove_thread(mainLoopThread)
        mainLoopThread = nil
    end

    if params.has_script_crashed then
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
        handle_script_exit({ has_script_crashed = true })
        return
    end

    -- Load log content
    local log_content, err = read_file(LOG_FILE_PATH)
    if err then
        handle_script_exit({ has_script_crashed = true })
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
                loggedPlayers[scid_num] = loggedPlayers[scid_num] or {}
                loggedPlayers[scid_num][ip] = true

                unique_scids[scid_num] = true
                unique_ips[ip] = true
                if name and name ~= "" then unique_names[name] = true end
            end
        end
    end

    initializationDone = true

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
local function add_player_to_log_buffer(player_entries_to_log, current_timestamp, player_scid, player_name, player_ip)
    loggedPlayers[player_scid] = loggedPlayers[player_scid] or {}
    if not loggedPlayers[player_scid][player_ip] then
        loggedPlayers[player_scid][player_ip] = true
        player_entries_to_log[#player_entries_to_log + 1] = string.format(
            "user:%s, scid:%d, ip:%s, timestamp:%d",
            player_name, player_scid, player_ip, current_timestamp
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
        handle_script_exit({ has_script_crashed = true })
        return
    end

    handle.text = table.concat(player_entries_to_log, "\n") .. "\n"
end

-- === Event Listeners ===
events.subscribe(events.event.player_join, function(data)
    while not initializationDone do
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
mainLoopThread = util.create_thread(function()
    while not initialization_done do
        util.yield()
    end

    if Natives.network_is_session_started() then
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
