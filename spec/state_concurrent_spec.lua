-- Lost-update protection: two writers of the same file no longer clobber
-- each other, and a closed-window reload picks up external changes.

local config = require("dooing.config")
local state = require("dooing.state")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")

local function todo(id, fields)
	return vim.tbl_extend(
		"force",
		{ id = id, text = "t", category = "", created_at = 1, updated_at = 1, depth = 0 },
		fields or {}
	)
end

local function fresh(todos)
	local path = dir .. "/todos_" .. math.random(1e9) .. ".json"
	local file = io.open(path, "w")
	file:write(vim.json.encode(todos or {}))
	file:close()
	config.setup({ save_path = path })
	state.load_todos()
	return path
end

local function write_externally(path, todos)
	-- Ensure the mtime actually moves even on a fast filesystem.
	local file = io.open(path, "w")
	file:write(vim.json.encode(todos))
	file:close()
	vim.uv.fs_utime(path, os.time() + 5, os.time() + 5)
end

describe("concurrent writers", function()
	it("merges instead of clobbering when the file moved underneath a save", function()
		local path = fresh({ todo("a1", { text = "original" }) })
		-- Another instance adds a todo directly to the file.
		write_externally(path, { todo("a1", { text = "original" }), todo("b1", { text = "from other instance" }) })
		-- This instance adds its own, then saves.
		state.add_todo("from this instance")
		eq(#state.todos, 3, "both additions survived the save")
	end)

	it("keeps the other writer's edit when we did not touch that todo", function()
		local path = fresh({ todo("a1", { text = "original" }), todo("b1", { text = "keep me" }) })
		write_externally(path, { todo("a1", { text = "edited elsewhere", updated_at = 999 }), todo("b1", { text = "keep me" }) })
		state.todos[2].text = "my own edit"
		state.save_todos()
		local by_id = {}
		for _, t in ipairs(state.todos) do
			by_id[t.id] = t
		end
		eq(by_id.a1.text, "edited elsewhere")
		eq(by_id.b1.text, "my own edit")
	end)

	it("reload_if_changed reloads only when the file moved", function()
		local path = fresh({ todo("a1") })
		falsy(state.reload_if_changed(), "nothing moved yet")
		write_externally(path, { todo("a1"), todo("b1", { text = "pushed while closed" }) })
		truthy(state.reload_if_changed())
		eq(#state.todos, 2)
		falsy(state.reload_if_changed(), "second call is a no-op")
	end)
end)
