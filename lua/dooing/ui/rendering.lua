---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Rendering module for UI

local M = {}
local constants = require("dooing.ui.constants")
local highlights = require("dooing.ui.highlights")
local utils = require("dooing.ui.utils")
local state = require("dooing.state")
local config = require("dooing.config")
local calendar = require("dooing.ui.calendar")

-- Save the current fold state
local function save_fold_state()
	if not constants.win_id or not vim.api.nvim_win_is_valid(constants.win_id) then
		return {}
	end
	
	local ok, result = pcall(function()
		local folds = {}
		local line_count = vim.api.nvim_buf_line_count(constants.buf_id)
		
		-- Save the current window to restore later
		local current_win = vim.api.nvim_get_current_win()
		vim.api.nvim_set_current_win(constants.win_id)
		
		-- The map published by the previous render describes the buffer as it
		-- currently stands on screen
		local line_to_todo = constants.line_to_todo or {}

		-- Check which todos have closed folds
		for line = 1, line_count do
			local fold_level = vim.fn.foldlevel(line)
			local is_closed = vim.fn.foldclosed(line) > 0
			local todo_index = line_to_todo[line]
			
			if fold_level > 0 and is_closed and todo_index then
				local todo = state.todos[todo_index]
				if todo and todo.id then
					folds[todo.id] = true
				end
			end
		end
		
		-- Restore the previous window
		if vim.api.nvim_win_is_valid(current_win) then
			vim.api.nvim_set_current_win(current_win)
		end
		
		return folds
	end)
	
	return ok and result or {}
end

-- Restore the fold state
local function restore_fold_state(folds)
	if not constants.win_id or not vim.api.nvim_win_is_valid(constants.win_id) or not folds or vim.tbl_isempty(folds) then
		return
	end
	
	pcall(function()
		-- Save the current window to restore later
		local current_win = vim.api.nvim_get_current_win()
		vim.api.nvim_set_current_win(constants.win_id)
		
		-- First, open all folds
		vim.cmd("normal! zR")
		
		-- Where each todo now lives. Uses the primary-line map rather than
		-- inverting `line_to_todo`, whose rows can span several lines.
		local todo_to_line = {}
		for todo_index, line in pairs(constants.primary_lines or {}) do
			local todo = state.todos[todo_index]
			if todo and todo.id then
				todo_to_line[todo.id] = line
			end
		end

		-- Close folds for todos that were previously folded
		for todo_id, _ in pairs(folds) do
			local line = todo_to_line[todo_id]
			if line and line <= vim.api.nvim_buf_line_count(constants.buf_id) then
				vim.api.nvim_win_set_cursor(constants.win_id, {line, 0})
				if vim.fn.foldlevel(line) > 0 then
					vim.cmd("normal! zc")
				end
			end
		end
		
		-- Restore the previous window
		if vim.api.nvim_win_is_valid(current_win) then
			vim.api.nvim_set_current_win(current_win)
		end
	end)
end

-- Renders the list using the modern style. Lines and highlight ranges are both
-- produced by `ui/modern.lua`, so nothing has to be re-matched here.
local function render_modern()
	local modern = require("dooing.ui.modern")
	local result = modern.build(state.todos, state.active_filter)

	vim.api.nvim_buf_set_lines(constants.buf_id, 0, -1, false, result.lines)
	constants.line_to_todo = result.line_to_todo
	constants.primary_lines = result.primary_lines
	constants.fold_levels = result.fold_levels

	-- Fold levels changed, so any cached fold computation is stale
	if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
		vim.api.nvim_win_call(constants.win_id, function()
			vim.cmd("silent! normal! zx")
		end)
	end

	for _, span in ipairs(result.spans) do
		vim.api.nvim_buf_add_highlight(
			constants.buf_id,
			constants.ns_id,
			span.hl_group,
			span.line,
			span.start_col,
			span.end_col
		)
	end
end

-- First buffer line belonging to a todo, or nil when the list is empty
local function first_todo_line()
	local first
	for line in pairs(constants.line_to_todo or {}) do
		if not first or line < first then
			first = line
		end
	end
	return first
