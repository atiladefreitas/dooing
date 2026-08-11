---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Actions module for todo CRUD operations

local M = {}
local constants = require("dooing.ui.constants")
local utils = require("dooing.ui.utils")
local state = require("dooing.state")
local config = require("dooing.config")
local calendar = require("dooing.ui.calendar")
local server = require("dooing.server")

-- Resolves the todo under the cursor. The renderer owns the line -> todo
-- mapping, so this works for any layout, including ones with section headers
-- and other non-todo lines.
local find_todo_index = function()
	return utils.todo_index_at_cursor()
end

-- Handles editing of existing todos
function M.edit_todo()
	local todo_index = find_todo_index()

	if todo_index and state.todos[todo_index] then
		require("dooing.ui.panels").prompt({
			title = " Edit to-do ",
			prompt = "Edit to-do: ",
			default = state.todos[todo_index].text,
		}, function(input)
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
	local todo_index = find_todo_index()

	if todo_index and state.todos[todo_index] then
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
				border = config.options.window.border,
				title = " Select Priorities ",
				title_pos = "center",
				footer = string.format(" %s: toggle | <Enter>: confirm ", config.options.keymaps.toggle_priority),
				footer_pos = "center",
				zindex = config.options.window.zindex + 4,
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
	require("dooing.ui.panels").prompt({
		title = " New to-do ",
		prompt = "New to-do: ",
		footer = " <CR> confirm · <Esc> cancel · #tag to categorise ",
	}, function(input)
		if not input or input == "" then
			return
		end

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
					border = config.options.window.border,
					title = " Select Priorities ",
					title_pos = "center",
					footer = string.format(" %s: toggle | <Enter>: confirm ", config.options.keymaps.toggle_priority),
					footer_pos = "center",
					zindex = config.options.window.zindex + 4,
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

-- Creates a nested todo item under the current todo
function M.new_nested_todo()
	-- Check if nested tasks are enabled
	if not config.options.nested_tasks or not config.options.nested_tasks.enabled then
		vim.notify("Nested tasks are disabled in configuration", vim.log.levels.WARN)
		return
	end
	
	local todo_index = find_todo_index()

	-- Check if cursor is on a todo line
	if not (todo_index and state.todos[todo_index]) then
		vim.notify("Cursor must be on a todo item to create nested task", vim.log.levels.WARN)
		return
	end
	
	-- Creates the nested todo and refreshes the UI
	local function create_nested_todo(input, priorities_to_add)
		local success = state.add_nested_todo(input, todo_index, priorities_to_add)

		if success then
			local rendering = require("dooing.ui.rendering")
			rendering.render_todos()
			vim.notify("Nested task created", vim.log.levels.INFO)

			-- Focus back to main window
			if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
				vim.api.nvim_set_current_win(constants.win_id)
			end
		else
			vim.notify("Failed to create nested task", vim.log.levels.ERROR)
		end
	end

	require("dooing.ui.panels").prompt({
		title = " New sub-task ",
		prompt = "New sub-task: ",
		footer = " <CR> confirm · <Esc> cancel ",
	}, function(input)
		if not input or input == "" then
			return
		end
		input = input:gsub("\n", " ")
		if input ~= "" then
			-- Inherit the parent priorities and skip the priority selection
			if config.options.nested_tasks.inherit_priority then
				local parent_todo = state.todos[todo_index]
				local inherited_priorities = parent_todo and parent_todo.priorities
				create_nested_todo(input, inherited_priorities and vim.deepcopy(inherited_priorities) or nil)
				return
			end

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
					border = config.options.window.border,
					title = " Select Priorities ",
					title_pos = "center",
					footer = string.format(" %s: toggle | <Enter>: confirm ", config.options.keymaps.toggle_priority),
					footer_pos = "center",
					zindex = config.options.window.zindex + 4,
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

					-- Add nested todo with priority names
					local priorities_to_add = #selected_priority_names > 0 and selected_priority_names or nil
					create_nested_todo(input, priorities_to_add)
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
				-- If prioritization is disabled, just add the nested todo without priority
				create_nested_todo(input, nil)
			end
		end
	end)
end

-- Toggles the completion status of the current todo
function M.toggle_todo()
	local todo_index = find_todo_index()

	if todo_index and state.todos[todo_index] then
		state.toggle_todo(todo_index)

		local rendering = require("dooing.ui.rendering")
		rendering.render_todos()
	end
end

-- Deletes the current todo item
function M.delete_todo()
	local todo_index = find_todo_index()

	if todo_index and state.todos[todo_index] then
		state.delete_todo_with_confirmation(todo_index, constants.win_id, calendar, function()
			local rendering = require("dooing.ui.rendering")
			rendering.render_todos()
		end)
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
	local todo_index = find_todo_index()
	if not (todo_index and state.todos[todo_index]) then
		vim.notify("Cursor must be on a todo item to add a due date", vim.log.levels.WARN)
		return
	end

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
	local todo_index = find_todo_index()
	if not (todo_index and state.todos[todo_index]) then
		vim.notify("Cursor must be on a todo item to remove a due date", vim.log.levels.WARN)
		return
	end

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
	local todo_index = find_todo_index()
	if not (todo_index and state.todos[todo_index]) then
		vim.notify("Cursor must be on a todo item to add a time estimation", vim.log.levels.WARN)
		return
	end

	require("dooing.ui.panels").prompt({
		title = " Time estimation ",
		prompt = "Estimated completion time (e.g., 15m, 2h, 1d, 0.5w): ",
		default = "",
		footer = " 15m · 2h · 1d · 0.5w ",
	}, function(input)
		if input and input ~= "" then
			local hours, err = utils.parse_time_estimation(input)
			if hours and state.todos[todo_index] then
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
	local todo_index = find_todo_index()

	if todo_index and state.todos[todo_index] then
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
	local default_path = vim.fn.expand(config.options.save_path)

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
	local default_path = vim.fn.expand(config.options.save_path)

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
