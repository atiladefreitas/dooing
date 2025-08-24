local M = {}
local config = require("dooing.config")
local ui = require("dooing.ui")
local state = require("dooing.state")

function M.setup(opts)
	config.setup(opts)
	state.load_todos()

	-- Auto-open project todos if configured
	if config.options.per_project.enabled and config.options.per_project.auto_open_project_todos then
		-- Defer to avoid startup conflicts
		vim.defer_fn(function()
			-- Only auto-open if no todo window is already open
			if not ui.is_window_open() and state.has_project_todos() then
				-- Load project todos
				local project_path = state.get_project_todo_path()
				state.load_todos_from_path(project_path)
				
				-- Open the todo window
				ui.toggle_todo_window()
				
				-- Notify user
				local git_root = state.get_git_root()
				local project_name = vim.fn.fnamemodify(git_root, ":t")
				vim.notify("Auto-opened project todos for: " .. project_name, vim.log.levels.INFO, { title = "Dooing" })
			end
		end, 100) -- Small delay to ensure everything is loaded
	end

	vim.api.nvim_create_user_command("Dooing", function(opts)
		local args = vim.split(opts.args, "%s+", { trimempty = true })
		if #args == 0 then
			M.open_global_todo()
			return
		end

		local command = args[1]
		table.remove(args, 1) -- Remove command

		if command == "add" then
			-- Parse priorities if -p or --priorities flag is present
			local priorities = nil
			local todo_text = ""

			local i = 1
			while i <= #args do
				if args[i] == "-p" or args[i] == "--priorities" then
					if i + 1 <= #args then
						-- Get and validate priorities
						local priority_str = args[i + 1]
						local priority_list = vim.split(priority_str, ",", { trimempty = true })

						-- Validate each priority against config
						local valid_priorities = {}
						local invalid_priorities = {}
						for _, p in ipairs(priority_list) do
							local is_valid = false
							for _, config_p in ipairs(config.options.priorities) do
								if p == config_p.name then
									is_valid = true
									table.insert(valid_priorities, p)
									break
								end
							end
							if not is_valid then
								table.insert(invalid_priorities, p)
							end
						end

						-- Notify about invalid priorities
						if #invalid_priorities > 0 then
							vim.notify(
								"Invalid priorities: " .. table.concat(invalid_priorities, ", "),
								vim.log.levels.WARN,
								{
									title = "Dooing",
								}
							)
						end

						if #valid_priorities > 0 then
							priorities = valid_priorities
						end

						i = i + 2 -- Skip priority flag and value
					else
						vim.notify("Missing priority value after " .. args[i], vim.log.levels.ERROR, {
							title = "Dooing",
						})
						return
					end
				else
					todo_text = todo_text .. " " .. args[i]
					i = i + 1
				end
			end

			todo_text = vim.trim(todo_text)
			if todo_text ~= "" then
				state.add_todo(todo_text, priorities)
				local msg = "Todo created: " .. todo_text
				if priorities then
					msg = msg .. " (priorities: " .. table.concat(priorities, ", ") .. ")"
				end
				vim.notify(msg, vim.log.levels.INFO, {
					title = "Dooing",
				})
			end
		elseif command == "list" then
			-- Print all todos with their indices
			for i, todo in ipairs(state.todos) do
				local status = todo.done and "✓" or "○"

				-- Build metadata string
				local metadata = {}
				if todo.priorities and #todo.priorities > 0 then
					table.insert(metadata, "priorities: " .. table.concat(todo.priorities, ", "))
				end
				if todo.due_date then
					table.insert(metadata, "due: " .. todo.due_date)
				end
				if todo.estimated_hours then
					table.insert(metadata, string.format("estimate: %.1fh", todo.estimated_hours))
				end

				local score = state.get_priority_score(todo)
				table.insert(metadata, string.format("score: %.1f", score))

				local metadata_text = #metadata > 0 and " (" .. table.concat(metadata, ", ") .. ")" or ""

				vim.notify(string.format("%d. %s %s%s", i, status, todo.text, metadata_text), vim.log.levels.INFO)
			end
		elseif command == "set" then
			if #args < 3 then
				vim.notify("Usage: Dooing set <index> <field> <value>", vim.log.levels.ERROR)
				return
			end

			local index = tonumber(args[1])
			if not index or not state.todos[index] then
				vim.notify("Invalid todo index: " .. args[1], vim.log.levels.ERROR)
				return
			end

			local field = args[2]
			local value = args[3]

			if field == "priorities" then
				-- Handle priority setting
				if value == "nil" then
					-- Clear priorities
					state.todos[index].priorities = nil
					state.save_todos()
					vim.notify("Cleared priorities for todo " .. index, vim.log.levels.INFO)
				else
					-- Handle priority setting
					local priority_list = vim.split(value, ",", { trimempty = true })
					local valid_priorities = {}
					local invalid_priorities = {}

					for _, p in ipairs(priority_list) do
						local is_valid = false
						for _, config_p in ipairs(config.options.priorities) do
							if p == config_p.name then
								is_valid = true
								table.insert(valid_priorities, p)
								break
							end
						end
						if not is_valid then
							table.insert(invalid_priorities, p)
						end
					end

					if #invalid_priorities > 0 then
						vim.notify(
							"Invalid priorities: " .. table.concat(invalid_priorities, ", "),
							vim.log.levels.WARN
						)
					end

					if #valid_priorities > 0 then
						state.todos[index].priorities = valid_priorities
						state.save_todos()
						vim.notify("Updated priorities for todo " .. index, vim.log.levels.INFO)
					end
				end
			elseif field == "ect" then
				-- Handle estimated completion time setting
				local hours, err = ui.parse_time_estimation(value)
				if hours then
					state.todos[index].estimated_hours = hours
					state.save_todos()
					vim.notify("Updated estimated completion time for todo " .. index, vim.log.levels.INFO)
				else
					vim.notify("Error: " .. (err or "Invalid time format"), vim.log.levels.ERROR)
				end
			else
				vim.notify("Unknown field: " .. field, vim.log.levels.ERROR)
			end
		else
			M.open_global_todo()
		end
	end, {
		desc = "Toggle Global Todo List window or add new todo",
		nargs = "*",
		complete = function(arglead, cmdline, cursorpos)
			local args = vim.split(cmdline, "%s+", { trimempty = true })
			if #args <= 2 then
				return { "add", "list", "set" }
			elseif args[1] == "set" and #args == 3 then
				return { "priorities", "ect" }
			elseif args[1] == "set" and (args[3] == "priorities") then
				local priorities = { "nil" } -- Add nil as an option
				for _, p in ipairs(config.options.priorities) do
					table.insert(priorities, p.name)
				end
				return priorities
			elseif args[#args - 1] == "-p" or args[#args - 1] == "--priorities" then
				-- Return available priorities for completion
				local priorities = {}
				for _, p in ipairs(config.options.priorities) do
					table.insert(priorities, p.name)
				end
				return priorities
			elseif #args == 3 then
				return { "-p", "--priorities" }
			end
			return {}
		end,
	})

	-- Create DooingLocal command for project todos
	vim.api.nvim_create_user_command("DooingLocal", function()
		M.open_project_todo()
	end, {
		desc = "Open project-specific todo list",
	})

	-- Only set up keymap if it's enabled in config
	if config.options.keymaps.toggle_window then
		vim.keymap.set("n", config.options.keymaps.toggle_window, function()
			M.open_global_todo()
		end, { desc = "Toggle Global Todo List" })
	end
	
	-- Set up project todo keymap if enabled
	if config.options.keymaps.open_project_todo and config.options.per_project.enabled then
		vim.keymap.set("n", config.options.keymaps.open_project_todo, function()
			M.open_project_todo()
		end, { desc = "Open Local Project Todo List" })
	end
end

-- Open global todo list
function M.open_global_todo()
	-- Always load global todos regardless of current state
	state.load_todos()
	
	-- If window is already open, update title and render, otherwise toggle
	if ui.is_window_open() then
		local window = require("dooing.ui.window")
		window.update_window_title()
		ui.render_todos()
	else
		ui.toggle_todo_window()
	end
	
	vim.notify("Opened global todos", vim.log.levels.INFO, { title = "Dooing" })
end

-- Open project-specific todo list
function M.open_project_todo()
	if not config.options.per_project.enabled then
		vim.notify("Per-project todos are disabled", vim.log.levels.WARN, { title = "Dooing" })
		return
	end
	
	local git_root = state.get_git_root()
	if not git_root then
		vim.notify("Not in a git repository", vim.log.levels.ERROR, { title = "Dooing" })
		return
	end
	
	local project_path = state.get_project_todo_path()
	
	if state.project_todo_exists() then
		-- Load existing project todos
		state.load_todos_from_path(project_path)
		
		-- If window is already open, update title and render, otherwise toggle
		if ui.is_window_open() then
			local window = require("dooing.ui.window")
			window.update_window_title()
			ui.render_todos()
		else
			ui.toggle_todo_window()
		end
		
		local project_name = vim.fn.fnamemodify(git_root, ":t")
		vim.notify("Opened project todos for: " .. project_name, vim.log.levels.INFO, { title = "Dooing" })
	else
		-- Handle missing project todo file
		if config.options.per_project.on_missing == "auto_create" then
			-- Auto-create the file
			M.create_project_todo(project_path)
		elseif config.options.per_project.on_missing == "prompt" then
			-- Prompt user
			M.prompt_create_project_todo(project_path)
		end
	end
end

-- Create project todo file
function M.create_project_todo(path, custom_filename)
	local final_path = path
	if custom_filename then
		local git_root = state.get_git_root()
		final_path = git_root .. "/" .. custom_filename
	end
	
	-- Create empty todo file
	state.load_todos_from_path(final_path)
	state.save_todos_to_current_path()
	
	-- Handle gitignore
	local filename = vim.fn.fnamemodify(final_path, ":t")
	if config.options.per_project.auto_gitignore == true then
		local success, msg = state.add_to_gitignore(filename)
		if success then
			vim.notify("Created " .. filename .. " and " .. msg, vim.log.levels.INFO, { title = "Dooing" })
		else
			vim.notify("Created " .. filename .. " but failed to add to .gitignore: " .. msg, vim.log.levels.WARN, { title = "Dooing" })
		end
	elseif config.options.per_project.auto_gitignore == "prompt" then
		vim.ui.select({"Yes", "No"}, {
			prompt = "Add " .. filename .. " to .gitignore?",
		}, function(choice)
			if choice == "Yes" then
				local success, msg = state.add_to_gitignore(filename)
				vim.notify(msg, success and vim.log.levels.INFO or vim.log.levels.WARN, { title = "Dooing" })
			end
		end)
	else
		vim.notify("Created " .. filename .. ". Run 'echo \"" .. filename .. "\" >> .gitignore' to ignore it.", 
			vim.log.levels.INFO, { title = "Dooing" })
	end
	
	-- Open the todo window with updated title
	if ui.is_window_open() then
		local window = require("dooing.ui.window")
		window.update_window_title()
		ui.render_todos()
	else
		ui.toggle_todo_window()
	end
	
	-- Notify about project todos
	local git_root = state.get_git_root()
	local project_name = vim.fn.fnamemodify(git_root, ":t")
	vim.notify("Opened project todos for: " .. project_name, vim.log.levels.INFO, { title = "Dooing" })
end

-- Prompt user to create project todo
function M.prompt_create_project_todo(path)
	vim.ui.select({"Yes", "No"}, {
		prompt = "No local TODO found. Create one?",
	}, function(choice)
		if choice == "Yes" then
			vim.ui.input({
				prompt = "Filename (default: " .. config.options.per_project.default_filename .. "): ",
				default = "",
			}, function(input)
				if input == nil then
					return -- User cancelled
				end
				
				local filename = vim.trim(input)
				if filename == "" then
					filename = config.options.per_project.default_filename
				end
				
				M.create_project_todo(path, filename)
			end)
		end
	end)
end

return M
