---@diagnostic disable: undefined-global, param-type-mismatch
-- Explicitly declare vim as a global variable
local vim = vim

-- UI Module for Dooing Plugin
-- Handles window creation, rendering and UI interactions for todo management

---@class DoingUI
---@field toggle_todo_window function
---@field render_todos function
---@field close_window function
---@field new_todo function
---@field toggle_todo function
---@field delete_todo function
---@field delete_completed function
local M = {}

--------------------------------------------------
-- Dependencies
--------------------------------------------------
local state = require("dooing.state")
local config = require("dooing.config")
local calendar = require("dooing.calendar")

--------------------------------------------------
-- Local Variables and Cache
--------------------------------------------------
-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace("dooing")
-- Cache for highlight groups
local highlight_cache = {}

-- Window and buffer IDs
---@type integer|nil
local win_id = nil
---@type integer|nil
local buf_id = nil
---@type integer|nil
local help_win_id = nil
---@type integer|nil
local help_buf_id = nil
---@type integer|nil
local tag_win_id = nil
---@type integer|nil
local tag_buf_id = nil
---@type integer|nil
local search_win_id = nil
---@type integer|nil
local search_buf_id = nil

-- Forward declare local functions that are used in keymaps
local create_help_window
local create_tag_window
local edit_todo

--------------------------------------------------
-- Highlights Setup
--------------------------------------------------
-- Set up highlights

local function setup_highlights()
	-- Clear highlight cache
	highlight_cache = {}

	-- Set up base highlights
	vim.api.nvim_set_hl(0, "DooingPending", { link = "Question", default = true })
	vim.api.nvim_set_hl(0, "DooingDone", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "DooingHelpText", { link = "Directory", default = true })

	-- Cache the base highlight groups
	highlight_cache.pending = "DooingPending"
	highlight_cache.done = "DooingDone"
	highlight_cache.help = "DooingHelpText"
end

-- Get or create highlight group for a priority group
local function get_priority_highlight(priority_group)
	if not priority_group then
		return highlight_cache.pending
	end

	local cache_key = priority_group.color or priority_group.hl_group
	if highlight_cache[cache_key] then
		return highlight_cache[cache_key]
	end

	local hl_group = highlight_cache.pending

	if
		priority_group.color
		and type(priority_group.color) == "string"
		and priority_group.color:match("^#%x%x%x%x%x%x$")
	then
		local hl_name = "Dooing" .. priority_group.color:gsub("#", "")
		vim.api.nvim_set_hl(0, hl_name, { fg = priority_group.color })
		hl_group = hl_name
	elseif priority_group.hl_group then
		hl_group = priority_group.hl_group
	end

	highlight_cache[cache_key] = hl_group
	return hl_group
end

--------------------------------------------------
-- Todo Management Functions
--------------------------------------------------

-- Handles editing of existing todos
edit_todo = function()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]

	local done_icon = config.options.icons.done
	local pending_icon = config.options.icons.pending

	if line_content:match("^%s+[" .. done_icon .. pending_icon .. "]") then
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
				M.render_todos()
			end
		end)
	end
end

--------------------------------------------------
-- Core Window Management
--------------------------------------------------

