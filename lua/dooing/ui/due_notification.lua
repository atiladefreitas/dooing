---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Due items notification window

local M = {}
local config = require("dooing.config")
local state = require("dooing.state")
local highlights = require("dooing.ui.highlights")
local utils = require("dooing.ui.utils")
local calendar = require("dooing.ui.calendar")

-- Store window and buffer IDs
local due_win_id = nil
local due_buf_id = nil
local ns_id = vim.api.nvim_create_namespace("dooing_due_notification")

-- Get todos that are due today or overdue
local function get_due_todos()
	local due_todos = {}
	local now = os.time()
	local today_start = os.time(os.date("*t", now))
	local today_end = today_start + 86400 -- 24 hours
	
	for i, todo in ipairs(state.todos) do
		if todo.due_at and not todo.done then
			-- Include overdue and due today
			if todo.due_at <= today_end then
				table.insert(due_todos, {
					index = i,
					todo = todo,
					is_overdue = todo.due_at < today_start
				})
			end
		end
	end
	
	-- Sort by due date (earliest first)
	table.sort(due_todos, function(a, b)
		return a.todo.due_at < b.todo.due_at
	end)
	
	return due_todos
end

-- Check if notification window is open
function M.is_notification_open()
	return due_win_id ~= nil and vim.api.nvim_win_is_valid(due_win_id)
end

-- Close notification window
function M.close_notification()
	if due_win_id and vim.api.nvim_win_is_valid(due_win_id) then
		vim.api.nvim_win_close(due_win_id, true)
		due_win_id = nil
		due_buf_id = nil
	end
end