end

-- Locks the buffer again and restores folds, cursor and window chrome.
-- With `focus_first`, the cursor is parked on the first todo instead of being
-- restored -- used when a list is opened or swapped, where the previous cursor
-- position is meaningless.
local function finish_render(fold_state, cursor_pos, focus_first)
	vim.api.nvim_buf_set_option(constants.buf_id, "modifiable", false)

	-- The title carries the progress bar, so it has to be refreshed whenever
	-- the counts can have changed
	if config.modern_feature("progress") then
		require("dooing.ui.window").update_window_title()
	end

	-- Restore fold state and cursor position after rendering (with a small delay to ensure buffer is ready)
	vim.defer_fn(function()
		restore_fold_state(fold_state)

		local target = cursor_pos
		if focus_first then
			local line = first_todo_line()
			target = line and { line, 0 } or nil
		end

		-- Restore (or set) the cursor position
		if target and constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
			local current_win = vim.api.nvim_get_current_win()
			vim.api.nvim_set_current_win(constants.win_id)
			local line_count = vim.api.nvim_buf_line_count(constants.buf_id)
			-- Ensure cursor position is valid
			if target[1] <= line_count then
				pcall(vim.api.nvim_win_set_cursor, constants.win_id, target)
			end
			if vim.api.nvim_win_is_valid(current_win) then
				vim.api.nvim_set_current_win(current_win)
			end
		end
	end, 15)
end

