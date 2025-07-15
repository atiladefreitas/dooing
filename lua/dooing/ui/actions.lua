---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Actions module for todo CRUD operations

local M = {}
local constants = require("dooing.ui.constants")
local utils = require("dooing.ui.utils")
local state = require("dooing.state")
local config = require("dooing.config")
local calendar = require("dooing.ui.calendar")
local server = require("dooing.server")

-- Handles editing of existing todos
function M.edit_todo()
	local cursor = vim.api.nvim_win_get_cursor(constants.win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(constants.buf_id, todo_index, todo_index + 1, false)[1]

	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local in_progress_icon = config.options.formatting.in_progress.icon

	if line_content:match("%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						todo_index = i
						break
					end
				end
			end
		end

		vim.ui.input({ zindex = 300, prompt = "Edit to-do: ", default = state.todos[todo_index].text }, function(input)
			if input and input ~= "" then
				state.todos[todo_index].text = input
				state.save_todos()
				local rendering = require("dooing.ui.rendering")
				rendering.render_todos()
			end
		end)
	end
end

-- Handles editing priorities
function M.edit_priorities()
	local cursor = vim.api.nvim_win_get_cursor(constants.win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(constants.buf_id, todo_index, todo_index + 1, false)[1]
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local in_progress_icon = config.options.formatting.in_progress.icon

	if line_content:match("%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						todo_index = i
						break
					end
				end
			end
		end

		-- Check if priorities are configured
		if config.options.priorities and #config.options.priorities > 0 then
			local priorities = config.options.priorities
			local priority_options = {}
			local selected_priorities = {}
			local current_todo = state.todos[todo_index]

			-- Pre-select existing priorities
			for i, priority in ipairs(priorities) do
				local is_selected = false
				if current_todo.priorities then
					for _, existing_priority in ipairs(current_todo.priorities) do
						if existing_priority == priority.name then
							is_selected = true
							selected_priorities[i] = true
							break
						end
					end
				end
				priority_options[i] = string.format("[%s] %s", is_selected and "x" or " ", priority.name)
			end

			-- Create buffer for priority selection
			local select_buf = vim.api.nvim_create_buf(false, true)
			local ui = vim.api.nvim_list_uis()[1]
			local width = 40
			local height = #priority_options + 2
			local row = math.floor((ui.height - height) / 2)
			local col = math.floor((ui.width - width) / 2)

			-- Store keymaps for cleanup
			local keymaps = {
				config.options.keymaps.toggle_priority,
				"<CR>",
				"q",
				"<Esc>",
			}

			local select_win = vim.api.nvim_open_win(select_buf, true, {
				relative = "editor",
				width = width,
				height = height,
				row = row,
				col = col,
				style = "minimal",
				border = "rounded",
				title = " Edit Priorities ",
				title_pos = "center",
				footer = string.format(" %s: toggle | <Enter>: confirm ", config.options.keymaps.toggle_priority),
				footer_pos = "center",
			})

			-- Set buffer content
			vim.api.nvim_buf_set_lines(select_buf, 0, -1, false, priority_options)
			vim.api.nvim_buf_set_option(select_buf, "modifiable", false)

			-- Add keymaps for selection
			vim.keymap.set("n", config.options.keymaps.toggle_priority, function()
				if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
					return
				end

				local cursor = vim.api.nvim_win_get_cursor(select_win)
				local line_num = cursor[1]
				local current_line = vim.api.nvim_buf_get_lines(select_buf, line_num - 1, line_num, false)[1]

				vim.api.nvim_buf_set_option(select_buf, "modifiable", true)
				if current_line:match("^%[%s%]") then
					-- Select item
					local new_line = current_line:gsub("^%[%s%]", "[x]")
					selected_priorities[line_num] = true
					vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
				else
					-- Deselect item
					local new_line = current_line:gsub("^%[x%]", "[ ]")
					selected_priorities[line_num] = nil
					vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
				end
				vim.api.nvim_buf_set_option(select_buf, "modifiable", false)
			end, { buffer = select_buf, nowait = true })

			-- Add keymap for confirmation
			vim.keymap.set("n", "<CR>", function()
				if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
					return
				end

				local selected_priority_names = {}
				for idx, _ in pairs(selected_priorities) do
					local priority = config.options.priorities[idx]
					if priority then
						table.insert(selected_priority_names, priority.name)
					end
				end

				-- Clean up resources before proceeding
				utils.cleanup_priority_selection(select_buf, select_win, keymaps)

				-- Update todo priorities
				state.todos[todo_index].priorities = #selected_priority_names > 0 and selected_priority_names or nil
				state.save_todos()
				local rendering = require("dooing.ui.rendering")
				rendering.render_todos()
			end, { buffer = select_buf, nowait = true })

			-- Add escape/quit keymaps
			local function close_window()
				utils.cleanup_priority_selection(select_buf, select_win, keymaps)
			end

			vim.keymap.set("n", "q", close_window, { buffer = select_buf, nowait = true })
			vim.keymap.set("n", "<Esc>", close_window, { buffer = select_buf, nowait = true })

			-- Add autocmd for cleanup when leaving buffer
			vim.api.nvim_create_autocmd("BufLeave", {
				buffer = select_buf,
				callback = function()
					utils.cleanup_priority_selection(select_buf, select_win, keymaps)
					return true
				end,
				once = true,
			})
		end
	end
end

-- Creates a new todo item
function M.new_todo()
	vim.ui.input({ prompt = "New to-do: " }, function(input)
		input = input:gsub("\n", " ")
		if input and input ~= "" then
			-- Check if priorities are configured
			if config.options.priorities and #config.options.priorities > 0 then
				local priorities = config.options.priorities
				local priority_options = {}
				local selected_priorities = {}

				for i, priority in ipairs(priorities) do
					priority_options[i] = string.format("[ ] %s", priority.name)
				end

				-- Create a buffer for priority selection
				local select_buf = vim.api.nvim_create_buf(false, true)
				local ui = vim.api.nvim_list_uis()[1]
				local width = 40
				local height = #priority_options + 2
				local row = math.floor((ui.height - height) / 2)
				local col = math.floor((ui.width - width) / 2)

				-- Store keymaps for cleanup
				local keymaps = {
					config.options.keymaps.toggle_priority,
					"<CR>",
					"q",
					"<Esc>",
				}

				local select_win = vim.api.nvim_open_win(select_buf, true, {
					relative = "editor",
					width = width,
					height = height,
					row = row,
					col = col,
					style = "minimal",
					border = "rounded",
					title = " Select Priorities ",
					title_pos = "center",
					footer = string.format(" %s: toggle | <Enter>: confirm ", config.options.keymaps.toggle_priority),
					footer_pos = "center",
				})

				-- Set buffer content
				vim.api.nvim_buf_set_lines(select_buf, 0, -1, false, priority_options)
				vim.api.nvim_buf_set_option(select_buf, "modifiable", false)

				-- Add keymaps for selection
				vim.keymap.set("n", config.options.keymaps.toggle_priority, function()
					if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
						return
					end

					local cursor = vim.api.nvim_win_get_cursor(select_win)
					local line_num = cursor[1]
					local current_line = vim.api.nvim_buf_get_lines(select_buf, line_num - 1, line_num, false)[1]

					vim.api.nvim_buf_set_option(select_buf, "modifiable", true)
					if current_line:match("^%[%s%]") then
						-- Select item
						local new_line = current_line:gsub("^%[%s%]", "[x]")
						selected_priorities[line_num] = true
						vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
					else
						-- Deselect item
						local new_line = current_line:gsub("^%[x%]", "[ ]")
						selected_priorities[line_num] = nil
						vim.api.nvim_buf_set_lines(select_buf, line_num - 1, line_num, false, { new_line })
					end
					vim.api.nvim_buf_set_option(select_buf, "modifiable", false)
				end, { buffer = select_buf, nowait = true })

				-- Add keymap for confirmation
				vim.keymap.set("n", "<CR>", function()
					if not (select_win and vim.api.nvim_win_is_valid(select_win)) then
						return
					end

					local selected_priority_names = {}
					for idx, _ in pairs(selected_priorities) do
						local priority = config.options.priorities[idx]
						if priority then
							table.insert(selected_priority_names, priority.name)
						end
					end

					-- Clean up resources before proceeding
					utils.cleanup_priority_selection(select_buf, select_win, keymaps)

					-- Add todo with priority names
					local priorities_to_add = #selected_priority_names > 0 and selected_priority_names or nil
					state.add_todo(input, priorities_to_add)
					local rendering = require("dooing.ui.rendering")
					rendering.render_todos()

					-- Make sure we're focusing on the main window
					if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
						vim.api.nvim_set_current_win(constants.win_id)
						
						-- Position cursor at the new todo
						local total_lines = vim.api.nvim_buf_line_count(constants.buf_id)
						local target_line = nil
						for i = 1, total_lines do
							local line = vim.api.nvim_buf_get_lines(constants.buf_id, i - 1, i, false)[1]
							if line:match("%s+" .. config.options.formatting.pending.icon .. ".*" .. vim.pesc(input)) then
								target_line = i
								break
							end
						end

						if target_line and constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
							vim.api.nvim_win_set_cursor(constants.win_id, { target_line, 0 })
						end
					end
				end, { buffer = select_buf, nowait = true })

				-- Add escape/quit keymaps
				local function close_window()
					utils.cleanup_priority_selection(select_buf, select_win, keymaps)
				end

				vim.keymap.set("n", "q", close_window, { buffer = select_buf, nowait = true })
				vim.keymap.set("n", "<Esc>", close_window, { buffer = select_buf, nowait = true })

				-- Add autocmd for cleanup when leaving buffer
				vim.api.nvim_create_autocmd("BufLeave", {
					buffer = select_buf,
					callback = function()
						utils.cleanup_priority_selection(select_buf, select_win, keymaps)
						return true -- Remove the autocmd after execution
					end,
					once = true,
				})
			else
				-- If prioritization is disabled, just add the todo without priority
				state.add_todo(input)
				local rendering = require("dooing.ui.rendering")
				rendering.render_todos()
				
				-- Make sure we're focusing on the main window
				if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
					vim.api.nvim_set_current_win(constants.win_id)
					
					-- Position cursor at the new todo
					local total_lines = vim.api.nvim_buf_line_count(constants.buf_id)
					local target_line = nil
					for i = 1, total_lines do
						local line = vim.api.nvim_buf_get_lines(constants.buf_id, i - 1, i, false)[1]
						if line:match("%s+" .. config.options.formatting.pending.icon .. ".*" .. vim.pesc(input)) then
							target_line = i
							break
						end
					end
					
					if target_line and constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
						vim.api.nvim_win_set_cursor(constants.win_id, { target_line, 0 })
					end
				end
			end
		end
	end)
end

-- Toggles the completion status of the current todo
function M.toggle_todo()
	local cursor = vim.api.nvim_win_get_cursor(constants.win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(constants.buf_id, todo_index, todo_index + 1, false)[1]
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local in_progress_icon = config.options.formatting.in_progress.icon

	if line_content:match("%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then -- -2 for filter header
						state.toggle_todo(i)
						break
					end
				end
			end
		else
			state.toggle_todo(todo_index)
		end
		local rendering = require("dooing.ui.rendering")
		rendering.render_todos()
	end
end

-- Deletes the current todo item
function M.delete_todo()
	local cursor = vim.api.nvim_win_get_cursor(constants.win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(constants.buf_id, todo_index, todo_index + 1, false)[1]
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon
	local in_progress_icon = config.options.formatting.in_progress.icon

	if line_content:match("%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						todo_index = 1
						break
					end
				end
			end
		else
			state.delete_todo_with_confirmation(todo_index, constants.win_id, calendar, function()
				local rendering = require("dooing.ui.rendering")
				rendering.render_todos()
			end)
		end
		local rendering = require("dooing.ui.rendering")
		rendering.render_todos()
	end
end

-- Deletes all completed todos
function M.delete_completed()
	state.delete_completed()
	local rendering = require("dooing.ui.rendering")
	rendering.render_todos()
end

-- Delete all duplicated todos
function M.remove_duplicates()
	local dups = state.remove_duplicates()
	vim.notify("Removed " .. dups .. " duplicates.", vim.log.levels.INFO)
	local rendering = require("dooing.ui.rendering")
	rendering.render_todos()
end

-- Add due date to to-do in the format MM/DD/YYYY
function M.add_due_date()
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local todo_index = current_line - (state.active_filter and 3 or 1)

	calendar.create(function(date_str)
		if date_str and date_str ~= "" then
			local success, err = state.add_due_date(todo_index, date_str)

			if success then
				vim.notify("Due date added successfully", vim.log.levels.INFO)
				local rendering = require("dooing.ui.rendering")
				rendering.render_todos()
			else
				vim.notify("Error adding due date: " .. (err or "Unknown error"), vim.log.levels.ERROR)
			end
		end
	end, { language = "en" })
end

-- Remove due date from to-do
function M.remove_due_date()
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local todo_index = current_line - (state.active_filter and 3 or 1)

	local success = state.remove_due_date(todo_index)

	if success then
		vim.notify("Due date removed successfully", vim.log.levels.INFO)
		local rendering = require("dooing.ui.rendering")
		rendering.render_todos()
	else
		vim.notify("Error removing due date", vim.log.levels.ERROR)
	end
end

-- Add estimated completion time to todo
function M.add_time_estimation()
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local todo_index = current_line - (state.active_filter and 3 or 1)

	vim.ui.input({
		prompt = "Estimated completion time (e.g., 15m, 2h, 1d, 0.5w): ",
		default = "",
	}, function(input)
		if input and input ~= "" then
			local hours, err = utils.parse_time_estimation(input)
			if hours then
				state.todos[todo_index].estimated_hours = hours
				state.save_todos()
				vim.notify("Time estimation added successfully", vim.log.levels.INFO)
				local rendering = require("dooing.ui.rendering")
				rendering.render_todos()
			else
				vim.notify("Error adding time estimation: " .. (err or "Unknown error"), vim.log.levels.ERROR)
			end
		end
	end)
end

-- Remove estimated completion time from todo
function M.remove_time_estimation()
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local todo_index = current_line - (state.active_filter and 3 or 1)

	if state.todos[todo_index] then
		state.todos[todo_index].estimated_hours = nil
		state.save_todos()
		vim.notify("Time estimation removed successfully", vim.log.levels.INFO)
		local rendering = require("dooing.ui.rendering")
		rendering.render_todos()
	else
		vim.notify("Error removing time estimation", vim.log.levels.ERROR)
	end
end

-- Import/Export functions
function M.prompt_export()
	local default_path = vim.fn.expand("~/todos.json")

	vim.ui.input({
		prompt = "Export todos to file: ",
		default = default_path,
		completion = "file",
	}, function(file_path)
		if not file_path or file_path == "" then
			vim.notify("Export cancelled", vim.log.levels.INFO)
			return
		end

		-- expand ~ to full home directory path
		file_path = vim.fn.expand(file_path)

		local success, message = state.export_todos(file_path)
		if success then
			vim.notify(message, vim.log.levels.INFO)
		else
			vim.notify(message, vim.log.levels.ERROR)
		end
	end)
end

function M.prompt_import()
	local default_path = vim.fn.expand("~/todos.json")

	vim.ui.input({
		prompt = "Import todos from file: ",
		default = default_path,
		completion = "file",
	}, function(file_path)
		if not file_path or file_path == "" then
			vim.notify("Import cancelled", vim.log.levels.INFO)
			return
		end

		-- expand ~ to full home directory path
		file_path = vim.fn.expand(file_path)

		local success, message = state.import_todos(file_path)
		if success then
			vim.notify(message, vim.log.levels.INFO)
			local rendering = require("dooing.ui.rendering")
			rendering.render_todos()
		else
			vim.notify(message, vim.log.levels.ERROR)
		end
	end)
end

-- Function to reload todos and refresh UI if window is open
function M.reload_todos()
    state.load_todos()
    local window = require("dooing.ui.window")
    if window.is_window_open() then
        local rendering = require("dooing.ui.rendering")
        rendering.render_todos()
        vim.notify("Todo list refreshed", vim.log.levels.INFO, { title = "Dooing" })
    end
end

-- Undo delete
function M.undo_delete()
	if state.undo_delete() then
		local rendering = require("dooing.ui.rendering")
		rendering.render_todos()
		vim.notify("Todo restored", vim.log.levels.INFO)
	end
end

return M 