-- Creates and manages the help window
create_help_window = function()
	if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
		vim.api.nvim_win_close(help_win_id, true)
		help_win_id = nil
		help_buf_id = nil
		return
	end

	help_buf_id = vim.api.nvim_create_buf(false, true)

	local width = 40
	local height = 20
	local ui = vim.api.nvim_list_uis()[1]
	local col = math.floor((ui.width - width) / 2) + width + 2
	local row = math.floor((ui.height - height) / 2)

	help_win_id = vim.api.nvim_open_win(help_buf_id, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " help ",
		title_pos = "center",
		zindex = 100,
	})

	local help_content = {
		" Main window:",
		" i     - Add new to-do",
		" x     - Toggle to-do status",
		" h     - Add due date to to-do ",
		" r     - Remove to-do due date",
		" T     - Add time estimation",
		" R     - Remove time estimation",
		" d     - Delete current to-do",
		" D     - Delete all completed todos",
		" ?     - Toggle this help window",
		" q     - Close window",
		" t     - Toggle tags window",
		" e     - Edit to-do item",
		" c     - Clear active tag filter",
		" /     - Search todos",
		" ",
		" Tags window:",
		" e     - Edit tag",
		" d     - Delete tag",
		" <CR>  - Filter by tag",
		" q     - Close window",
		" ",
	}

	vim.api.nvim_buf_set_lines(help_buf_id, 0, -1, false, help_content)
	vim.api.nvim_buf_set_option(help_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(help_buf_id, "buftype", "nofile")

	for i = 0, #help_content - 1 do
		vim.api.nvim_buf_add_highlight(help_buf_id, ns_id, "DooingHelpText", i, 0, -1)
	end

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = help_buf_id,
		callback = function()
			if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
				vim.api.nvim_win_close(help_win_id, true)
				help_win_id = nil
				help_buf_id = nil
			end
			return true
		end,
	})

	local function close_help()
		if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
			vim.api.nvim_win_close(help_win_id, true)
			help_win_id = nil
			help_buf_id = nil
		end
	end

	vim.keymap.set("n", config.options.keymaps.close_window, close_help, { buffer = help_buf_id, nowait = true })
	vim.keymap.set("n", config.options.keymaps.toggle_help, close_help, { buffer = help_buf_id, nowait = true })
end

-- Creates and manages the tags window
create_tag_window = function()
	if tag_win_id and vim.api.nvim_win_is_valid(tag_win_id) then
		vim.api.nvim_win_close(tag_win_id, true)
		tag_win_id = nil
		tag_buf_id = nil
		return
	end

	tag_buf_id = vim.api.nvim_create_buf(false, true)

	local width = 30
	local height = 10
	local ui = vim.api.nvim_list_uis()[1]
	local main_width = 40
	local main_col = math.floor((ui.width - main_width) / 2)
	local col = main_col - width - 2
	local row = math.floor((ui.height - height) / 2)

	tag_win_id = vim.api.nvim_open_win(tag_buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " tags ",
		title_pos = "center",
	})

	local tags = state.get_all_tags()
	if #tags == 0 then
		tags = { "No tags found" }
	end

	vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, tags)

	vim.api.nvim_buf_set_option(tag_buf_id, "modifiable", true)

	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.set_filter(tag)
			vim.api.nvim_win_close(tag_win_id, true)
			tag_win_id = nil
			tag_buf_id = nil
			M.render_todos()
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", config.options.keymaps.edit_tag, function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local old_tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if old_tag ~= "No tags found" then
			vim.ui.input({ prompt = "Edit tag: ", default = old_tag }, function(new_tag)
				if new_tag and new_tag ~= "" and new_tag ~= old_tag then
					state.rename_tag(old_tag, new_tag)
					local tags = state.get_all_tags()
					vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, tags)
					M.render_todos()
				end
			end)
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", config.options.keymaps.delete_tag, function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.delete_tag(tag)
			local tags = state.get_all_tags()
			if #tags == 0 then
				tags = { "No tags found" }
			end
			vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, tags)
			M.render_todos()
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(tag_win_id, true)
		tag_win_id = nil
		tag_buf_id = nil
		vim.api.nvim_set_current_win(win_id)
	end, { buffer = tag_buf_id })
end

