-- Declare vim locally at the top
local vim = vim

local M = {}
local config = require("dooing.config")

M.todos = {}

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
	if not todo.priority or not config.options.prioritization then
		return 0
	end

	-- Create a lookup table for valid priorities and their weights
	local priority_weights = {}
	for _, p in ipairs(config.options.priorities) do
		priority_weights[p.name] = p.weight or 1 -- Default weight of 1 if not specified
	end

	local score = 0
	for _, priority_name in ipairs(todo.priority) do
		-- Only count priorities that are defined in config
		local weight = priority_weights[priority_name]
		if weight then
			score = score + weight
		end
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

return M
