-- The sync exchange, driven directly (no sockets): convergence over two
-- rounds, conflict trailing with restorable losers, and the
-- project-context-loaded safety rule.

local canonical = require("dooing.sync.canonical")
local config = require("dooing.config")
local devices = require("dooing.sync.devices")
local exchange = require("dooing.sync.exchange")
local state = require("dooing.state")
local store = require("dooing.sync.store")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")

local DEVICE = { id = "phone1", name = "test-phone" }

local function fresh(todos)
	store.reset_for_tests()
	store._path_override = dir .. "/sync_" .. math.random(1e9) .. ".json"
	devices.reset_for_tests()
	devices._path_override = dir .. "/devices_" .. math.random(1e9) .. ".json"
	local save_path = dir .. "/todos_" .. math.random(1e9) .. ".json"
	local file = io.open(save_path, "w")
	file:write(vim.json.encode(todos or {}))
	file:close()
	config.setup({ save_path = save_path })
	state.load_todos()
	return save_path
end

local function todo(id, fields)
	return vim.tbl_extend(
		"force",
		{ id = id, text = "t", category = "", created_at = 1, updated_at = 1, depth = 0 },
		fields or {}
	)
end

describe("todos exchange", function()
	it("first exchange unions both sides and both end identical", function()
		fresh({ todo("srv1", { text = "from nvim" }) })
		local response = exchange.todos_exchange(DEVICE, {
			todos = { todo("dev1", { text = "from phone" }) },
			tombstones = {},
		})
		eq(response.revision, 1)
		eq(#response.todos, 2)
		eq(#state.todos, 2, "server adopted the device's todo")
		eq(#response.conflicts, 0)
	end)

	it("a second, unchanged exchange is a no-op that still advances revision", function()
		fresh({ todo("srv1") })
		local first = exchange.todos_exchange(DEVICE, { todos = {}, tombstones = {} })
		-- The device echoes back exactly what it received.
		local second = exchange.todos_exchange(DEVICE, { todos = first.todos, tombstones = {} })
		eq(second.revision, 2)
		eq(#second.conflicts, 0)
		eq(canonical.encode(second.todos), canonical.encode(first.todos), "converged")
	end)

	it("a device deletion propagates to the server after the base exists", function()
		fresh({ todo("srv1") })
		local first = exchange.todos_exchange(DEVICE, { todos = {}, tombstones = {} })
		eq(#first.todos, 1, "device received the todo")
		local second = exchange.todos_exchange(DEVICE, {
			todos = {},
			tombstones = { { id = "srv1", deleted_at = 999 } },
		})
		eq(#second.todos, 0)
		eq(#state.todos, 0, "server deleted it too")
		eq(second.tombstones[1].id, "srv1")
	end)

	it("trails a conflict with the full losing todo, restorable", function()
		fresh({ todo("x1", { text = "original", updated_at = 100 }) })
		exchange.todos_exchange(DEVICE, { todos = {}, tombstones = {} }) -- establish base
		-- Both sides edit: server newer.
		state.todos[1].text = "server version"
		state.save_todos()
		local response = exchange.todos_exchange(DEVICE, {
			todos = { todo("x1", { text = "phone version", updated_at = 150 }) },
			tombstones = {},
		})
		eq(#response.conflicts, 1)
		eq(response.conflicts[1].winner, "local")
		local trailed = store.conflicts()[1]
		eq(trailed.loser_todo.text, "phone version", "the whole losing todo is in the trail")

		local before = #state.todos
		exchange.restore(1)
		eq(#state.todos, before + 1)
		truthy(state.todos[#state.todos].text:find("phone version", 1, true))
	end)

	it("never touches live project state, but still updates the global file", function()
		local global_path = fresh({ todo("srv1", { text = "global todo" }) })
		-- Simulate a project list being loaded.
		local project_path = dir .. "/project_" .. math.random(1e9) .. ".json"
		local file = io.open(project_path, "w")
		file:write(vim.json.encode({ todo("proj1", { text = "project todo" }) }))
		file:close()
		state.load_todos_from_path(project_path)
		eq(state.todos[1].id, "proj1")

		exchange.todos_exchange(DEVICE, {
			todos = { todo("dev1", { text = "from phone" }) },
			tombstones = {},
		})

		eq(state.todos[1].id, "proj1", "live project list untouched")
		eq(#state.todos, 1)
		local read = io.open(global_path, "r")
		local global = vim.json.decode(read:read("*a"))
		read:close()
		eq(#global, 2, "global file gained the device todo")
	end)

	it("rejects a body without a todos array", function()
		fresh({})
		local response, status = exchange.todos_exchange(DEVICE, { nope = true })
		eq(response, nil)
		eq(status, 400)
	end)

	it("on an exact timestamp tie, the device wins (hex ids sort before 'server')", function()
		fresh({ todo("x1", { text = "original", updated_at = 100 }) })
		exchange.todos_exchange(DEVICE, { todos = {}, tombstones = {} })
		state.todos[1].text = "server version"
		state.save_todos()
		local stamped = state.todos[1].updated_at
		local response = exchange.todos_exchange(DEVICE, {
			todos = { todo("x1", { text = "phone version", updated_at = stamped }) },
			tombstones = {},
		})
		eq(response.conflicts[1].winner, "remote")
		eq(state.todos[1].text, "phone version")
	end)
end)