-- Handle search queries
local function handle_search_query(query)
	if not query or query == "" then
		if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
			vim.api.nvim_win_close(search_win_id, true)
			vim.api.nvim_set_current_win(win_id)
			search_win_id = nil
			search_buf_id = nil
		end
		return
	end

	local done_icon = config.options.icons.done
	local pending_icon = config.options.icons.pending

	-- Prepare the search results
	local results = state.search_todos(query)
	vim.api.nvim_buf_set_option(search_buf_id, "modifiable", true)
	local lines = { "Search Results for: " .. query, "" }
	local valid_lines = {} -- Store valid todo lines
	if #results > 0 then
		for _, result in ipairs(results) do
			local icon = result.todo.done and done_icon or pending_icon
			local line = string.format("  %s %s", icon, result.todo.text)
			table.insert(lines, line)
			table.insert(valid_lines, { line_index = #lines, result = result })
		end
	else
		table.insert(lines, "  No results found")
		vim.api.nvim_set_current_win(win_id)
	end

	-- Add search results to window
	vim.api.nvim_buf_set_lines(search_buf_id, 0, -1, false, lines)

	-- After adding search results, make it unmodifiable
	vim.api.nvim_buf_set_option(search_buf_id, "modifiable", false)

	-- Highlight todos on search results
	for i, line in ipairs(lines) do
		if line:match("^%s+[" .. done_icon .. pending_icon .. "]") then
			local hl_group = line:match(done_icon) and "DooingDone" or "DooingPending"
			vim.api.nvim_buf_add_highlight(search_buf_id, ns_id, hl_group, i - 1, 0, -1)
			for tag in line:gmatch("#(%w+)") do
				local start_idx = line:find("#" .. tag) - 1
				vim.api.nvim_buf_add_highlight(search_buf_id, ns_id, "Type", i - 1, start_idx, start_idx + #tag + 1)
			end
		elseif line:match("Search Results") then
			vim.api.nvim_buf_add_highlight(search_buf_id, ns_id, "WarningMsg", i - 1, 0, -1)
		end
	end

	-- Close search window
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(search_win_id, true)
		search_win_id = nil
		search_buf_id = nil
		if win_id and vim.api.nvim_win_is_valid(win_id) then
			vim.api.nvim_set_current_win(win_id)
		end
	end, { buffer = search_buf_id, nowait = true })

	-- Jump to todo in main window
	vim.keymap.set("n", "<CR>", function()
		local current_line = vim.api.nvim_win_get_cursor(search_win_id)[1]
		local matched_result = nil
		for _, item in ipairs(valid_lines) do
			if item.line_index == current_line then
				matched_result = item.result
				break
			end
		end
		if matched_result then
			vim.api.nvim_win_close(search_win_id, true)
			search_win_id = nil
			search_buf_id = nil
			vim.api.nvim_set_current_win(win_id)
			vim.api.nvim_win_set_cursor(win_id, { matched_result.lnum + 1, 3 })
		end
	end, { buffer = search_buf_id, nowait = true })
end

-- Search for todos
local function create_search_window()
	-- If search window exists and is valid, focus on the existing window and return
	if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
		vim.api.nvim_set_current_win(search_win_id)
		vim.ui.input({ prompt = "Search todos: " }, function(query)
			handle_search_query(query)
		end)
		return
	end

	-- If search window exists but is not valid, reset IDs
	if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
		search_win_id = nil
		search_buf_id = nil
	end

	-- Create search results buffer
	search_buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(search_buf_id, "buflisted", true)
	vim.api.nvim_buf_set_option(search_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(search_buf_id, "filetype", "todo_search")
	local width = 40
	local height = 10
	local ui = vim.api.nvim_list_uis()[1]
	local main_width = 40
	local main_col = math.floor((ui.width - main_width) / 2)
	local col = main_col - width - 2
	local row = math.floor((ui.height - height) / 2)
	search_win_id = vim.api.nvim_open_win(search_buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Search Todos ",
		title_pos = "center",
	})

	-- Create search query pane
	vim.ui.input({ prompt = "Search todos: " }, function(query)
		handle_search_query(query)
	end)

	-- Close the search window if main window is closed
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win_id),
		callback = function()
			if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
				vim.api.nvim_win_close(search_win_id, true)
				search_win_id = nil
				search_buf_id = nil
			end
		end,
	})
end

-- Parse time estimation string (e.g., "2h", "1d", "0.5w")
function M.parse_time_estimation(time_str)
	local number, unit = time_str:match("^(%d+%.?%d*)([hdw])$")

	if not (number and unit) then
		return nil, "Invalid format. Use number followed by h (hours), d (days), or w (weeks). E.g., 2h, 1d, 0.5w"
	end

	local hours = tonumber(number)
	if not hours then
		return nil, "Invalid number format"
	end

	-- Convert to hours
	if unit == "d" then
		hours = hours * 24
	elseif unit == "w" then
		hours = hours * 24 * 7
	end

	return hours
