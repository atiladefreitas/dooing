-- Declare vim locally at the top
local vim = vim

local M = {}
local config = require("dooing.config")

-- Cache frequently accessed values
local priority_weights = {}

M.todos = {}

-- Update priority weights cache when config changes
local function update_priority_weights()
	priority_weights = {}
	for _, p in ipairs(config.options.priorities) do
		priority_weights[p.name] = p.weight or 1
	end
end

local function save_todos()
	local file = io.open(config.options.save_path, "w")
	if file then
		file:write(vim.fn.json_encode(M.todos))
		file:close()
	end
end

-- Expose it as part of the module
M.save_todos = save_todos

function M.load_todos()
	update_priority_weights()
	local file = io.open(config.options.save_path, "r")
	if file then
		local content = file:read("*all")
		file:close()
		if content and content ~= "" then
			M.todos = vim.fn.json_decode(content)
		end
	end
end

function M.add_todo(text, priority_names)
	table.insert(M.todos, {
		text = text,
		done = false,
		in_progress = false,
		category = text:match("#(%w+)") or "",
		created_at = os.time(),
		priorities = priority_names,
		estimated_hours = nil, -- Add estimated_hours field
		notes = "",
	})
	save_todos()
end

function M.toggle_todo(index)
	if M.todos[index] then
		-- Cycle through states: pending -> in_progress -> done -> pending
		if not M.todos[index].in_progress and not M.todos[index].done then
			-- From pending to in_progress
			M.todos[index].in_progress = true
		elseif M.todos[index].in_progress then
			-- From in_progress to done
			M.todos[index].in_progress = false
			M.todos[index].done = true
		else
			-- From done back to pending
			M.todos[index].done = false
		end
		save_todos()
	end
end

-- Parse date string in the format MM/DD/YYYY
local function parse_date(date_str, format)
	local month, day, year = date_str:match("^(%d%d?)/(%d%d?)/(%d%d%d%d)$")

	print(month, day, year)
	if not (month and day and year) then
		return nil, "Invalid date format"
	end

	month, day, year = tonumber(month), tonumber(day), tonumber(year)

	local function is_leap_year(y)
		return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
	end

	-- Handle days and months, with leap year check
	local days_in_month = {
		31, -- January
		is_leap_year(year) and 29 or 28, -- February
		31, -- March
		30, -- April
		31, -- May
		30, -- June
		31, -- July
		31, -- August
		30, -- September
		31, -- October
		30, -- November
		31, -- December
	}
	if month < 1 or month > 12 then
		return nil, "Invalid month"
	end
	if day < 1 or day > days_in_month[month] then
		return nil, "Invalid day for month"
	end

	-- Convert to Unix timestamp
	local timestamp = os.time({ year = year, month = month, day = day, hour = 0, min = 0, sec = 0 })
	return timestamp
end

function M.add_due_date(index, date_str)
	if not M.todos[index] then
		return false, "Todo not found"
	end

	local timestamp, err = parse_date(date_str)
	if timestamp then
		M.todos[index].due_at = timestamp
		M.save_todos()
		return true
	else
		return false, err
	end
end

function M.remove_due_date(index)
	if M.todos[index] then
		M.todos[index].due_at = nil
		M.save_todos()
		return true
	end
	return false
end

-- Add estimated completion time to a todo
function M.add_time_estimation(index, hours)
	if not M.todos[index] then
		return false, "Todo not found"
	end

	if type(hours) ~= "number" or hours < 0 then
		return false, "Invalid time estimation"
	end

	M.todos[index].estimated_hours = hours
	M.save_todos()
	return true
end

-- Remove estimated completion time from a todo
function M.remove_time_estimation(index)
	if M.todos[index] then
		M.todos[index].estimated_hours = nil
		M.save_todos()
		return true
	end
	return false
end

function M.get_all_tags()
	local tags = {}
	local seen = {}
	for _, todo in ipairs(M.todos) do
		-- Remove unused todo_tags variable
		for tag in todo.text:gmatch("#(%w+)") do
			if not seen[tag] then
				seen[tag] = true
				table.insert(tags, tag)
			end
		end
	end
	table.sort(tags)
	return tags
end

function M.set_filter(tag)
	M.active_filter = tag
end

function M.delete_todo(index)
	if M.todos[index] then
		table.remove(M.todos, index)
		save_todos()
	end
end

