-- Declare vim locally at the top
local vim = vim

local M = {}
local config = require("dooing.config")

-- Cache frequently accessed values
local priority_weights = {}

M.todos = {}
M.current_save_path = nil
M.current_context = "global" -- Track current context: "global" or project name

-- Update priority weights cache when config changes
local function update_priority_weights()
	priority_weights = {}
	for _, p in ipairs(config.options.priorities) do
		priority_weights[p.name] = p.weight or 1
	end
end

local function encode_json(value)
	local json_str = vim.json.encode(value, { sort_keys = true })

	if not config.options.pretty_print_json then
		return json_str
	end

	-- Try external formatters for pretty printing
	local formatters = {
		"jq -S .",
		"python3 -m json.tool --sort-keys",
		"python -m json.tool --sort-keys",
	}

	for _, cmd in ipairs(formatters) do
		local exe = cmd:match("^(%S+)")
		if exe and vim.fn.executable(exe) == 1 then
			local result = vim.fn.system(cmd, json_str)
			if vim.v.shell_error == 0 then
				return result
			end
		end
	end

	-- Fallback to compact JSON if no formatter available
	return json_str
end

local function save_todos()
	local save_path = M.current_save_path or config.options.save_path
	local file = io.open(save_path, "w")
	if file then
		file:write(encode_json(M.todos))
		file:close()
	end
end

-- Expose it as part of the module
M.save_todos = save_todos
M.save_todos_to_current_path = function()
	local save_path = M.current_save_path or config.options.save_path
	local file = io.open(save_path, "w")
	if file then
		file:write(encode_json(M.todos))
		file:close()
	end
end

-- Get git root directory
function M.get_git_root()
	local devnull = (vim.uv.os_uname().sysname == "Windows_NT") and "NUL" or "/dev/null"
	local handle = io.popen("git rev-parse --show-toplevel 2>" .. devnull)
	if not handle then
		return nil
	end

	local result = handle:read("*a")
	handle:close()

	if result and result ~= "" then
		return vim.trim(result)
	end

	return nil
end

-- Get project todo file path
function M.get_project_todo_path()
	local git_root = M.get_git_root()
	if not git_root then
		return nil
	end

	return git_root .. "/" .. config.options.per_project.default_filename
end

-- Check if project todo file exists
function M.project_todo_exists()
	local path = M.get_project_todo_path()
	if not path then
		return false
	end

	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	end
	return false
end

-- Check if project has todos (file exists and contains todos)
function M.has_project_todos()
	-- Check if we're in a git repository
	local git_root = M.get_git_root()
	if not git_root then
		return false
	end

	-- Check if project todo file exists
	local path = M.get_project_todo_path()
	if not path then
		return false
	end

	-- Check if file exists and has content
	local file = io.open(path, "r")
	if not file then
		return false
	end

	local content = file:read("*all")
	file:close()

	-- Check if file has actual todos
	if not content or content == "" then
		return false
	end

	-- Try to parse the JSON content
	local success, todos = pcall(vim.fn.json_decode, content)
	if not success or not todos or type(todos) ~= "table" or #todos == 0 then
		return false
	end

	return true
end

-- Load todos from specific path
function M.load_todos_from_path(path)
	M.current_save_path = path

	-- Set context based on path
	local git_root = M.get_git_root()
	if git_root then
		M.current_context = vim.fn.fnamemodify(git_root, ":t")
	else
		M.current_context = "project"
	end

	update_priority_weights()
	local file = io.open(path, "r")
	if file then
		local content = file:read("*all")
		file:close()
		if content and content ~= "" then
			M.todos = vim.fn.json_decode(content)
			-- Migrate existing todos to new format
			M.migrate_todos()
		else
			M.todos = {}
		end
	else
		M.todos = {}
	end
end

-- Get window title based on current context
function M.get_window_title()
	if M.current_context == "global" then
		return " Global to-dos "
	else
		return " " .. M.current_context .. " to-dos "
	end
