-- :DooingSyncRevoke resolution: number, id, unique name; ambiguity refused.

local config = require("dooing.config")
local devices = require("dooing.sync.devices")
local exchange = require("dooing.sync.exchange")
local store = require("dooing.sync.store")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")

local function fresh()
	devices.reset_for_tests()
	devices._path_override = dir .. "/devices_" .. math.random(1e9) .. ".json"
	store.reset_for_tests()
	store._path_override = dir .. "/sync_" .. math.random(1e9) .. ".json"
	config.setup({ save_path = dir .. "/todos_" .. math.random(1e9) .. ".json" })
end

local function pair(name)
	return devices.pair(devices.new_pairing_token(), name)
end

describe("sync revoke", function()
	it("revokes by list number and clears the device's sync state", function()
		fresh()
		local a = pair("phone-a")
		pair("phone-b")
		store.commit_exchange(a.device_id, { x = { id = "x" } }, {}, 1000)
		truthy(exchange.revoke("1"))
		eq(#devices.devices(), 1)
		eq(devices.devices()[1].name, "phone-b")
		eq(store.device(a.device_id).revision, 0, "sync state gone, recreated empty")
	end)

	it("revokes by id", function()
		fresh()
		local a = pair("phone-a")
		truthy(exchange.revoke(a.device_id))
		eq(#devices.devices(), 0)
	end)

	it("revokes by name only when the name is unique", function()
		fresh()
		pair("redmi")
		pair("redmi")
		pair("pixel")
		local ok, err = exchange.revoke("redmi")
		falsy(ok)
		truthy(err:find("2 devices"), "ambiguous name refused: " .. tostring(err))
		truthy(exchange.revoke("pixel"))
		eq(#devices.devices(), 2)
	end)

	it("refuses junk with a pointer to the status window", function()
		fresh()
		pair("phone")
		local ok, err = exchange.revoke("nonsense")
		falsy(ok)
		truthy(err:find("no paired device"))
		local ok2 = exchange.revoke("9")
		falsy(ok2)
	end)

	it("a revoked device's list number shifts, ids do not", function()
		fresh()
		pair("one")
		local b = pair("two")
		exchange.revoke("1")
		-- "two" is now number 1; its id still works regardless.
		truthy(exchange.revoke(b.device_id))
		eq(#devices.devices(), 0)
	end)
end)
