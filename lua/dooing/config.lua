-- In config.lua, add PRIORITIES to the defaults
local M = {}

M.defaults = {
	window = {
		width = 40,
		height = 20,
		border = "rounded",
		padding = {
			top = 1,
			bottom = 1,
			left = 2,
			right = 2,
		},
	},
	icons = {
		pending = "○",
		done = "✓",
	},
	prioritization = false,
	priorities = {
		{
			name = "important and urgent",
			color = "DooingPriorityUrgentImportant",
			icon = "",
			hl_group = "DiagnosticError",
		},
		{
			name = "important and not urgent",
			color = "DooingPriorityImportant",
			icon = "",
			hl_group = "DiagnosticWarn",
		},
		{
			name = "not important and urgent",
			color = "DooingPriorityUrgent",
			icon = "",
			hl_group = "DiagnosticInfo",
		},
		{
			name = "not important and not urgent",
			color = "DooingPriorityNormal",
			icon = "",
			hl_group = "DiagnosticHint",
		},
	},
	save_path = vim.fn.stdpath("data") .. "/dooing_todos.json",
	keymaps = {
		toggle_window = "<leader>td",
		new_todo = "i",
		toggle_todo = "x",
		delete_todo = "d",
		delete_completed = "D",
		close_window = "q",
		toggle_help = "?",
		toggle_tags = "t",
		clear_filter = "c",
		edit_todo = "e",
		edit_tag = "e",
		delete_tag = "d",
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
