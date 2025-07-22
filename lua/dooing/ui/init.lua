---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- UI Module for Dooing Plugin
-- Main entry point that coordinates all UI functionality

---@class DoingUI
---@field toggle_todo_window function
---@field render_todos function
---@field close_window function
---@field new_todo function
---@field toggle_todo function
---@field delete_todo function
---@field delete_completed function
local M = {}

-- Load all modules
local constants = require("dooing.ui.constants")
local window = require("dooing.ui.window")
local rendering = require("dooing.ui.rendering")
local actions = require("dooing.ui.actions")
local keymaps = require("dooing.ui.keymaps")

-- Re-export utility functions that are used externally
M.parse_time_estimation = require("dooing.ui.utils").parse_time_estimation

-- Main public interface functions

-- Toggles the main todo window visibility
function M.toggle_todo_window()
	if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
		M.close_window()
	else
		window.create_window()
		keymaps.setup_keymaps()
		M.render_todos()
	end
end

-- Main function for todos rendering
function M.render_todos()
	rendering.render_todos()
end

-- Closes all plugin windows
function M.close_window()
	window.close_window()
end

-- Check if the window is currently open
function M.is_window_open()
    return window.is_window_open()
end

-- Function to reload todos and refresh UI if window is open
function M.reload_todos()
    actions.reload_todos()
end

-- Creates a new todo item
function M.new_todo()
	actions.new_todo()
end

-- Toggles the completion status of the current todo
function M.toggle_todo()
	actions.toggle_todo()
end

-- Deletes the current todo item
function M.delete_todo()
	actions.delete_todo()
end

-- Deletes all completed todos
function M.delete_completed()
	actions.delete_completed()
end

-- Delete all duplicated todos
function M.remove_duplicates()
	actions.remove_duplicates()
end

-- Open global todo list
function M.open_global_todo()
	require("dooing").open_global_todo()
end

-- Open project-specific todo list
function M.open_project_todo()
	require("dooing").open_project_todo()
end

return M 