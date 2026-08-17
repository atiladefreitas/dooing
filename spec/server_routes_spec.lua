-- The router: guards, auth posture, and the v1 compatibility switch.
-- Driven through server._handle_request_for_tests — no sockets involved.

local config = require("dooing.config")
local devices = require("dooing.sync.devices")
local server = require("dooing.server")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")

local function fresh(opts)
	devices.reset_for_tests()
	devices._path_override = dir .. "/devices_" .. math.random(1e9) .. ".json"
	local save_path = dir .. "/todos_" .. math.random(1e9) .. ".json"
	local file = io.open(save_path, "w")
	file:write('[{"id":"1_1","text":"served"}]')
	file:close()
	config.setup(vim.tbl_deep_extend("force", { save_path = save_path }, opts or {}))
end

local function request(method, path, headers, body)
	headers = headers or {}
	headers.host = headers.host or "192.168.1.2:7283"
	return { method = method, path = path, query = "", headers = headers, body = body or "" }
end

local function status_of(response)
	return tonumber(response:match("^HTTP/1%.1 (%d+)"))
end

local function body_of(response)
	return response:match("\r\n\r\n(.*)$")
end

describe("server routes", function()
	it("serves /version publicly", function()
		fresh()
		local response = server._handle_request_for_tests(request("GET", "/version"))
		eq(status_of(response), 200)
		local body = vim.json.decode(body_of(response))
		eq(body.product, "dooing")
		eq(body.protocol, 2)
	end)

	it("rejects any request with an Origin header", function()
		fresh()
		local response =
			server._handle_request_for_tests(request("GET", "/todos", { origin = "http://evil.example.com" }))
		eq(status_of(response), 403)
	end)

	it("rejects a DNS-name Host", function()
		fresh()
		local response = server._handle_request_for_tests(request("GET", "/todos", { host = "attacker.dev:7283" }))
		eq(status_of(response), 403)
	end)

	it("serves /todos from disk, per request, while allow_v1 holds", function()
		fresh({ sync = { server = { allow_v1 = true } } })
		local response = server._handle_request_for_tests(request("GET", "/todos"))
		eq(status_of(response), 200)
		eq(vim.json.decode(body_of(response))[1].text, "served")

		-- Change the file; the next request must see it. This is the "snapshot
		-- served forever" bug staying dead.
		local file = io.open(config.options.save_path, "w")
		file:write('[{"id":"1_1","text":"changed"}]')
		file:close()
		response = server._handle_request_for_tests(request("GET", "/todos"))
		eq(vim.json.decode(body_of(response))[1].text, "changed")
	end)

	it("requires a device token when allow_v1 is off", function()
		fresh({ sync = { server = { allow_v1 = false } } })
		local response = server._handle_request_for_tests(request("GET", "/todos"))
		eq(status_of(response), 401)
	end)

	it("accepts a paired device when allow_v1 is off", function()
		fresh({ sync = { server = { allow_v1 = false } } })
		local paired = devices.pair(devices.new_pairing_token(), "phone")
		local response = server._handle_request_for_tests(
			request("GET", "/todos", { authorization = "Bearer " .. paired.device_token })
		)
		eq(status_of(response), 200)
	end)

	it("pairs through POST /v2/pair", function()
		fresh()
		local token = devices.new_pairing_token()
		local response = server._handle_request_for_tests(
			request("POST", "/v2/pair", nil, vim.json.encode({ token = token, device_name = "phone" }))
		)
		eq(status_of(response), 200)
		local body = vim.json.decode(body_of(response))
		truthy(body.device_token)
		truthy(devices.authorize("Bearer " .. body.device_token))
	end)

	it("rejects a bad pairing token with 401", function()
		fresh()
		local response = server._handle_request_for_tests(
			request("POST", "/v2/pair", nil, vim.json.encode({ token = "nope", device_name = "phone" }))
		)
		eq(status_of(response), 401)
	end)

	it("rejects a non-JSON pairing body with 400", function()
		fresh()
		local response = server._handle_request_for_tests(request("POST", "/v2/pair", nil, "not json"))
		eq(status_of(response), 400)
	end)

	it("405s a write to a read-only endpoint", function()
		fresh()
		local response = server._handle_request_for_tests(request("POST", "/todos", nil, "[]"))
		eq(status_of(response), 405)
	end)

	it("404s unknown paths", function()
		fresh()
		local response = server._handle_request_for_tests(request("GET", "/secrets"))
		eq(status_of(response), 404)
	end)
end)
