---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Keymaps setup for UI module

local M = {}
local constants = require("dooing.ui.constants")
local config = require("dooing.config")
local actions = require("dooing.ui.actions")
local components = require("dooing.ui.components")
local state = require("dooing.state")
local server = require("dooing.server")

-- Setup keymaps for the main window
function M.setup_keymaps()
	-- Helper function to setup keymap
	local function setup_keymap(key_option, callback)
		if config.options.keymaps[key_option] then
			vim.keymap.set("n", config.options.keymaps[key_option], callback, { buffer = constants.buf_id, nowait = true })
		end
	end

	-- Server functionality
	setup_keymap("share_todos", function()
		server.start_qr_server()
	end)

	-- Main actions
	setup_keymap("new_todo", actions.new_todo)
	setup_keymap("toggle_todo", actions.toggle_todo)
	setup_keymap("delete_todo", actions.delete_todo)
	setup_keymap("delete_completed", actions.delete_completed)
	setup_keymap("undo_delete", actions.undo_delete)
	setup_keymap("refresh_todos", actions.reload_todos)

	-- Window and view management
	setup_keymap("toggle_help", components.create_help_window)
	setup_keymap("toggle_tags", components.create_tag_window)
	setup_keymap("clear_filter", function()
		state.set_filter(nil)
		local rendering = require("dooing.ui.rendering")
		rendering.render_todos()
	end)

	-- Todo editing and management
	setup_keymap("edit_todo", actions.edit_todo)
	setup_keymap("edit_priorities", actions.edit_priorities)
	setup_keymap("add_due_date", actions.add_due_date)
	setup_keymap("remove_due_date", actions.remove_due_date)
	setup_keymap("add_time_estimation", actions.add_time_estimation)
	setup_keymap("remove_time_estimation", actions.remove_time_estimation)
	setup_keymap("open_todo_scratchpad", components.open_todo_scratchpad)

	-- Import/Export functionality
	setup_keymap("import_todos", actions.prompt_import)
	setup_keymap("export_todos", actions.prompt_export)
	setup_keymap("remove_duplicates", actions.remove_duplicates)
	setup_keymap("search_todos", components.create_search_window)

	-- Window close
	setup_keymap("close_window", function()
		local window = require("dooing.ui.window")
		window.close_window()
	end)
end

return M 