function M.delete_completed()
	local remaining_todos = {}
	for _, todo in ipairs(M.todos) do
		if not todo.done then
			table.insert(remaining_todos, todo)
		end
	end
	M.todos = remaining_todos
	save_todos()
end

-- Helper function for hashing a todo object
local function gen_hash(todo)
	local todo_string = vim.inspect(todo)
	return vim.fn.sha256(todo_string)
end

-- Remove duplicate todos based on hash
function M.remove_duplicates()
	local seen = {}
	local uniques = {}
	local removed = 0

	for _, todo in ipairs(M.todos) do
		if type(todo) == "table" then
			local hash = gen_hash(todo)
			if not seen[hash] then
				seen[hash] = true
				table.insert(uniques, todo)
			else
				removed = removed + 1
			end
		end
	end

	M.todos = uniques
	save_todos()
	return tostring(removed)
end

-- Calculate priority score for a todo item
function M.get_priority_score(todo)
	if todo.done then
		return 0
	end

	if not config.options.priorities or #config.options.priorities == 0 then
		return 0
	end

	-- Calculate base score from priorities
	local score = 0
	if todo.priorities and type(todo.priorities) == "table" then
		for _, priority_name in ipairs(todo.priorities) do
			score = score + (priority_weights[priority_name] or 0)
		end
	end

	-- Calculate estimated completion time multiplier
	local ect_multiplier = 1
	if todo.estimated_hours and todo.estimated_hours > 0 then
		ect_multiplier = 1 / (todo.estimated_hours * config.options.hour_score_value)
	end

	return score * ect_multiplier
end

function M.sort_todos()
	table.sort(M.todos, function(a, b)
		-- First sort by completion status
		if a.done ~= b.done then
			return not a.done -- Undone items come first
		end

		-- Then sort by priority score if configured
		if config.options.priorities and #config.options.priorities > 0 then
			local a_score = M.get_priority_score(a)
			local b_score = M.get_priority_score(b)

			if a_score ~= b_score then
				return a_score > b_score
			end
		end

		-- Then sort by due date if both have one
		if a.due_at and b.due_at then
			if a.due_at ~= b.due_at then
				return a.due_at < b.due_at
			end
		elseif a.due_at then
			return true -- Items with due date come first
		elseif b.due_at then
			return false
		end

		-- Finally sort by creation time
		return a.created_at < b.created_at
	end)
end

function M.rename_tag(old_tag, new_tag)
	for _, todo in ipairs(M.todos) do
		todo.text = todo.text:gsub("#" .. old_tag, "#" .. new_tag)
	end
	save_todos()
end

function M.delete_tag(tag)
	local remaining_todos = {}
	for _, todo in ipairs(M.todos) do
		todo.text = todo.text:gsub("#" .. tag .. "(%s)", "%1")
		todo.text = todo.text:gsub("#" .. tag .. "$", "")
		table.insert(remaining_todos, todo)
	end
	M.todos = remaining_todos
	save_todos()
end

function M.search_todos(query)
	local results = {}
	query = query:lower()

	for index, todo in ipairs(M.todos) do
		if todo.text:lower():find(query) then
			table.insert(results, { lnum = index, todo = todo })
		end
	end

	return results
end

