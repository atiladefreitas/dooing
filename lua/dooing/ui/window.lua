---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Window management for UI module

local M = {}
local constants = require("dooing.ui.constants")
local highlights = require("dooing.ui.highlights")
local config = require("dooing.config")

-- Creates and configures the small keys window
local function create_small_keys_window(main_win_pos)
	if not config.options.quick_keys then
		return nil
	end

	local keys = config.options.keymaps
	local small_buf = vim.api.nvim_create_buf(false, true)
	local width = config.options.window.width

	-- Define two separate line arrays for each column
	local lines_1 = {
		"",
		string.format("  %-6s - New todo", keys.new_todo),
		string.format("  %-6s - Toggle todo", keys.toggle_todo),
		string.format("  %-6s - Delete todo", keys.delete_todo),
		string.format("  %-6s - Undo delete", keys.undo_delete),
		string.format("  %-6s - Add due date", keys.add_due_date),
		"",
	}

	local lines_2 = {
		"",
		string.format("  %-6s - Add time", keys.add_time_estimation),
		string.format("  %-6s - Tags", keys.toggle_tags),
		string.format("  %-6s - Search", keys.search_todos),
		string.format("  %-6s - Import", keys.import_todos),
		string.format("  %-6s - Export", keys.export_todos),
		"",
	}

	-- Calculate middle point for even spacing
	local mid_point = math.floor(width / 2)
	local padding = 2

	-- Create combined lines with centered columns
	local lines = {}
	for i = 1, #lines_1 do
		local line1 = lines_1[i] .. string.rep(" ", mid_point - #lines_1[i] - padding)
		local line2 = lines_2[i] or ""
		lines[i] = line1 .. line2
	end

	vim.api.nvim_buf_set_lines(small_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(small_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(small_buf, "buftype", "nofile")

	-- Position it under the main window
	local row = main_win_pos.row + main_win_pos.height + 1

	local small_win = vim.api.nvim_open_win(small_buf, false, {
		relative = "editor",
		row = row,
		col = main_win_pos.col,
		width = width,
		height = #lines,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 45,
		footer = " Quick Keys ",
		footer_pos = "center",
	})

	-- Add highlights
	local ns = vim.api.nvim_create_namespace("dooing_small_keys")

	-- Highlight title
	vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickTitle", 0, 0, -1)

	-- Highlight each key and description in both columns
	for i = 1, #lines - 1 do
		if i > 0 then
			-- Left column
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickKey", i, 2, 3) -- Key
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickDesc", i, 5, mid_point - padding) -- Description

			-- Right column
			local right_key_start = mid_point
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickKey", i, right_key_start + 2, right_key_start + 3) -- Key
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickDesc", i, right_key_start + 5, -1) -- Description
		end
	end

	return small_win
end

-- Creates and configures the main todo window
function M.create_window()
	local ui = vim.api.nvim_list_uis()[1]
	local width = config.options.window.width
	local height = config.options.window.height
	local position = config.options.window.position or "right"
	local padding = 2 -- padding from screen edges

	-- Calculate position based on config
	local col, row
	if position == "right" then
		col = ui.width - width - padding
		row = math.floor((ui.height - height) / 2)
	elseif position == "left" then
		col = padding
		row = math.floor((ui.height - height) / 2)
	elseif position == "top" then
		col = math.floor((ui.width - width) / 2)
		row = padding
	elseif position == "bottom" then
		col = math.floor((ui.width - width) / 2)
		row = ui.height - height - padding
	elseif position == "top-right" then
		col = ui.width - width - padding
		row = padding
	elseif position == "top-left" then
		col = padding
		row = padding
	elseif position == "bottom-right" then
		col = ui.width - width - padding
		row = ui.height - height - padding
	elseif position == "bottom-left" then
		col = padding
		row = ui.height - height - padding
	else -- center or invalid position
		col = math.floor((ui.width - width) / 2)
		row = math.floor((ui.height - height) / 2)
	end

	highlights.setup_highlights()

	constants.buf_id = vim.api.nvim_create_buf(false, true)

	constants.win_id = vim.api.nvim_open_win(constants.buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " to-dos ",
		title_pos = "center",
		footer = " [?] for help ",
		footer_pos = "center",
	})

	-- Create small keys window with main window position
	local small_win = create_small_keys_window({
		row = row,
		col = col,
		width = width,
		height = height,
	})

	-- Close small window when main window is closed
	if small_win then
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(constants.win_id),
			callback = function()
				if vim.api.nvim_win_is_valid(small_win) then
					vim.api.nvim_win_close(small_win, true)
				end
			end,
		})
	end

	vim.api.nvim_win_set_option(constants.win_id, "wrap", true)
	vim.api.nvim_win_set_option(constants.win_id, "linebreak", true)
	vim.api.nvim_win_set_option(constants.win_id, "breakindent", true)
	vim.api.nvim_win_set_option(constants.win_id, "breakindentopt", "shift:2")
	vim.api.nvim_win_set_option(constants.win_id, "showbreak", " ")
end

-- Check if the window is currently open
function M.is_window_open()
    return constants.win_id ~= nil and vim.api.nvim_win_is_valid(constants.win_id)
end

-- Closes all plugin windows
function M.close_window()
	if constants.help_win_id and vim.api.nvim_win_is_valid(constants.help_win_id) then
		vim.api.nvim_win_close(constants.help_win_id, true)
		constants.help_win_id = nil
		constants.help_buf_id = nil
	end

	if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
		vim.api.nvim_win_close(constants.win_id, true)
		constants.win_id = nil
		constants.buf_id = nil
	end
end

return M 