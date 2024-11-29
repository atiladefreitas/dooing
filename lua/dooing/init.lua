local M = {}
local config = require("dooing.config")
local ui = require("dooing.ui")
local state = require("dooing.state")

function M.setup(opts)
	config.setup(opts)
	state.load_todos()

	vim.api.nvim_create_user_command("Dooing", function(opts)
		local args = vim.split(opts.args, "%s+", { trimempty = true })
		if #args > 0 and args[1] == "add" then
			-- Remove the "add" keyword and join the rest as the todo text
			table.remove(args, 1)
			local todo_text = table.concat(args, " ")
			if todo_text ~= "" then
				state.add_todo(todo_text)
			end
		else
			ui.toggle_todo_window()
		end
	end, {
		desc = "Toggle Todo List window or add new todo",
		nargs = "*",
		complete = function(arglead, cmdline, cursorpos)
			local args = vim.split(cmdline, "%s+", { trimempty = true })
			if #args <= 2 then
				return { "add" }
			end
			return {}
		end,
	})

	-- Only set up keymap if it's enabled in config
	if config.options.keymaps.toggle_window then
		vim.keymap.set("n", config.options.keymaps.toggle_window, function()
			ui.toggle_todo_window()
		end, { desc = "Toggle Todo List" })
	end
end

return M