-- Create and display due items notification
function M.show_due_notification()
	-- If window is already open, close it
	if M.is_notification_open() then
		M.close_notification()
		return
	end
	
	-- Get due todos
	local due_todos = get_due_todos()
	
	-- If no due items, show brief notification
	if #due_todos == 0 then
		vim.notify("No items are due today", vim.log.levels.INFO, { title = "Dooing" })
		return
	end
	
	-- Create buffer
	due_buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(due_buf_id, "modifiable", true)
	vim.api.nvim_buf_set_option(due_buf_id, "buftype", "nofile")
	
	-- Prepare lines
	local lines = { "" }
	local line_map = {} -- Map line numbers to todo indices
	
	-- Get formatting config
	local formatting = config.options.formatting
	local lang = calendar.get_language()
	local window_width = config.options.window.width
	local notes_icon = config.options.notes.icon
	
	-- Render each due todo
	for _, item in ipairs(due_todos) do
		local todo = item.todo
		local tmp_notes_icon = (todo.notes and todo.notes ~= "") and notes_icon or ""
		
		-- Calculate indentation for nested tasks
		local depth = todo.depth or 0
		local indent_size = config.options.nested_tasks and config.options.nested_tasks.indent or 2
		local base_indent = "  "
		local nested_indent = string.rep(" ", depth * indent_size)
		local total_indent = base_indent .. nested_indent
		
		-- Adjust window width for indentation
		local effective_width = window_width - vim.fn.strdisplaywidth(total_indent)
		
		-- Render todo using existing utility
		local todo_text = utils.render_todo(todo, formatting, lang, tmp_notes_icon, effective_width)
		
		table.insert(lines, total_indent .. todo_text)
		line_map[#lines] = item.index
	end
	
	table.insert(lines, "")
	
	-- Set buffer content
	vim.api.nvim_buf_set_lines(due_buf_id, 0, -1, false, lines)
	
	-- Calculate window dimensions
	local ui = vim.api.nvim_list_uis()[1]
	local width = config.options.window.width
	local height = math.min(#lines + 2, math.floor(ui.height * 0.6))
	local position = config.options.window.position or "center"
	local padding = 2
	
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
	else -- center
		col = math.floor((ui.width - width) / 2)
		row = math.floor((ui.height - height) / 2)
	end
	
	-- Setup highlights
	highlights.setup_highlights()
	
	-- Create window
	local overdue_count = 0
	for _, item in ipairs(due_todos) do
		if item.is_overdue then
			overdue_count = overdue_count + 1
		end
	end
	
	local title = string.format(" %d item%s due today ", #due_todos, #due_todos == 1 and "" or "s")
	if overdue_count > 0 then
		title = string.format(" %d overdue, %d due today ", overdue_count, #due_todos - overdue_count)
	end
	
	due_win_id = vim.api.nvim_open_win(due_buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = config.options.window.border,
		title = title,
		title_pos = "center",
		footer = " [q] close | [<CR>] jump to todo ",
		footer_pos = "center",
		zindex = 50,
	})
	
	vim.api.nvim_win_set_option(due_win_id, "wrap", true)
	vim.api.nvim_win_set_option(due_win_id, "linebreak", true)
	vim.api.nvim_win_set_option(due_win_id, "breakindent", true)
	
	-- Apply highlights
	local done_icon = formatting.done.icon
	local pending_icon = formatting.pending.icon
	local in_progress_icon = formatting.in_progress.icon
	
	for i, line in ipairs(lines) do
		local line_nr = i - 1
		if line:match("%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
			local todo_index = line_map[i]
			if todo_index then
				local todo = state.todos[todo_index]
				
				if todo then
					-- Base todo highlight
					if todo.done then
						vim.api.nvim_buf_add_highlight(due_buf_id, ns_id, "DooingDone", line_nr, 0, -1)
					else
						local hl_group = highlights.get_priority_highlight(todo.priorities)
						vim.api.nvim_buf_add_highlight(due_buf_id, ns_id, hl_group, line_nr, 0, -1)
					end
					
					-- Tags highlight
					for tag in line:gmatch("#(%w+)") do
						local tag_pattern = "#" .. tag
						local start_idx = line:find(tag_pattern)
						if start_idx then
							vim.api.nvim_buf_add_highlight(due_buf_id, ns_id, "Type", line_nr, start_idx - 1, start_idx + #tag_pattern - 1)
						end
					end
					
					-- Due date highlights
					local due_date_patterns = {
						"%[!.-%d+.-%d+.-%d+%]", -- Overdue with !
						"%[.-%d+.-%d+.-%d+%]",   -- Normal date
					}
					for _, pattern in ipairs(due_date_patterns) do
						local start_idx = line:find(pattern)
						if start_idx then
							local match = line:match(pattern)
							if match:find("^%[!") then
								vim.api.nvim_buf_add_highlight(due_buf_id, ns_id, "ErrorMsg", line_nr, start_idx - 1, start_idx + #match - 1)
							else
								vim.api.nvim_buf_add_highlight(due_buf_id, ns_id, "DooingTimestamp", line_nr, start_idx - 1, start_idx + #match - 1)
							end
						end
					end
					
					-- Time estimation highlight
					local ect_pattern = "%[≈ [%d%.]+[mhdw]%]"
					local start_idx = line:find(ect_pattern)
					if start_idx then
						local match = line:match(ect_pattern)
						vim.api.nvim_buf_add_highlight(due_buf_id, ns_id, "DooingTimestamp", line_nr, start_idx - 1, start_idx + #match - 1)
					end
					
					-- Timestamp highlight
					if config.options.timestamp and config.options.timestamp.enabled then
						local timestamp_pattern = "@[%w%s]+ago"
						local start_idx = line:find(timestamp_pattern)
						if start_idx then
							local match = line:match(timestamp_pattern)
							vim.api.nvim_buf_add_highlight(due_buf_id, ns_id, "DooingTimestamp", line_nr, start_idx - 1, start_idx + #match - 1)
						end
					end
				end
			end
		end
	end
	
	vim.api.nvim_buf_set_option(due_buf_id, "modifiable", false)
	
	-- Keymaps
	local opts = { buffer = due_buf_id, nowait = true }
	
	-- Close window
	vim.keymap.set("n", "q", function()
		M.close_notification()
	end, opts)
	
	vim.keymap.set("n", "<Esc>", function()
		M.close_notification()
	end, opts)
	
	-- Jump to todo in main window
	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(due_win_id)
		local todo_index = line_map[cursor[1]]
		
		if todo_index then
			M.close_notification()
			
			-- Open the appropriate todo window (global or project)
			local ui_module = require("dooing.ui")
			if not ui_module.is_window_open() then
				-- If no window is open, open the appropriate one based on current context
				if state.current_context == "global" then
					require("dooing").open_global_todo()
				else
					require("dooing").open_project_todo()
				end
			end
			
			-- Jump to the todo
			local constants = require("dooing.ui.constants")
			if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
				vim.api.nvim_set_current_win(constants.win_id)
				
				-- Calculate line position (accounting for filter header if present)
				local line_pos = todo_index + (state.active_filter and 2 or 0)
				vim.api.nvim_win_set_cursor(constants.win_id, { line_pos, 0 })
			end
		end
	end, opts)
	
	-- Auto-close on buffer leave
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = due_buf_id,
		callback = function()
			M.close_notification()
		end,
		once = true,
	})
end

return M
