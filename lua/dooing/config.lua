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
			name = "important",
			weight = 4,
		},
		{
			name = "urgent",
			weight = 2,
		},
	},
	priority_thresholds = {
		{
			min = 5, -- Corresponds to `urgent` and `important` tasks
			max = 999,
			color = nil,
			icon = "",
			hl_group = "DiagnosticError",
		},
		{
			min = 3, -- Corresponds to `important` tasks
			max = 4,
			color = nil,
			icon = "",
			hl_group = "DiagnosticWarn",
		},
		{
			min = 1, -- Corresponds to `urgent tasks`
			max = 2,
			color = nil,
			icon = "",
			hl_group = "DiagnosticInfo",
		},
		{
			min = 0,
			max = 0,
			color = nil,
			icon = "⚪",
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
		search_todos = "/",
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
