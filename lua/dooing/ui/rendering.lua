---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Rendering module for UI

local M = {}
local constants = require("dooing.ui.constants")
local highlights = require("dooing.ui.highlights")
local utils = require("dooing.ui.utils")
local state = require("dooing.state")
local config = require("dooing.config")
local calendar = require("dooing.ui.calendar")

-- Main function for todos rendering
function M.render_todos()
	if not constants.buf_id then
		return
	end

	-- Create the buffer
	vim.api.nvim_buf_set_option(constants.buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(constants.buf_id, constants.ns_id, 0, -1)
	local lines = { "" }

	-- Sort todos and get config
	state.sort_todos()
	local lang = calendar and calendar.get_language()
	local formatting = config.options.formatting
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local notes_icon = config.options.notes.icon
	local tmp_notes_icon = ""
	local in_progress_icon = config.options.formatting.in_progress.icon

	-- Loop through all todos and render them using the format
	for _, todo in ipairs(state.todos) do
		if not state.active_filter or todo.text:match("#" .. state.active_filter) then
			-- use the appropriate format based on the todo's status and lang
			if todo.notes == nil or todo.notes == "" then
				tmp_notes_icon = ""
			else
				tmp_notes_icon = notes_icon
			end
			local todo_text = utils.render_todo(todo, formatting, lang, tmp_notes_icon)
			table.insert(lines, "  " .. todo_text)
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
				for tag in line:gmatch("#(%w+)") do
					local tag_pattern = "#" .. tag
					local start_idx = line:find(tag_pattern) - 1
					add_hl(line_nr, start_idx, start_idx + #tag_pattern, "Type")
				end

				-- Due date and overdue highlights
				highlight_pattern(line, line_nr, "%[@%d+/%d+/%d+%]", "Comment")
				highlight_pattern(line, line_nr, "%[OVERDUE%]", "ErrorMsg")

				-- Timestamp highlight
				if config.options.timestamp and config.options.timestamp.enabled then
					local timestamp_pattern = "@[%w%s]+ago"
					local start_idx = line:find(timestamp_pattern)
					if start_idx then
						add_hl(line_nr, start_idx - 1, start_idx + #line:match(timestamp_pattern), "DooingTimestamp")
					end
				end
			end
		elseif line:match("Filtered by:") then
			add_hl(line_nr, 0, -1, "WarningMsg")
		end
	end

	vim.api.nvim_buf_set_option(constants.buf_id, "modifiable", false)
end

return M 