end

-- Add gitignore entry
function M.add_to_gitignore(filename)
	local git_root = M.get_git_root()
	if not git_root then
		return false, "Not in a git repository"
	end

	local gitignore_path = git_root .. "/.gitignore"
	local file = io.open(gitignore_path, "r")
	local content = ""

	if file then
		content = file:read("*all")
		file:close()

		-- Check if already ignored
		if content:find(filename, 1, true) then
			return true, "Already in .gitignore"
		end
	end

	-- Append to gitignore
	file = io.open(gitignore_path, "a")
	if file then
		if content ~= "" and not content:match("\n$") then
			file:write("\n")
		end
		file:write(filename .. "\n")
		file:close()
		return true, "Added to .gitignore"
	end

	return false, "Failed to write to .gitignore"
end

function M.load_todos()
	M.current_save_path = config.options.save_path
	M.current_context = "global"
	update_priority_weights()
	local file = io.open(M.current_save_path, "r")
	if file then
		local content = file:read("*all")
		file:close()
		if content and content ~= "" then
			M.todos = vim.fn.json_decode(content)
			-- Migrate existing todos to new format
			M.migrate_todos()
		else
			M.todos = {}
		end
	else
		M.todos = {}
	end
end

-- Migrate existing todos to support nested structure
function M.migrate_todos()
	for i, todo in ipairs(M.todos) do
		-- Add unique ID if missing
		if not todo.id then
			todo.id = os.time() .. "_" .. i .. "_" .. math.random(1000, 9999)
		end

		-- Add nesting fields if missing
		if todo.parent_id == nil then
			todo.parent_id = nil
		end
		if todo.depth == nil then
			todo.depth = 0
		end
	end
	-- Save migrated data
	save_todos()
end

function M.add_todo(text, priority_names)
	-- Generate unique ID using timestamp and random component
	local unique_id = os.time() .. "_" .. math.random(1000, 9999)

	table.insert(M.todos, {
		id = unique_id,
		text = text,
		done = false,
		in_progress = false,
		category = text:match("#(%w+)") or "",
		created_at = os.time(),
		priorities = priority_names,
		estimated_hours = nil, -- Add estimated_hours field
		notes = "",
		parent_id = nil, -- For nested tasks: ID of parent task
		depth = 0, -- Nesting depth (0 = top level, 1 = first level subtask, etc.)
	})
	save_todos()
end

-- Add nested todo under a parent task
function M.add_nested_todo(text, parent_index, priority_names)
	-- Check if nested tasks are enabled
	if not config.options.nested_tasks or not config.options.nested_tasks.enabled then
		return false, "Nested tasks are disabled"
	end

	if not M.todos[parent_index] then
		return false, "Parent todo not found"
	end

	local parent_todo = M.todos[parent_index]
	local parent_depth = parent_todo.depth or 0
	local parent_id = parent_todo.id -- Use stable ID instead of index

	-- Generate unique ID for nested todo
	local unique_id = os.time() .. "_" .. math.random(1000, 9999)

	-- Create nested todo
	local nested_todo = {
		id = unique_id,
		text = text,
		done = false,
		in_progress = false,
		category = text:match("#(%w+)") or "",
		created_at = os.time(),
		priorities = priority_names,
		estimated_hours = nil,
		notes = "",
		parent_id = parent_id,
		depth = parent_depth + 1,
	}

	-- Insert after parent and its existing children
	local insert_position = parent_index + 1
	while insert_position <= #M.todos and M.todos[insert_position].parent_id == parent_id do
		insert_position = insert_position + 1
	end

	table.insert(M.todos, insert_position, nested_todo)
	save_todos()
	return true
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
			-- Track completion time
			M.todos[index].completed_at = os.time()
		else
			-- From done back to pending
			M.todos[index].done = false
			M.todos[index].completed_at = nil
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
		local date_table = os.date("*t", timestamp)
		date_table.hour = 23
		date_table.min = 59
		date_table.sec = 59
		timestamp = os.time(date_table)

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
	if M.nested_tasks_enabled() then
		M.delete_completed_structure_aware()
	else
		M.delete_completed_flat()
	end
