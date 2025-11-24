local M = {}

local config = require("dooing.config")
local uv = vim.loop
local api = vim.api

local function get_todos_file_path()
	return config.options.save_path or vim.fn.stdpath("data") .. "/dooing_todos.json"
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

local function debug_log(message)
	-- Utility function to log debugging messages to Neovim's command line
	vim.notify("[Dooing Debug] " .. message, vim.log.levels.DEBUG)
end

local function start_server(port, todos_json)
	local server = uv.new_tcp()

	local success, err = pcall(function()
		server:bind("0.0.0.0", port) -- Ensure binding to all interfaces
		debug_log("Server bound to 0.0.0.0 on port " .. port)
	end)

	if not success then
		vim.notify("Failed to bind server: " .. err, vim.log.levels.ERROR)
		return nil
	end

	server:listen(128, function()
		debug_log("Server listening for connections")
		local client = uv.new_tcp()
		server:accept(client)

		client:read_start(function(err, chunk)
			if err then
				debug_log("Error reading from client: " .. err)
				client:close()
				return
			end
			if chunk then
				local path = chunk:match("GET (%S+) HTTP")

				local response_content
				local content_type

				local local_ip = get_local_ip()
				if path == "/todos" then
					response_content = todos_json
					content_type = "application/json"
				else
					response_content = string.format(
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
	<div class="ip-info">Server IP: %s:%d</div>
	<script>
		new QRCode(document.getElementById("qrcode"), {
			text: "http://%s:%d/todos",
			width: 256,
			height: 256
		});
	</script>
</body>
</html>
]],
						local_ip,
						port,
						local_ip,
						port
					)
					content_type = "text/html"
				end

				local response = table.concat({
					"HTTP/1.1 200 OK",
					"Content-Type: " .. content_type,
					"Access-Control-Allow-Origin: *",
					"Connection: close",
					"",
					response_content,
				}, "\r\n")

				client:write(response)
				client:shutdown()
				client:close()
			end
		end)
	end)

	return server
end

function M.start_qr_server()
	local file = io.open(get_todos_file_path(), "r")
	if not file then
		vim.notify("Could not read todos file", vim.log.levels.ERROR)
		return
	end

	local todos_json = file:read("*all")
	file:close()

	local port = 7283
	local local_ip = get_local_ip()
	if local_ip == "127.0.0.1" then
		vim.notify("Warning: Server is only accessible on localhost", vim.log.levels.WARN)
	end

	local server = start_server(port, todos_json)

	if server then
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
			server:close()
			debug_log("Server stopped by user")
		end, { buffer = buf, nowait = true })

		vim.keymap.set("n", "e", function()
			api.nvim_win_close(win, true)
			debug_log("Window closed, server still running")
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
	else
		vim.notify("Failed to start server", vim.log.levels.ERROR)
	end
end

return M