end

-- Add estimated completion time to todo
local function add_time_estimation()
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local todo_index = current_line - (state.active_filter and 3 or 1)

	vim.ui.input({
		prompt = "Estimated completion time (e.g., 2h, 1d, 0.5w): ",
		default = "",
	}, function(input)
		if input and input ~= "" then
			local hours, err = M.parse_time_estimation(input)
			if hours then
				state.todos[todo_index].estimated_hours = hours
				state.save_todos()
				vim.notify("Time estimation added successfully", vim.log.levels.INFO)
				M.render_todos()
			else
				vim.notify("Error adding time estimation: " .. (err or "Unknown error"), vim.log.levels.ERROR)
			end
		end
	end)
end

-- Remove estimated completion time from todo
local function remove_time_estimation()
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local todo_index = current_line - (state.active_filter and 3 or 1)

	if state.todos[todo_index] then
		state.todos[todo_index].estimated_hours = nil
		state.save_todos()
		vim.notify("Time estimation removed successfully", vim.log.levels.INFO)
		M.render_todos()
	else
		vim.notify("Error removing time estimation", vim.log.levels.ERROR)
	end
end

-- Add due date to to-do in the format MM/DD/YYYY
-- In ui.lua, update the add_due_date function
local function add_due_date()
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local todo_index = current_line - (state.active_filter and 3 or 1)

	calendar.create(function(date_str)
		if date_str and date_str ~= "" then
			local success, err = state.add_due_date(todo_index, date_str)

			if success then
				vim.notify("Due date added successfully", vim.log.levels.INFO)
				M.render_todos()
			else
				vim.notify("Error adding due date: " .. (err or "Unknown error"), vim.log.levels.ERROR)
			end
		end
	end, { language = "en" })
end

-- Remove due date from to-do
local function remove_due_date()
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local todo_index = current_line - (state.active_filter and 3 or 1)

	local success = state.remove_due_date(todo_index)

	if success then
		vim.notify("Due date removed successfully", vim.log.levels.INFO)
		M.render_todos()
	else
		vim.notify("Error removing due date", vim.log.levels.ERROR)
	end
end

