-- `updated_at` stamping. The rule under test: mutations are detected at save
-- time by diffing against the last load/save, so it does not matter which
-- call site changed a field — including the UI layer's direct writes.

local config = require("dooing.config")
local state = require("dooing.state")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")

local function fresh_file(todos)
	local path = dir .. "/todos_" .. math.random(1e9) .. ".json"
	if todos then
		local file = io.open(path, "w")
		file:write(vim.json.encode(todos))
		file:close()
	end
	config.setup({ save_path = path })
	state.load_todos()
	return path
end

local function read_back(path)
	local file = io.open(path, "r")
	local content = file:read("*a")
	file:close()
	return vim.json.decode(content)
end

describe("state updated_at", function()
	it("stamps new todos at creation", function()
		fresh_file(nil)
		state.add_todo("hello #world")
		truthy(state.todos[1].updated_at)
		eq(state.todos[1].updated_at, state.todos[1].created_at)
	end)

	it("backfills updated_at from created_at on migration", function()
		local path = fresh_file({
			{ id = "1_1", text = "old", done = false, in_progress = false, category = "", created_at = 1000, notes = "", depth = 0 },
		})
		eq(state.todos[1].updated_at, 1000)
		eq(read_back(path)[1].updated_at, 1000)
	end)

	it("does not stamp unchanged todos on load or save", function()
		local path = fresh_file({
			{ id = "1_1", text = "old", done = false, in_progress = false, category = "", created_at = 1000, updated_at = 2000, notes = "", depth = 0 },
		})
		state.save_todos()
		eq(read_back(path)[1].updated_at, 2000, "an untouched todo was re-stamped")
	end)

	it("stamps a direct field write, the way ui/actions.lua edits text", function()
		fresh_file({
			{ id = "1_1", text = "old", done = false, in_progress = false, category = "", created_at = 1000, updated_at = 1000, notes = "", depth = 0 },
		})
		state.todos[1].text = "edited"
		state.save_todos()
		truthy(state.todos[1].updated_at > 1000, "edit was not stamped")
	end)

	it("stamps a toggle but not its neighbours", function()
		fresh_file({
			{ id = "1_1", text = "a", done = false, in_progress = false, category = "", created_at = 1000, updated_at = 1000, notes = "", depth = 0 },
			{ id = "1_2", text = "b", done = false, in_progress = false, category = "", created_at = 1000, updated_at = 1000, notes = "", depth = 0 },
		})
		state.toggle_todo(1)
		truthy(state.todos[1].updated_at > 1000)
		eq(state.todos[2].updated_at, 1000, "an untouched neighbour was stamped")
	end)

	it("writes the todos file 0600", function()
		local path = fresh_file(nil)
		state.add_todo("secret plans")
		local stat = vim.uv.fs_stat(path)
		truthy(stat)
		eq(bit.band(stat.mode, tonumber("777", 8)), tonumber("600", 8))
	end)
end)
