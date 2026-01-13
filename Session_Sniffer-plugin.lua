-- Author: IB_U_Z_Z_A_R_Dl
-- Description: Plugin for Session Sniffer project on GitHub.
-- Enables username resolution in the Session Sniffer project by logging all players from your sessions to "Lexis\Grand Theft Auto V\scripts\Session_Sniffer-plugin\log.txt".
-- GitHub Repository: https://github.com/Illegal-Services/Session_Sniffer-plugin-Lexis-Lua

-- === Globals ===
local main_loop_thread = nil
local initialization_done = false
local loggedPlayers = {}  -- Dedup map: scid -> { [ip] = true }
local log_queue = {}  -- Single-writer queue

-- === Constants ===
local SCRIPT_NAME <const> = "Session_Sniffer-plugin.lua"
local SCRIPT_TITLE <const> = "Session Sniffer"
local LOG_FILE_PATH <const> = paths.script .. "\\Session_Sniffer-plugin\\log.txt"
local Natives <const> = require("natives")

-- === Utility Functions ===
local function needs_trailing_newline(str)
    return #str > 0 and str:sub(-1) ~= "\n"
end

local function read_or_create_file(path)
    local dir = path:match("^(.*)[/\\]")
    if dir and not dirs.exists(dir) then
        dirs.create(dir)
    end

    local handle = file.open(path, { create_if_not_exists = true })
    if not handle.valid then
        return nil
    end
    return handle.text
end

local function handle_script_exit(opts)
    opts = opts or {}

    if main_loop_thread and not opts.skip_thread_cleanup then
        util.remove_thread(main_loop_thread)
        main_loop_thread = nil
    end

    if opts.has_script_crashed then
        notify.push(
            SCRIPT_TITLE,
            "Oh no... Script crashed:(\nYou'll need to restart it manually.",
            { time = 15000, icon = notify.icon.hazard }
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

-- === Player Validation ===
local function is_valid_player_entry(scid, ip, name)
    if not scid or scid <= 0 then return false end
    if not ip or ip == "" or ip == "0.0.0.0" or ip == "255.255.255.255" then return false end
    if not name or name == "" or name == "**Invalid**" then return false end
    return true
end

local function extract_valid_player_data(player)
    if not player
        or not player.connected
        or not player.exists
        or player == players.me()
        or type(player.ip_address) ~= "number"
    then
        return nil
    end

    local scid = player.rockstar_id
    local ip = dec_to_ipv4(player.ip_address)
    local name = player.name

    if not is_valid_player_entry(scid, ip, name) then
        return nil
    end

    return scid, name, ip
end

-- === Logging Core ===
local function build_log_entry(timestamp, scid, name, ip)
    loggedPlayers[scid] = loggedPlayers[scid] or {}

    if loggedPlayers[scid][ip] then
        return nil
    end

    loggedPlayers[scid][ip] = true

    return string.format(
        "user:%s, scid:%d, ip:%s, timestamp:%d",
        name, scid, ip, timestamp
    )
end

local function enqueue_log_entry(entry)
    log_queue[#log_queue + 1] = entry
end

-- === Initialization Job ===
util.create_job(function()
    local log_content = read_or_create_file(LOG_FILE_PATH)
    if not log_content then
        notify.push(
            SCRIPT_TITLE,
            "Failed to read/create log file at:\n" .. LOG_FILE_PATH,
            { time = 10000, icon = notify.icon.hazard }
        )

        handle_script_exit({ has_script_crashed = true })
        return
    end

    if needs_trailing_newline(log_content) then
        local handle = file.open(LOG_FILE_PATH, { append = true })
        if handle.valid then
            handle.text = handle.text .. "\n"
            log_content = log_content .. "\n"
        end
    end

    local unique_scids, unique_ips, unique_names = {}, {}, {}
    local total_lines, total_loaded = 0, 0

    for line in log_content:gmatch("[^\r\n]+") do
        total_lines = total_lines + 1

        local name, scid, ip = line:match("user:([^,]+), scid:(%d+), ip:([%d%.]+)")
        if name and scid and ip then
            local scid_num = tonumber(scid)
            if is_valid_player_entry(scid_num, ip, name) then
                loggedPlayers[scid_num] = loggedPlayers[scid_num] or {}
                loggedPlayers[scid_num][ip] = true

                unique_scids[scid_num] = true
                unique_ips[ip] = true
                if name and name ~= "" and name ~= "**Invalid**" then unique_names[name] = true end

                total_loaded = total_loaded + 1
            end
        end
    end

    initialization_done = true

    local function count(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
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

-- === Single Writer Thread ===
util.create_thread(function()
    if #log_queue > 0 then
        local entries_to_write = log_queue
        log_queue = {}

        local handle = file.open(LOG_FILE_PATH, { append = true })
        if not handle.valid then
            handle_script_exit({ has_script_crashed = true })
            return
        end

        handle.text = table.concat(entries_to_write, "\n") .. "\n"
    end

    util.yield(500)
end)

-- === Event Listener ===
events.subscribe(events.event.player_join, function(data)
    while not initialization_done do
        util.yield()
    end

    local scid, name, ip = extract_valid_player_data(data.player)
    if scid then
        local entry = build_log_entry(os.time(), scid, name, ip)
        if entry then
            enqueue_log_entry(entry)
        end
    end
end)

-- === Main Loop ===
main_loop_thread = util.create_thread(function()
    while not initialization_done do
        util.yield()
    end

    if not Natives.network_is_session_started() then
        return
    end

    for _, player in ipairs(players.list()) do
        local scid, name, ip = extract_valid_player_data(player)
        if scid then
            local entry = build_log_entry(os.time(), scid, name, ip)
            if entry then
                enqueue_log_entry(entry)
            end
        end

        util.yield()
    end
end)
