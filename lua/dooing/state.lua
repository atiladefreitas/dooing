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
		category = text:match("#(%w+)") or "",
		created_at = os.time(),
		priority = priority_names,
	})
	save_todos()
end

function M.toggle_todo(index)
	if M.todos[index] then
		M.todos[index].done = not M.todos[index].done
		save_todos()
	end
end

-- Parse date string in the format MM/DD/YYYY
-- @TODO: handle `format` -> a custom date format
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

-- Calculate priority score for a todo item
function M.get_priority_score(todo)
	if not todo.priority or not config.options.prioritization or todo.done then
		return 0
	end

	local score = 0
	for _, priority_name in ipairs(todo.priority) do
		score = score + (priority_weights[priority_name] or 0)
	end
	return score
end

function M.sort_todos()
	table.sort(M.todos, function(a, b)
		-- If prioritization is enabled, sort by priority first
		if config.options.prioritization then
			local a_score = M.get_priority_score(a)
			local b_score = M.get_priority_score(b)

			if a_score ~= b_score then
				return a_score > b_score -- Higher score = higher priority
			end
		end

		-- Then sort by completion status
		if a.done ~= b.done then
			return not a.done -- Undone items come first
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

-- Helper function to get the priority-based highlights
local function get_priority_highlights(todo)
	if not config.options.prioritization then
		return "DooingPending"
	end

	local score = M.get_priority_score(todo)
	for _, threshold in ipairs(config.options.priority_thresholds) do
		if score >= threshold.min and score <= threshold.max then
			return threshold.hl_group
		end
	end
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
	local todo_display_text = "   ○ " .. current_todo.text
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

return M