function M.import_todos(file_path)
	local file = io.open(file_path, "r")
	if not file then
		return false, "Could not open file: " .. file_path
	end

	local content = file:read("*all")
	file:close()

	local status, imported_todos = pcall(vim.fn.json_decode, content)
	if not status then
		return false, "Error parsing JSON file"
	end

	-- merge imported todos with existing todos
	for _, todo in ipairs(imported_todos) do
		table.insert(M.todos, todo)
	end

	M.sort_todos()
	M.save_todos()

	return true, string.format("Imported %d todos", #imported_todos)
end

function M.export_todos(file_path)
	local file = io.open(file_path, "w")
	if not file then
		return false, "Could not open file for writing: " .. file_path
	end

	local json_content = vim.fn.json_encode(M.todos)
	file:write(json_content)
	file:close()

	return true, string.format("Exported %d todos to %s", #M.todos, file_path)
end

-- Helper function to get the priority-based highlights
local function get_priority_highlights(todo)
	-- First check if the todo is done
	if todo.done then
		return "DooingDone"
	end

	-- Then check if it's in progress
	if todo.in_progress then
		return "DooingInProgress"
	end

	-- If there are no priorities configured, return the default pending highlight
	if not config.options.priorities or #config.options.priorities == 0 then
		return "DooingPending"
	end

	-- If the todo has priorities, check priority groups
	if todo.priorities and #todo.priorities > 0 and config.options.priority_groups then
		-- Sort priority groups by number of members (descending)
		local sorted_groups = {}
		for name, group in pairs(config.options.priority_groups) do
			table.insert(sorted_groups, { name = name, group = group })
		end
		table.sort(sorted_groups, function(a, b)
			return #a.group.members > #b.group.members
		end)

		-- Check each priority group
		for _, group_data in ipairs(sorted_groups) do
			local group = group_data.group
			local all_members_match = true

			-- Check if all group members are in todo's priorities
			for _, member in ipairs(group.members) do
				local found = false
				for _, priority in ipairs(todo.priorities) do
					if priority == member then
						found = true
						break
					end
				end
				if not found then
					all_members_match = false
					break
				end
			end

			if all_members_match then
				return group.hl_group or "DooingPending"
			end
		end
	end

	-- Default to pending highlight if no other conditions met
	return "DooingPending"
end

-- Delete todo with confirmation for incomplete items
function M.delete_todo_with_confirmation(todo_index, win_id, calendar, callback)
	local current_todo = M.todos[todo_index]
	if not current_todo then
		return
	end

	-- If todo is completed, delete without confirmation
	if current_todo.done then
		M.delete_todo(todo_index)
		if callback then
			callback()
		end
		return
	end

	-- Create confirmation buffer
	local confirm_buf = vim.api.nvim_create_buf(false, true)

	-- Format todo text with due date
	local safe_todo_text = current_todo.text:gsub("\n", " ")
	local todo_display_text = "   ○ " .. safe_todo_text
	local lang = calendar.get_language()
	lang = calendar.MONTH_NAMES[lang] and lang or "en"

	if current_todo.due_at then
		local date = os.date("*t", current_todo.due_at)
		local month = calendar.MONTH_NAMES[lang][date.month]

		local formatted_date
		if lang == "pt" then
			formatted_date = string.format("%d de %s de %d", date.day, month, date.year)
		else
			formatted_date = string.format("%s %d, %d", month, date.day, date.year)
		end
		todo_display_text = todo_display_text .. " [@ " .. formatted_date .. "]"

		-- Add overdue status if applicable
		if current_todo.due_at < os.time() then
			todo_display_text = todo_display_text .. " [OVERDUE]"
		end
	end

	local lines = {
		"",
		"",
		todo_display_text,
		"",
		"",
		"",
	}

	-- Set buffer content
	vim.api.nvim_buf_set_lines(confirm_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(confirm_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(confirm_buf, "buftype", "nofile")

	-- Calculate window dimensions
	local ui = vim.api.nvim_list_uis()[1]
	local width = 60
	local height = #lines
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - width) / 2)

	-- Create confirmation window
	local confirm_win = vim.api.nvim_open_win(confirm_buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Delete incomplete todo? ",
		title_pos = "center",
		footer = " [Y]es - [N]o ",
		footer_pos = "center",
		noautocmd = true,
	})

	-- Window options
	vim.api.nvim_win_set_option(confirm_win, "cursorline", false)
	vim.api.nvim_win_set_option(confirm_win, "cursorcolumn", false)
	vim.api.nvim_win_set_option(confirm_win, "number", false)
	vim.api.nvim_win_set_option(confirm_win, "relativenumber", false)
	vim.api.nvim_win_set_option(confirm_win, "signcolumn", "no")
	vim.api.nvim_win_set_option(confirm_win, "mousemoveevent", false)

	-- Add highlights
	local ns = vim.api.nvim_create_namespace("dooing_confirm")
	vim.api.nvim_buf_add_highlight(confirm_buf, ns, "WarningMsg", 0, 0, -1)

	local main_hl = get_priority_highlights(current_todo)
	vim.api.nvim_buf_add_highlight(confirm_buf, ns, main_hl, 2, 0, #todo_display_text)

	-- Tag highlights
	for tag in current_todo.text:gmatch("#(%w+)") do
		local start_idx = todo_display_text:find("#" .. tag)
		if start_idx then
			vim.api.nvim_buf_add_highlight(confirm_buf, ns, "Type", 2, start_idx - 1, start_idx + #tag)
		end
	end

	-- Due date highlight
	if current_todo.due_at then
		local due_date_start = todo_display_text:find("%[@")
		local overdue_start = todo_display_text:find("%[OVERDUE%]")

		if due_date_start then
			vim.api.nvim_buf_add_highlight(
				confirm_buf,
				ns,
				"Comment",
				2,
				due_date_start - 1,
				overdue_start and overdue_start - 1 or -1
			)
		end

		if overdue_start then
			vim.api.nvim_buf_add_highlight(confirm_buf, ns, "ErrorMsg", 2, overdue_start - 1, -1)
		end
	end

	-- Options highlights
	vim.api.nvim_buf_add_highlight(confirm_buf, ns, "Question", 4, 1, 2)
	vim.api.nvim_buf_add_highlight(confirm_buf, ns, "Normal", 4, 0, 1)
	vim.api.nvim_buf_add_highlight(confirm_buf, ns, "Normal", 4, 2, 5)
	vim.api.nvim_buf_add_highlight(confirm_buf, ns, "Normal", 4, 5, 9)
	vim.api.nvim_buf_add_highlight(confirm_buf, ns, "Question", 4, 10, 11)
	vim.api.nvim_buf_add_highlight(confirm_buf, ns, "Normal", 4, 9, 10)
	vim.api.nvim_buf_add_highlight(confirm_buf, ns, "Normal", 4, 11, 12)

	-- Prevent cursor movement
	local movement_keys = {
		"h",
		"j",
		"k",
		"l",
		"<Up>",
		"<Down>",
		"<Left>",
		"<Right>",
		"<C-f>",
		"<C-b>",
		"<C-u>",
		"<C-d>",
		"w",
		"b",
		"e",
		"ge",
		"0",
		"$",
		"^",
		"gg",
		"G",
	}

	local opts = { buffer = confirm_buf, nowait = true }
	for _, key in ipairs(movement_keys) do
		vim.keymap.set("n", key, function() end, opts)
	end

	-- Close confirmation window
	local function close_confirm()
		if vim.api.nvim_win_is_valid(confirm_win) then
			vim.api.nvim_win_close(confirm_win, true)
			vim.api.nvim_set_current_win(win_id)
		end
	end

	-- Handle responses
	vim.keymap.set("n", "y", function()
		close_confirm()
		M.delete_todo(todo_index)
		if callback then
			callback()
		end
	end, opts)

	vim.keymap.set("n", "Y", function()
		close_confirm()
		M.delete_todo(todo_index)
		if callback then
			callback()
		end
	end, opts)

	vim.keymap.set("n", "n", close_confirm, opts)
	vim.keymap.set("n", "N", close_confirm, opts)
	vim.keymap.set("n", "q", close_confirm, opts)
	vim.keymap.set("n", "<Esc>", close_confirm, opts)

	-- Auto-close on buffer leave
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = confirm_buf,
		callback = close_confirm,
		once = true,
	})
end
-- In state.lua, add these at the top with other local variables:
local deleted_todos = {}
local MAX_UNDO_HISTORY = 100

-- Add these functions to state.lua:
function M.store_deleted_todo(todo, index)
	table.insert(deleted_todos, 1, {
		todo = vim.deepcopy(todo),
		index = index,
		timestamp = os.time(),
	})
	-- Keep only the last MAX_UNDO_HISTORY deletions
	if #deleted_todos > MAX_UNDO_HISTORY then
		table.remove(deleted_todos)
	end
end

function M.undo_delete()
	if #deleted_todos == 0 then
		vim.notify("No more todos to restore", vim.log.levels.INFO)
		return false
	end

	local last_deleted = table.remove(deleted_todos, 1)

	-- If index is greater than current todos length, append to end
	local insert_index = math.min(last_deleted.index, #M.todos + 1)

	-- Insert the todo at the original position
	table.insert(M.todos, insert_index, last_deleted.todo)

	-- Save the updated todos
	M.save_todos()

	-- Return true to indicate successful undo
	return true
end

-- Modify the delete_todo function in state.lua:
function M.delete_todo(index)
	if M.todos[index] then
		local todo = M.todos[index]
		M.store_deleted_todo(todo, index)
		table.remove(M.todos, index)
		save_todos()
	end
end

-- Add to delete_completed in state.lua:
function M.delete_completed()
	local remaining_todos = {}
	local removed_count = 0

	for i, todo in ipairs(M.todos) do
		if todo.done then
			M.store_deleted_todo(todo, i - removed_count)
			removed_count = removed_count + 1
		else
			table.insert(remaining_todos, todo)
		end
	end

	M.todos = remaining_todos
	save_todos()
end

return M