end

-- Original delete completed (preserves old behavior when nested tasks disabled)
function M.delete_completed_flat()
	local remaining_todos = {}
	for _, todo in ipairs(M.todos) do
		if not todo.done then
			table.insert(remaining_todos, todo)
		end
	end
	M.todos = remaining_todos
	save_todos()
end

-- Structure-aware delete completed that handles orphaned nested tasks
function M.delete_completed_structure_aware()
	local remaining_todos = {}
	local orphaned_todos = {}

	-- First pass: collect remaining todos and identify orphans
	for _, todo in ipairs(M.todos) do
		if not todo.done then
			table.insert(remaining_todos, todo)
		elseif todo.parent_id then
			-- This is a completed nested task, check if parent still exists
			local parent_exists = false
			for _, remaining in ipairs(remaining_todos) do
				if remaining.id == todo.parent_id then
					parent_exists = true
					break
				end
			end
			-- If parent doesn't exist yet, we'll check in the final list
			table.insert(orphaned_todos, todo)
		end
	end

	-- Second pass: handle orphaned nested tasks
	for _, orphan in ipairs(orphaned_todos) do
		local parent_exists = false
		for _, remaining in ipairs(remaining_todos) do
			if remaining.id == orphan.parent_id then
				parent_exists = true
				break
			end
		end

		if parent_exists then
			-- Parent still exists, keep the orphaned task
			table.insert(remaining_todos, orphan)
		else
			-- Parent was deleted, promote orphan to top-level if not completed
			if not orphan.done then
				orphan.parent_id = nil
				orphan.depth = 0
				table.insert(remaining_todos, orphan)
			end
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

-- Helper function to check if nested tasks are enabled
function M.nested_tasks_enabled()
	return config.options.nested_tasks
		and config.options.nested_tasks.enabled
		and config.options.nested_tasks.retain_structure_on_complete
end

function M.sort_todos()
	-- Check if nested tasks are enabled and structure should be preserved
	if M.nested_tasks_enabled() then
		M.sort_todos_with_structure()
	else
		M.sort_todos_flat()
	end
end

