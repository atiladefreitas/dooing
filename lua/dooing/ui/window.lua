---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Window management for UI module

local M = {}
local constants = require("dooing.ui.constants")
local highlights = require("dooing.ui.highlights")
local config = require("dooing.config")
local state = require("dooing.state")

-- Quick keys panel height (fixed: 8 lines with border = 10 total)
local QUICK_KEYS_CONTENT_LINES = 8
local QUICK_KEYS_BORDER_HEIGHT = 2 -- top + bottom border

-- Returns the total height of the quick keys panel (including border), or 0 if disabled
local function get_quick_keys_height()
	if not config.options.quick_keys then
		return 0
	end
	return QUICK_KEYS_CONTENT_LINES + QUICK_KEYS_BORDER_HEIGHT
end

-- Returns the height of the tabline (0 or 1)
local function get_tabline_height()
	local showtabline = vim.o.showtabline
	if showtabline == 2 then
		return 1
	elseif showtabline == 1 and #vim.api.nvim_list_tabpages() > 1 then
		return 1
	end
	return 0
end

-- Returns the height of the statusline + cmdline
local function get_bottom_offset()
	local laststatus = vim.o.laststatus
	local cmdheight = vim.o.cmdheight
	local statusline = 0
	if laststatus == 2 or laststatus == 3 then
		statusline = 1
	elseif laststatus == 1 and #vim.api.nvim_list_wins() > 1 then
		statusline = 1
	end
	return statusline + cmdheight
end

-- Border character sets for different styles
-- Format: { top-left, top, top-right, right, bottom-right, bottom, bottom-left, left }
local BORDER_CHARS = {
	rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
	single = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
	double = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
	solid = { "▛", "▀", "▜", "▐", "▟", "▄", "▙", "▌" },
}

-- T-junction characters for separator line (connects left/right borders)
local SEPARATOR_CHARS = {
	rounded = { left = "├", line = "─", right = "┤" },
	single = { left = "├", line = "─", right = "┤" },
	double = { left = "╠", line = "═", right = "╣" },
	solid = { left = "▙", line = "▄", right = "▟" },
}

-- Get border array for a given style, or return the style if it's already an array
local function get_border_chars(style)
	if type(style) == "table" then
		return style
	end
	return BORDER_CHARS[style] or BORDER_CHARS.rounded
end

-- Get separator chars for a given style
local function get_separator_chars(style)
	if type(style) == "string" then
		return SEPARATOR_CHARS[style] or SEPARATOR_CHARS.rounded
	end
	-- For custom border arrays, fall back to rounded separators
	return SEPARATOR_CHARS.rounded
end

-- Create border array for main window when fused (separator on connecting edge)
local function get_main_border_fused(style, quick_panel_above)
	local chars = get_border_chars(style)
	local sep = get_separator_chars(style)
	
	if quick_panel_above then
		-- Quick panel is above, so main's TOP edge is the separator
		return { sep.left, sep.line, sep.right, chars[4], chars[5], chars[6], chars[7], chars[8] }
	else
		-- Quick panel is below, so main's BOTTOM edge is the separator
		return { chars[1], chars[2], chars[3], chars[4], sep.right, sep.line, sep.left, chars[8] }
	end
end

-- Create border array for quick keys panel when fused (no border on connecting edge)
local function get_quick_border_fused(style, quick_panel_above)
	local chars = get_border_chars(style)
	
	if quick_panel_above then
		-- Quick panel is above main, so quick's BOTTOM edge connects (use spaces)
		return { chars[1], chars[2], chars[3], chars[4], " ", " ", " ", chars[8] }
	else
		-- Quick panel is below main, so quick's TOP edge connects (use spaces)
		return { " ", " ", " ", chars[4], chars[5], chars[6], chars[7], chars[8] }
	end
end

