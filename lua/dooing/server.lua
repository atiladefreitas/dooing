-- The LAN share/sync server.
--
-- Serves the current todos (and, as a deprecated passthrough, bloocky's
-- blocks) to the companion app, and pairs devices for the authenticated v2
-- protocol. Protocol and security posture are documented in
-- docs/SYNC-PROTOCOL.md; request framing and the request guards live in
-- sync/httpd.lua where the spec suite can reach them.
--
-- What changed from the original single-chunk server, and why it could not
-- be extended in place:
--   * requests are properly framed (a POST body spans chunks),
--   * /todos is read from disk per request instead of a snapshot taken at
--     startup and served stale forever,
--   * no Access-Control-Allow-Origin at all, plus Host/Origin guards, so a
--     web page on the same network can neither read nor drive this server,
--   * data endpoints can require a paired device token (sync/devices.lua).

local M = {}

local config = require("dooing.config")
local devices = require("dooing.sync.devices")
local httpd = require("dooing.sync.httpd")
local uv = vim.uv or vim.loop
local api = vim.api

local PROTOCOL_VERSION = 2
local MAX_CONNECTIONS = 16
local IDLE_TIMEOUT_MS = 10000

local server_handle = nil
local open_connections = 0

--------------------------------------------------------------------------
-- Data sources — read per request, so the server never serves a snapshot
--------------------------------------------------------------------------

local function get_todos_file_path()
	return config.options.save_path or vim.fn.stdpath("data") .. "/dooing_todos.json"
end

-- Time blocks live in bloocky.nvim. Ask it where its file is when it's
-- installed, otherwise fall back to its documented default path. This is a
-- deprecated v1 passthrough: once bloocky serves its own bus, the app reads
-- blocks from there and this endpoint goes away.
local function get_blocks_file_path()
	local ok, bloocky_config = pcall(require, "bloocky.config")
	if ok and type(bloocky_config) == "table" then
		local path = bloocky_config.options and bloocky_config.options.save_path
		if type(path) == "string" and path ~= "" then
			return path
		end
	end
	return vim.fn.stdpath("data") .. "/bloocky_blocks.json"
end

-- A missing or empty file is "no items", not an error.
local function read_json_file(path)
	local file = io.open(path, "r")
	if not file then
		return "[]"
	end
	local content = file:read("*all")
	file:close()
	if not content or content:match("^%s*$") then
		return "[]"
	end
	return content
end

local function get_local_ip()
	local socket = uv.new_udp()
	socket:connect("8.8.8.8", 80)
	local sockname = socket:getsockname()
	socket:close()

	if not sockname or not sockname.ip then
		vim.notify("Could not determine local IP address", vim.log.levels.ERROR)
		return "127.0.0.1" -- Fallback to localhost
	end
	return sockname.ip
end

local function server_options()
	local sync = config.options.sync or {}
	return sync.server or {}
end

--------------------------------------------------------------------------
-- The QR page
--------------------------------------------------------------------------