-- Creates and configures the main todo window
local function create_window()
	local ui = vim.api.nvim_list_uis()[1]
	local width = config.options.window.width
	local height = config.options.window.height
	local col = math.floor((ui.width - width) / 2)
	local row = math.floor((ui.height - height) / 2)

	setup_highlights()

	local function set_conditional_keymap(key_option, callback, opts)
		if config.options.keymaps[key_option] then
			vim.keymap.set("n", config.options.keymaps[key_option], callback, opts)
		end
	end

	buf_id = vim.api.nvim_create_buf(false, true)

	win_id = vim.api.nvim_open_win(buf_id, true, {
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

	vim.api.nvim_win_set_option(win_id, "wrap", true)
	vim.api.nvim_win_set_option(win_id, "linebreak", true)
	vim.api.nvim_win_set_option(win_id, "breakindent", true)
	vim.api.nvim_win_set_option(win_id, "breakindentopt", "shift:2")
	vim.api.nvim_win_set_option(win_id, "showbreak", " ")

	set_conditional_keymap("new_todo", M.new_todo, { buffer = buf_id, nowait = true })
	set_conditional_keymap("toggle_todo", M.toggle_todo, { buffer = buf_id, nowait = true })
	set_conditional_keymap("delete_todo", M.delete_todo, { buffer = buf_id, nowait = true })
	set_conditional_keymap("delete_completed", M.delete_completed, { buffer = buf_id, nowait = true })
	set_conditional_keymap("close_window", M.close_window, { buffer = buf_id, nowait = true })
	set_conditional_keymap("toggle_help", create_help_window, { buffer = buf_id, nowait = true })
	set_conditional_keymap("toggle_tags", create_tag_window, { buffer = buf_id, nowait = true })
	set_conditional_keymap("edit_todo", edit_todo, { buffer = buf_id, nowait = true })
	set_conditional_keymap("add_due_date", add_due_date, { buffer = buf_id, nowait = true })
	set_conditional_keymap("remove_due_date", remove_due_date, { buffer = buf_id, nowait = true })
	set_conditional_keymap("add_time_estimation", add_time_estimation, { buffer = buf_id, nowait = true })
	set_conditional_keymap("remove_time_estimation", remove_time_estimation, { buffer = buf_id, nowait = true })
	set_conditional_keymap("search_todos", create_search_window, { buffer = buf_id, nowait = true })
	set_conditional_keymap("clear_filter", function()
		state.set_filter(nil)
		M.render_todos()
	end, { buffer = buf_id, desc = "Clear filter" })
end

-- Public Interface
--------------------------------------------------

function M.render_todos()
	if not buf_id then
		return
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

	local lines = { "" }
	state.sort_todos()

	local lang = calendar and calendar.get_language()

	local done_icon = config.options.icons.done
	local pending_icon = config.options.icons.pending

	for _, todo in ipairs(state.todos) do
		if not state.active_filter or todo.text:match("#" .. state.active_filter) then
			local check_icon = todo.done and done_icon or pending_icon

			local text = todo.text

			-- Format due date if exists
			local due_date_str = ""
			if todo.due_at then
				local date = os.date("*t", todo.due_at)
				local month = calendar.MONTH_NAMES[lang][date.month]

				local formatted_date
				if lang == "pt" or lang == "en" then
					formatted_date = string.format("%d de %s de %d", date.day, month, date.year)
				elseif lang == "fr" then
					formatted_date = string.format("%d %s %d", date.day, month, date.year)
				elseif lang == "de" or lang == "it" then
					formatted_date = string.format("%d %s %d", date.day, month, date.year)
				elseif lang == "jp" then
					formatted_date = string.format("%d年%s%d日", date.year, month, date.day)
				else -- "en"
					formatted_date = string.format("%s %d, %d", month, date.day, date.year)
				end
				due_date_str = " [" .. config.options.icons.calendar .. " " .. formatted_date .. "]"

				-- Highlight overdue todos
				local current_time = os.time()
				if not todo.done and todo.due_at < current_time then
					due_date_str = due_date_str .. " [OVERDUE]"
				end
			end

			-- Format time estimation if exists
			local time_str = ""
			if todo.estimated_hours then
				if todo.estimated_hours >= 168 then -- more than a week
					time_str = string.format(" [≈ %.1fw]", todo.estimated_hours / 168)
				elseif todo.estimated_hours >= 24 then -- more than a day
					time_str = string.format(" [≈ %.1fd]", todo.estimated_hours / 24)
				else
					time_str = string.format(" [≈ %.1fh]", todo.estimated_hours)
				end
			end

			if todo.done then
				text = "~" .. text .. "~"
			end

			table.insert(lines, "  " .. check_icon .. " " .. text .. due_date_str .. time_str)
		end
	end

	if state.active_filter then
		table.insert(lines, 1, "")
		table.insert(lines, 1, "  Filtered by: #" .. state.active_filter)
	end

	table.insert(lines, "")
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

	for i, line in ipairs(lines) do
		if line:match("^%s+[" .. done_icon .. pending_icon .. "]") then
			local todo_index = i - (state.active_filter and 3 or 1)
			local todo = state.todos[todo_index]

			if todo then
				-- If todo is done, use DooingDone highlight
				if todo.done then
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, "DooingDone", i - 1, 0, -1)
				else
					-- Log todo priorities
					if todo.priorities then
						vim.notify(
							string.format(
								"Todo '%s' has priorities: %s",
								todo.text,
								table.concat(todo.priorities, ", ")
							),
							vim.log.levels.INFO
						)
					else
						vim.notify(string.format("Todo '%s' has no priorities", todo.text), vim.log.levels.INFO)
					end

					-- Log configured priority groups
					if config.options.priorities then
						local groups = {}
						for _, group in ipairs(config.options.priorities) do
							table.insert(
								groups,
								string.format(
									"%s (color: %s, hl_group: %s)",
									group.name,
									group.color or "none",
									group.hl_group or "none"
								)
							)
						end
						vim.notify(
							string.format("Configured priority groups:\n%s", table.concat(groups, "\n")),
							vim.log.levels.INFO
						)
					else
						vim.notify("No priority groups configured", vim.log.levels.INFO)
					end

					-- Find matching priority group based on todo's priorities
					if todo.priorities and config.options.priorities then
						for _, priority in ipairs(todo.priorities) do
							for _, group in ipairs(config.options.priorities) do
								if group.name == priority then
									vim.notify(
										string.format(
											"Found matching priority group '%s' for todo '%s'",
											group.name,
											todo.text
										),
										vim.log.levels.INFO
									)
								end
							end
						end
					end
				end

				-- Highlight tags
				for tag in line:gmatch("#(%w+)") do
					local start_idx = line:find("#" .. tag) - 1
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Type", i - 1, start_idx, start_idx + #tag + 1)
				end

				-- Highlight due dates and overdue status
				local due_date_match = line:match("%[@(%d+/%d+/%d+)%]")
				local overdue_match = line:match("%[OVERDUE%]")

				if due_date_match then
					local due_date_start = line:find("@" .. due_date_match)
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Comment", i - 1, due_date_start - 1, -1)
				end

				if overdue_match then
					local overdue_start = line:find("%[OVERDUE%]")
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, "ErrorMsg", i - 1, overdue_start - 1, -1)
				end
			end
		elseif line:match("Filtered by:") then
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "WarningMsg", i - 1, 0, -1)
		end
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