-- Original flat sorting (preserves old behavior when nested tasks disabled)
function M.sort_todos_flat()
	table.sort(M.todos, function(a, b)
		-- First sort by completion status
		if a.done ~= b.done then
			return not a.done -- Undone items come first
		end

		-- For completed items, sort by completion time (most recent first)
		if config.options.done_sort_by_completed_time and a.done and b.done then
			-- Use completed_at if available, otherwise fall back to created_at
			local a_time = a.completed_at or a.created_at or 0
			local b_time = b.completed_at or b.created_at or 0
			return a_time > b_time -- Most recently completed first
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

-- Structure-preserving sorting for nested tasks (supports multi-level nesting)
function M.sort_todos_with_structure()
	-- Group todos by their hierarchical structure
	local top_level = {}
	local nested_groups = {}

	-- Separate top-level todos and group nested ones by parent
	for i, todo in ipairs(M.todos) do
		if not todo.parent_id then
			-- Top-level todo
			table.insert(top_level, { todo = todo, original_index = i })
		else
			-- Nested todo, group by its direct parent_id
			if not nested_groups[todo.parent_id] then
				nested_groups[todo.parent_id] = {}
			end
			table.insert(nested_groups[todo.parent_id], { todo = todo, original_index = i })
		end
	end

	-- Sort top-level todos
	table.sort(top_level, M.compare_todos)

	-- Sort each nested group using the appropriate comparison
	for _, children in pairs(nested_groups) do
		if config.options.nested_tasks.move_completed_to_end then
			-- Sort children but keep completed at end within their group
			table.sort(children, M.compare_todos)
		else
			-- Sort children without moving completed ones
			table.sort(children, function(a, b)
				return M.compare_todos_ignore_completion(a, b)
			end)
		end
	end

	-- Recursively add a parent and all of its descendants in depth-first order
	local new_todos = {}
	local function add_with_children(parent_todo)
		-- Insert the parent itself
		table.insert(new_todos, parent_todo)

		-- Then insert all its direct children (if any), each followed by their own children
		local children = nested_groups[parent_todo.id]
		if children then
			for _, child_data in ipairs(children) do
				add_with_children(child_data.todo)
			end
		end
	end

	for _, parent_data in ipairs(top_level) do
		add_with_children(parent_data.todo)
	end

	M.todos = new_todos
end

-- Comparison function for todos
function M.compare_todos(a, b)
	local todo_a = a.todo
	local todo_b = b.todo

	-- First sort by completion status
	if todo_a.done ~= todo_b.done then
		return not todo_a.done -- Undone items come first
	end

	-- For completed items, sort by completion time (most recent first)
	if config.options.done_sort_by_completed_time and todo_a.done and todo_b.done then
		local a_time = todo_a.completed_at or todo_a.created_at or 0
		local b_time = todo_b.completed_at or todo_b.created_at or 0
		return a_time > b_time
	end

	-- Then sort by priority score if configured
	if config.options.priorities and #config.options.priorities > 0 then
		local a_score = M.get_priority_score(todo_a)
		local b_score = M.get_priority_score(todo_b)

		if a_score ~= b_score then
			return a_score > b_score
		end
	end

	-- Then sort by due date if both have one
	if todo_a.due_at and todo_b.due_at then
		if todo_a.due_at ~= todo_b.due_at then
			return todo_a.due_at < todo_b.due_at
		end
	elseif todo_a.due_at then
		return true
	elseif todo_b.due_at then
		return false
	end

	-- Finally sort by creation time
	return todo_a.created_at < todo_b.created_at
end

-- Comparison function that ignores completion status (for nested tasks when move_completed_to_end is false)
function M.compare_todos_ignore_completion(a, b)
	local todo_a = a.todo
	local todo_b = b.todo

	-- Sort by priority score if configured
	if config.options.priorities and #config.options.priorities > 0 then
		local a_score = M.get_priority_score(todo_a)
		local b_score = M.get_priority_score(todo_b)

		if a_score ~= b_score then
			return a_score > b_score
		end
	end

	-- Then sort by due date if both have one
	if todo_a.due_at and todo_b.due_at then
		if todo_a.due_at ~= todo_b.due_at then
			return todo_a.due_at < todo_b.due_at
		end
	elseif todo_a.due_at then
		return true
	elseif todo_b.due_at then
		return false
	end

	-- Finally sort by creation time
	return todo_a.created_at < todo_b.created_at
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

	local json_content = encode_json(M.todos)
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
		border = config.options.window.border,
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

-- Get count of due and overdue todos
function M.get_due_count()
	local now = os.time()
	local today_start = os.time(os.date("*t", now))
	local today_end = today_start + 86400 -- 24 hours

	local due_today = 0
	local overdue = 0

	for _, todo in ipairs(M.todos) do
		if todo.due_at and not todo.done then
			if todo.due_at < today_start then
				overdue = overdue + 1
			elseif todo.due_at <= today_end then
				due_today = due_today + 1
			end
		end
	end

	return {
		overdue = overdue,
		due_today = due_today,
		total = overdue + due_today,
	}
end

-- Show due items notification
function M.show_due_notification()
	local due_count = M.get_due_count()

	if due_count.total == 0 then
		return -- Don't show notification if nothing is due
	end

	local config = require("dooing.config")
	if not config.options.due_notifications or not config.options.due_notifications.enabled then
		return
	end

	local message = string.format("%d item%s due", due_count.total, due_count.total == 1 and "" or "s")

	vim.notify(message, vim.log.levels.ERROR, { title = "Dooing" })
end

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