-- The QR carries a v2 pairing payload: host plus a fresh single-use pairing
-- token, minted per page load. Older app builds do not recognise it and keep
-- scanning — pairing needs the updated app. What `sync.server.allow_v1` keeps
-- alive for them is "Sync now from last host" against a host they imported
-- before upgrading, since v1 GETs stay unauthenticated while it holds.
local function qr_page(local_ip, port)
	local token = devices.new_pairing_token()
	local payload = vim.json.encode({
		v = PROTOCOL_VERSION,
		p = "dooing",
		host = ("http://%s:%d"):format(local_ip, port),
		t = token,
	})
	return string.format(
		[[
<!DOCTYPE html>
<html>
<head>
	<meta charset="utf-8">
	<title>Dooing QR Code</title>
	<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
	<style>
		body { background: #1a1a1a; color: #fff; font-family: sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; }
		#qrcode { background: white; padding: 20px; border-radius: 8px; }
		.ip-info { margin-top: 20px; font-size: 14px; color: #888; }
	</style>
</head>
<body>
	<div id="qrcode"></div>
	<div class="ip-info">Server IP: %s:%d &middot; scan within 10 minutes</div>
	<script>
		new QRCode(document.getElementById("qrcode"), {
			text: %s,
			width: 256,
			height: 256
		});
	</script>
</body>
</html>
]],
		local_ip,
		port,
		vim.json.encode(payload) -- payload as a JS string literal
	)
end

--------------------------------------------------------------------------
-- Routing
--------------------------------------------------------------------------

local function authorized(request)
	return devices.authorize(request.headers["authorization"]) ~= nil
end

-- vim.json.encode({}) says "{}", and an empty todos list is an ARRAY. Force
-- the bracket form so a device with zero todos still parses the response.
local function encode_list(list)
	if #list == 0 then
		return "[]"
	end
	return vim.json.encode(list)
end

local function handle_sync_todos(request)
	local device = devices.authorize(request.headers["authorization"])
	if not device then
		return httpd.error_response(401, "pair this device first (scan the QR)")
	end
	local ok, body = pcall(vim.json.decode, request.body)
	if not ok or type(body) ~= "table" then
		return httpd.error_response(400, "expected a JSON body")
	end
	local exchange = require("dooing.sync.exchange")
	local response, status, message = exchange.todos_exchange(device, body)
	if not response then
		return httpd.error_response(status or 500, message or "exchange failed")
	end
	local json = ('{"revision":%d,"todos":%s,"tombstones":%s,"conflicts":%s}'):format(
		response.revision,
		encode_list(response.todos),
		encode_list(response.tombstones),
		encode_list(response.conflicts)
	)
	return httpd.response(200, "application/json", json)
end

local function handle_pair(request)
	local ok, body = pcall(vim.json.decode, request.body)
	if not ok or type(body) ~= "table" then
		return httpd.error_response(400, "expected a JSON body")
	end
	local result, err = devices.pair(body.token, body.device_name)
	if not result then
		return httpd.error_response(401, err or "pairing failed")
	end
	vim.schedule(function()
		vim.notify(("Dooing: paired device %q"):format(result.name), vim.log.levels.INFO)
	end)
	return httpd.json_response(200, result)
end

local function handle_request(request, port)
	-- Guards first, on every route. See sync/httpd.lua for the reasoning.
	if not httpd.check_origin(request.headers["origin"]) then
		return httpd.error_response(403, "cross-origin requests are not allowed")
	end
	if not httpd.check_host(request.headers["host"], port) then
		return httpd.error_response(403, "bad Host header")
	end

	local method, path = request.method, request.path

	if method == "GET" and (path == "/" or path == "") then
		return httpd.response(200, "text/html", qr_page(get_local_ip(), port))
	end

	if method == "GET" and path == "/version" then
		return httpd.json_response(200, { protocol = PROTOCOL_VERSION, product = "dooing" })
	end

	if method == "POST" and path == "/v2/pair" then
		return handle_pair(request)
	end

	if method == "POST" and path == "/v2/sync/todos" then
		return handle_sync_todos(request)
	end

	if path == "/todos" or path == "/blocks" then
		if method ~= "GET" then
			return httpd.error_response(405, "only GET here")
		end
		if not (server_options().allow_v1 or authorized(request)) then
			return httpd.error_response(401, "pair this device first (scan the QR)")
		end
		local file_path = path == "/todos" and get_todos_file_path() or get_blocks_file_path()
		return httpd.response(200, "application/json", read_json_file(file_path))
	end

	return httpd.error_response(404, "no such endpoint")
end

--------------------------------------------------------------------------
-- Connections
--------------------------------------------------------------------------

local function close_client(client, timer)
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
	if not client:is_closing() then
		client:shutdown()
		client:close()
	end
	open_connections = math.max(0, open_connections - 1)
end

local function handle_connection(client, port)
	open_connections = open_connections + 1
	local parser = httpd.new_parser()

	local timer = uv.new_timer()
	timer:start(IDLE_TIMEOUT_MS, 0, function()
		close_client(client, timer)
	end)

	client:read_start(function(err, chunk)
		if err or not chunk then
			close_client(client, timer)
			return
		end

		local request, parse_err = parser:feed(chunk)
		if parse_err then
			client:write(httpd.error_response(400, parse_err))
			close_client(client, timer)
			return
		end
		if not request then
			return -- incomplete; keep reading
		end

		-- Handlers touch vim.* and the filesystem; run them on the main loop.
		vim.schedule(function()
			local ok, response = pcall(handle_request, request, port)
			if not ok then
				response = httpd.error_response(500, "internal error")
			end
			client:write(response)
			close_client(client, timer)
		end)
	end)
end

local function start_server(port)
	local server = uv.new_tcp()
	local bind_address = server_options().bind or "0.0.0.0"

	local success, err = pcall(function()
		server:bind(bind_address, port)
	end)
	if not success then
		vim.notify("Failed to bind server: " .. tostring(err), vim.log.levels.ERROR)
		return nil
	end

	server:listen(128, function()
		local client = uv.new_tcp()
		server:accept(client)
		if open_connections >= MAX_CONNECTIONS then
			client:close()
			return
		end
		handle_connection(client, port)
	end)

	return server
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function M.is_running()
	return server_handle ~= nil and not server_handle:is_closing()
end

-- The footer shows a green indicator while the server runs; refresh it on
-- start/stop so an already-open window picks up the change
local function refresh_footer()
	pcall(function()
		require("dooing.ui.window").update_window_title()
	end)
end

function M.start()
	if M.is_running() then
		return true
	end
	local port = server_options().port or 7283
	server_handle = start_server(port)
	refresh_footer()
	return server_handle ~= nil
end

function M.stop()
	if M.is_running() then
		server_handle:close()
	end
	server_handle = nil
	refresh_footer()
end

function M.start_qr_server()
	local port = server_options().port or 7283
	local local_ip = get_local_ip()
	if local_ip == "127.0.0.1" then
		vim.notify("Warning: Server is only accessible on localhost", vim.log.levels.WARN)
	end

	if not M.start() then
		vim.notify("Failed to start server", vim.log.levels.ERROR)
		return
	end

	local buf = api.nvim_create_buf(false, true)
	local url = string.format("http://%s:%d", local_ip, port)

	api.nvim_buf_set_lines(buf, 0, -1, false, {
		"",
		" Server running at:",
		" " .. url,
		"",
		" Make sure your phone is on the same network",
		" [q] to close window and stop server",
		" [e] to exit and keep server running",
		"",
	})

	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		width = 50,
		height = 8,
		row = math.floor((vim.o.lines - 8) / 2),
		col = math.floor((vim.o.columns - 50) / 2),
		style = "minimal",
		border = config.options.window.border,
		title = " Dooing Share ",
		title_pos = "center",
	})

	vim.keymap.set("n", "q", function()
		api.nvim_win_close(win, true)
		M.stop()
	end, { buffer = buf, nowait = true })

	vim.keymap.set("n", "e", function()
		api.nvim_win_close(win, true)
		vim.notify("Server still running at " .. url, vim.log.levels.INFO)
	end, { buffer = buf, nowait = true })

	vim.defer_fn(function()
		if vim.fn.has("mac") == 1 then
			os.execute("open " .. url)
		elseif vim.fn.has("unix") == 1 then
			os.execute("xdg-open " .. url)
		elseif vim.fn.has("win32") == 1 then
			os.execute("start " .. url)
		end
	end, 100)
end

-- Spec hook: route a request table straight through the router, no sockets.
function M._handle_request_for_tests(request, port)
	return handle_request(request, port or 7283)
end

return M