-- Toggles the main todo window visibility
function M.toggle_todo_window()
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		M.close_window()
	else
		create_window()
		M.render_todos()
	end
end

-- Closes all plugin windows
function M.close_window()
	if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
		vim.api.nvim_win_close(help_win_id, true)
		help_win_id = nil
		help_buf_id = nil
	end

	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
		win_id = nil
		buf_id = nil
	end
end

-- Creates a new todo item
function M.new_todo()
	vim.ui.input({ prompt = "New to-do: " }, function(input)
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
					local selected_priority_names = {}
					for idx, _ in pairs(selected_priorities) do
						-- Get the priority name from the config using the index
						local priority = config.options.priorities[idx]
						if priority then
							table.insert(selected_priority_names, priority.name)
						end
					end

					-- Close selection window
					vim.api.nvim_win_close(select_win, true)

					-- Add todo with priority names (or nil if none selected)
					local priorities_to_add = #selected_priority_names > 0 and selected_priority_names or nil
					state.add_todo(input, priorities_to_add)
					M.render_todos()

					-- Position cursor logic...
					local total_lines = vim.api.nvim_buf_line_count(buf_id)
					local target_line = nil
					local last_uncompleted_line = nil

					for i = 1, total_lines do
						local line = vim.api.nvim_buf_get_lines(buf_id, i - 1, i, false)[1]
						if line:match("^%s+[" .. config.options.icons.pending .. "]") then
							last_uncompleted_line = i
						end
						if line:match("^%s+[" .. config.options.icons.done .. "].*~") then
							target_line = i - 1
							break
						end
					end

					if not target_line and last_uncompleted_line then
						target_line = last_uncompleted_line
					end

					if target_line then
						vim.api.nvim_win_set_cursor(win_id, { target_line, 0 })
					end
				end)
			else
				-- If prioritization is disabled, just add the todo without priority
				state.add_todo(input)
				M.render_todos()
			end
		end
	end)
end

-- Toggles the completion status of the current todo
function M.toggle_todo()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]
	local done_icon = config.options.icons.done
	local pending_icon = config.options.icons.pending

	if line_content:match("^%s+[" .. done_icon .. pending_icon .. "]") then
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
		M.render_todos()
	end
end

-- Deletes the current todo item
function M.delete_todo()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]
	local done_icon = config.options.icons.done
	local pending_icon = config.options.icons.pending

	if line_content:match("^%s+[" .. done_icon .. pending_icon .. "]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						state.delete_todo(i)
						break
					end
				end
			end
		else
			state.delete_todo(todo_index)
		end
		M.render_todos()
	end
end

-- Deletes all completed todos
function M.delete_completed()
	state.delete_completed()
	M.render_todos()
end

return M