-- Creates and configures the small keys window at the specified position
local function create_small_keys_window(row, col, width, border)
	if not config.options.quick_keys then
		return nil
	end

	local keys = config.options.keymaps
	local small_buf = vim.api.nvim_create_buf(false, true)

	-- Define two separate line arrays for each column
	local fmt = " %10s - %s"
	local lines_1 = {
		"",
		string.format(fmt, keys.new_todo, "New todo"),
		string.format(fmt, keys.create_nested_task, "Nested todo"),
		string.format(fmt, keys.toggle_todo, "Toggle todo"),
		string.format(fmt, keys.delete_todo, "Delete todo"),
		string.format(fmt, keys.undo_delete, "Undo delete"),
		string.format(fmt, keys.add_due_date, "Add due date"),
		"",
	}

	local lines_2 = {
		"",
		string.format(fmt, keys.add_time_estimation, "Add time"),
		string.format(fmt, keys.toggle_tags, "Tags"),
		string.format(fmt, keys.search_todos, "Search"),
		string.format(fmt, keys.import_todos, "Import"),
		string.format(fmt, keys.export_todos, "Export"),
		"",
	}

	-- Calculate middle point for even spacing
	local mid_point = math.floor(width / 2)
	local inner_padding = 2

	-- Create combined lines with centered columns
	local lines = {}
	for i = 1, #lines_1 do
		local line1 = lines_1[i] .. string.rep(" ", mid_point - #lines_1[i] - inner_padding)
		local line2 = lines_2[i] or ""
		lines[i] = line1 .. line2
	end

	vim.api.nvim_buf_set_lines(small_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(small_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(small_buf, "buftype", "nofile")

	local small_win = vim.api.nvim_open_win(small_buf, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = #lines,
		style = "minimal",
		border = border,
		focusable = false,
		zindex = config.options.window.zindex,
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
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickDesc", i, 5, mid_point - inner_padding) -- Description

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
	-- Save the window the user was in before opening dooing
	-- Only save if we're not already inside a dooing window (e.g. toggling global↔project)
	if constants.win_id == nil or not vim.api.nvim_win_is_valid(constants.win_id) then
		constants.previous_win = vim.api.nvim_get_current_win()
	end

	local ui = vim.api.nvim_list_uis()[1]
	local width = config.options.window.width
	local height = config.options.window.height
	local main_border_height = 2 -- top + bottom border
	local position = config.options.window.position or "right"

	local quick_keys_height = get_quick_keys_height()
	local is_top_position = vim.tbl_contains({ "top", "top-left", "top-right" }, position)
	local is_bottom_position = vim.tbl_contains({ "bottom", "bottom-left", "bottom-right" }, position)
	local has_quick_keys = quick_keys_height > 0

	-- Calculate vertical padding based on position
	local top_padding = is_top_position and get_tabline_height() or 0
	local bottom_padding = is_bottom_position and get_bottom_offset() or 0

	-- Calculate column based on position
	local col
	if vim.tbl_contains({ "right", "top-right", "bottom-right" }, position) then
		col = ui.width - width
	elseif vim.tbl_contains({ "left", "top-left", "bottom-left" }, position) then
		col = 0
	else -- center, top, bottom
		col = math.floor((ui.width - width) / 2)
	end

	-- Calculate rows for main window and quick keys panel
	-- When fused, we use gap = -1 to overlap the borders
	local main_row, quick_row
	local fused_gap = -1 -- Overlap borders by 1 row for fused appearance

	if not has_quick_keys then
		-- No quick keys panel, use original positioning logic
		if is_top_position then
			main_row = top_padding
		elseif is_bottom_position then
			main_row = ui.height - height - main_border_height - bottom_padding
		else -- left, right, center
			main_row = math.floor((ui.height - height - main_border_height) / 2)
		end
		quick_row = nil
	elseif is_top_position then
		-- Quick panel at top, main window below (fused)
		quick_row = top_padding
		main_row = top_padding + quick_keys_height + fused_gap
	else
		-- Main window above, quick panel below (fused)
		-- Account for fused_gap in total height calculation
		local total_height = height + main_border_height + quick_keys_height + fused_gap

		if is_bottom_position then
			-- Anchor quick panel at bottom edge
			quick_row = ui.height - quick_keys_height - bottom_padding
			main_row = quick_row + fused_gap - height
		else -- left, right, center
			-- Center the combined stack vertically
			local stack_start = math.floor((ui.height - total_height) / 2)
			main_row = stack_start
			quick_row = stack_start + height + main_border_height + fused_gap
		end
	end

	-- Determine borders (fused or normal)
	local main_border = config.options.window.border
	local quick_border = config.options.window.border

	if has_quick_keys then
		-- Use fused borders for connected appearance
		local border_style = config.options.window.border
		local quick_panel_above = is_top_position
		main_border = get_main_border_fused(border_style, quick_panel_above)
		quick_border = get_quick_border_fused(border_style, quick_panel_above)
	end

	highlights.setup_highlights()

	constants.buf_id = vim.api.nvim_create_buf(false, true)

	constants.win_id = vim.api.nvim_open_win(constants.buf_id, true, {
		relative = "editor",
		row = main_row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = main_border,
		zindex = config.options.window.zindex,
		title = state.get_window_title(),
		title_pos = "center",
		footer = " [?] for help ",
		footer_pos = "center",
	})

	-- Create quick keys window if enabled
	local small_win = nil
	if quick_row then
		small_win = create_small_keys_window(quick_row, col, width, quick_border)
	end

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
	
	-- Set up folding for nested tasks
	vim.api.nvim_win_set_option(constants.win_id, "foldmethod", "indent")
	vim.api.nvim_win_set_option(constants.win_id, "foldlevel", 99) -- Start with all folds open
	vim.api.nvim_win_set_option(constants.win_id, "foldenable", true)
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

	-- Restore focus to the window the user was in before opening dooing
	if constants.previous_win and vim.api.nvim_win_is_valid(constants.previous_win) then
		vim.api.nvim_set_current_win(constants.previous_win)
	end
	constants.previous_win = nil
end

-- Update window title without recreating the window
function M.update_window_title()
	if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
		vim.api.nvim_win_set_config(constants.win_id, {
			title = state.get_window_title(),
		})
	end
end

return M 