-- Main function for todos rendering
---@param opts table|nil { focus_first = boolean } park the cursor on the first todo
function M.render_todos(opts)
	local focus_first = opts and opts.focus_first or false

	if not constants.buf_id then
		return
	end

	-- Save fold state and cursor position before rendering
	local fold_state = save_fold_state()
	local cursor_pos = nil
	if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
		local current_win = vim.api.nvim_get_current_win()
		vim.api.nvim_set_current_win(constants.win_id)
		cursor_pos = vim.api.nvim_win_get_cursor(constants.win_id)
		if vim.api.nvim_win_is_valid(current_win) then
			vim.api.nvim_set_current_win(current_win)
		end
	end

	-- Create the buffer
	vim.api.nvim_buf_set_option(constants.buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(constants.buf_id, constants.ns_id, 0, -1)
	-- Sort todos and get config
	state.sort_todos()

	if config.is_modern() then
		render_modern()
		finish_render(fold_state, cursor_pos, focus_first)
		return
	end

	local lines = { "" }
	local lang = calendar and calendar.get_language()
	local formatting = config.options.formatting
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local notes_icon = config.options.notes.icon
	local tmp_notes_icon = ""
	local in_progress_icon = config.options.formatting.in_progress.icon

	-- Get window width for timestamp positioning
	local window_width = config.get_window_dimensions().width
	
	-- Loop through all todos and render them using the format
	for _, todo in ipairs(state.todos) do
		if not state.active_filter or utils.has_tag(todo.text, state.active_filter) then
			-- use the appropriate format based on the todo's status and lang
			if todo.notes == nil or todo.notes == "" then
				tmp_notes_icon = ""
			else
				tmp_notes_icon = notes_icon
			end
			
			-- Calculate indentation based on depth
			local depth = todo.depth or 0
			local indent_size = config.options.nested_tasks and config.options.nested_tasks.indent or 2
			local base_indent = "  " -- Base indentation for all todos
			local nested_indent = string.rep(" ", depth * indent_size)
			local total_indent = base_indent .. nested_indent
			
			-- Adjust window width for indentation
			local effective_width = window_width - vim.fn.strdisplaywidth(total_indent)
			
			local todo_text = utils.render_todo(todo, formatting, lang, tmp_notes_icon, effective_width)
			
			table.insert(lines, total_indent .. todo_text)
		end
	end

	if state.active_filter then
		table.insert(lines, 1, "")
		table.insert(lines, 1, "  Filtered by: #" .. state.active_filter)
	end

	table.insert(lines, "")

	for i, line in ipairs(lines) do
		lines[i] = line:gsub("\n", " ")
	end
	vim.api.nvim_buf_set_lines(constants.buf_id, 0, -1, false, lines)

	-- Publish the line -> todo mapping for the classic layout, matching the
	-- positional arithmetic this layout has always used
	local classic_map = {}
	local classic_primary = {}
	local line_offset = state.active_filter and 3 or 1
	local visible_count = 0
	for index, todo in ipairs(state.todos) do
		if not state.active_filter or utils.has_tag(todo.text, state.active_filter) then
			visible_count = visible_count + 1
			classic_map[line_offset + visible_count] = index
			classic_primary[index] = line_offset + visible_count
		end
	end
	constants.line_to_todo = classic_map
	-- One line per todo in the classic layout, so the two maps agree
	constants.primary_lines = classic_primary

	-- Helper function to add highlight
	local function add_hl(line_nr, start_col, end_col, hl_group)
		vim.api.nvim_buf_add_highlight(constants.buf_id, constants.ns_id, hl_group, line_nr, start_col, end_col)
	end

	-- Helper function to find pattern and highlight
	local function highlight_pattern(line, line_nr, pattern, hl_group)
		local start_idx = line:find(pattern)
		if start_idx then
			add_hl(line_nr, start_idx - 1, -1, hl_group)
		end
	end

	for i, line in ipairs(lines) do
		local line_nr = i - 1
		if line:match("%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
			local todo_index = i - (state.active_filter and 3 or 1)
			local todo = state.todos[todo_index]

			if todo then
				-- Base todo highlight
				if todo.done then
					add_hl(line_nr, 0, -1, "DooingDone")
				else
					-- Get highlight based on priorities
					local hl_group = highlights.get_priority_highlight(todo.priorities)
					add_hl(line_nr, 0, -1, hl_group)
				end

				-- Tags highlight
				for tag in line:gmatch("#([%w_%-/]+)") do
					local tag_pattern = "#" .. tag
					local start_idx = line:find("#" .. utils.escape_pattern(tag)) - 1
					add_hl(line_nr, start_idx, start_idx + #tag_pattern, "Type")
				end

				-- Due date highlights
				-- Match various due date formats: [icon date], [date], [@ date]
				local due_date_patterns = {
					"%[!.-%d+.-%d+.-%d+%]", -- Overdue date pattern with ! prefix
					"%[.-%d+.-%d+.-%d+%]", -- General date pattern with brackets
					"%[@ .-%]" -- @ format pattern
				}
				for _, pattern in ipairs(due_date_patterns) do
					local start_idx = line:find(pattern)
					if start_idx then
						local match = line:match(pattern)
						if match:find("^%[!") then
							-- Overdue date - highlight in red
							add_hl(line_nr, start_idx - 1, start_idx + #match - 1, "ErrorMsg")
						else
							-- Normal date - highlight in grey
							add_hl(line_nr, start_idx - 1, start_idx + #match - 1, "DooingTimestamp")
						end
					end
				end

				-- Time estimation highlight
				local ect_pattern = "%[≈ [%d%.]+[mhdw]%]"
				local start_idx = line:find(ect_pattern)
				if start_idx then
					local match = line:match(ect_pattern)
					add_hl(line_nr, start_idx - 1, start_idx + #match - 1, "DooingTimestamp")
				end

				-- Timestamp highlight (now positioned at the right)
				if config.options.timestamp and config.options.timestamp.enabled then
					local timestamp_pattern = "@[%w%s]+ago"
					local start_idx = line:find(timestamp_pattern)
					if start_idx then
						local match = line:match(timestamp_pattern)
						add_hl(line_nr, start_idx - 1, start_idx + #match - 1, "DooingTimestamp")
					end
				end
			end
		elseif line:match("Filtered by:") then
			add_hl(line_nr, 0, -1, "WarningMsg")
		end
	end

	finish_render(fold_state, cursor_pos, focus_first)
end

return M

