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
	if not todo.priority or not config.options.priorities or #config.options.priorities == 0 or todo.done then
		return 0
	end

	local score = 0
	for _, priority_name in ipairs(todo.priority) do
		score = score + (priority_weights[priority_name] or 0)
	end

	local current_time = os.time()
	if todo.due_at < current_time then
		score = score + config.options.due_score_offset
	end

	return score
end

function M.sort_todos()
	table.sort(M.todos, function(a, b)
		-- If priorities are configured, sort by priority first
		if config.options.priorities and #config.options.priorities > 0 then
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

return M
