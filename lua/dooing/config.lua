-- In config.lua, add PRIORITIES to the defaults
local M = {}

M.defaults = {
	window = {
		width = 55,
		height = 20,
		border = "rounded",
		position = "center",
		padding = {
			top = 1,
			bottom = 1,
			left = 2,
			right = 2,
		},
	},
	quick_keys = true,
	notes = {
		icon = "󱞁",
	},
	timestamp = {
		enabled = true,
	},
	formatting = {
		pending = {
			icon = "○",
			format = { "notes_icon", "icon", "text", "ect", "due_date", "relative_time" },
		},
		in_progress = {
			icon = "◐",
			format = { "notes_icon", "icon", "text", "ect", "due_date", "relative_time" },
		},
		done = {
			icon = "✓",
			format = { "notes_icon", "icon", "text", "ect", "due_date", "relative_time" },
		},
	},
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
	priority_groups = {
		high = {
			members = { "important", "urgent" },
			color = nil,
			hl_group = "DiagnosticError",
		},
		medium = {
			members = { "important" },
			color = nil,
			hl_group = "DiagnosticWarn",
		},
		low = {
			members = { "urgent" },
			color = nil,
			hl_group = "DiagnosticInfo",
		},
	},
	hour_score_value = 1 / 8,
	done_sort_by_completed_time = false,
	nested_tasks = {
		enabled = true,
		indent = 2,
		retain_structure_on_complete = true,
		move_completed_to_end = true,
	},
	due_notifications = {
		enabled = true,
		on_startup = true,
		on_open = true,
	},
	save_path = vim.fn.stdpath("data") .. "/dooing_todos.json",
	pretty_print_json = false,
	per_project = {
		enabled = true,
		default_filename = "dooing.json",
		auto_gitignore = false,
		on_missing = "prompt",
		auto_open_project_todos = false,
	},
	keymaps = {
		toggle_window = "<leader>td",
		open_project_todo = "<leader>tD",
		show_due_notification = "<leader>tN",
		new_todo = "i",
		create_nested_task = "<leader>tn",
		toggle_todo = "x",
		delete_todo = "d",
		delete_completed = "D",
		close_window = "q",
		undo_delete = "u",
		add_due_date = "H",
		remove_due_date = "r",
		toggle_help = "?",
		toggle_tags = "t",
		toggle_priority = "<Space>",
		clear_filter = "c",
		edit_todo = "e",
		edit_tag = "e",
		edit_priorities = "p",
		delete_tag = "d",
		search_todos = "/",
		add_time_estimation = "T",
		remove_time_estimation = "R",
		import_todos = "I",
		export_todos = "E",
		remove_duplicates = "<leader>D",
		open_todo_scratchpad = "<leader>p",
		refresh_todos = "f",
	},
	calendar = {
		language = "en",
		start_day = "sunday", -- or "monday"
		icon = "",
		keymaps = {
			previous_day = "h",
			next_day = "l",
			previous_week = "k",
			next_week = "j",
			previous_month = "H",
			next_month = "L",
			select_day = "<CR>",
			close_calendar = "q",
		},
	},
	scratchpad = {
		syntax_highlight = "markdown",
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
