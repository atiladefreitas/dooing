-- In config.lua, add PRIORITIES to the defaults
local M = {}

M.defaults = {
	window = {
		-- Size of the todo window: either a table `{ width = <n>, height = <n> }`
		-- or a function returning such a table. The function form is evaluated every
		-- time the window is opened, which allows sizes that adapt to the current
		-- editor dimensions, e.g.
		--   dimensions = function()
		--     return { width = math.floor(vim.o.columns * 0.4), height = math.floor(vim.o.lines * 0.6) }
		--   end
		dimensions = {
			width = 55,
			height = 20,
		},
		border = "rounded",
		zindex = 50,
		position = "center",
		padding = {
			top = 1,
			bottom = 1,
			left = 2,
			right = 2,
		},
	},
	-- Opt-in redesigned interface. `style = "classic"` (the default) keeps the
	-- original rendering untouched; `style = "modern"` enables the reworked
	-- layout. The individual toggles below only apply to the modern style and
	-- can each be turned off to mix and match.
	ui = {
		style = "classic", -- "classic" | "modern"
		sections = true, -- group top-level todos under status headings
		priority_bar = true, -- colored marker instead of coloring the whole row
		tree_connectors = true, -- draw ├─ / └─ / │ guides for nested tasks
		note_preview = true, -- show the first line of a todo's notes beneath it
		progress = true, -- progress bar in the title, summary in the footer
		compact_quick_keys = true, -- single-strip quick keys instead of the tall panel
		section_titles = {
			in_progress = "IN PROGRESS",
			pending = "PENDING",
			done = "DONE",
		},
		icons = {
			priority_bar = "▎",
			overdue = "󰀦",
			progress_on = "▰",
			progress_off = "▱",
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
		inherit_priority = false,
	},
	due_notifications = {
		enabled = true,
		on_startup = true,
		on_open = true,
	},
	save_path = vim.fn.stdpath("data") .. "/dooing_todos.json",
	pretty_print_json = false,
	-- The LAN share/sync server (see docs/SYNC-PROTOCOL.md). Started by the
	-- share keymap as before; these settings shape how it behaves.
	sync = {
		server = {
			-- Keep the server running for paired devices (two-way sync).
			--   "auto"  start on setup IF a device has been paired (the QR
			--           share flow still starts it on demand either way)
			--   true    always start on setup
			--   false   never start automatically; :DooingServe only
			enabled = "auto",
			autostart = true, -- start on setup when enabled resolves true
			port = 7283,
			bind = "0.0.0.0", -- "127.0.0.1" for tunnel-only setups
			-- v1 compatibility: serve GET /todos and /blocks without a device
			-- token, as older app builds expect. Deprecated; will default to
			-- false one release after v2 pairing ships in the app. Browser
			-- attacks are blocked regardless (Host/Origin guards, no CORS).
			allow_v1 = true,
		},
		conflict = {
			-- How many losing versions to keep for :DooingSyncRestore
			trail_limit = 50,
		},
	},
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

-- Used when `window.dimensions` cannot be resolved to usable values
local FALLBACK_DIMENSIONS = { width = 55, height = 20 }

-- Extracts width/height from a dimensions table, accepting both the named form
-- `{ width = 55, height = 20 }` and the positional form `{ 55, 20 }`
local function unpack_dimensions(value)
	if type(value) ~= "table" then
		return nil
	end
	local width = value.width or value[1]
	local height = value.height or value[2]
	if type(width) ~= "number" or type(height) ~= "number" then
		return nil
	end
	return { width = width, height = height }
end

-- Folds the deprecated `window.width` / `window.height` options into
-- `window.dimensions` so that existing user configurations keep working
local function migrate_legacy_dimensions(opts)
	local user_window = opts and opts.window
	if type(user_window) ~= "table" then
		return
	end
	if user_window.width == nil and user_window.height == nil then
		return
	end

	-- An explicit `dimensions` always wins over the legacy keys
	if user_window.dimensions == nil then
		local defaults = M.defaults.window.dimensions
		M.options.window.dimensions = {
			width = user_window.width or defaults.width,
			height = user_window.height or defaults.height,
		}
	end

	-- Drop the legacy keys to keep a single source of truth
	M.options.window.width = nil
	M.options.window.height = nil

	vim.notify(
		"dooing: `window.width` / `window.height` are deprecated, use "
			.. "`window.dimensions = { width = <n>, height = <n> }` instead "
			.. "(a function returning such a table is also supported)",
		vim.log.levels.WARN
	)
end

---Resolves `window.dimensions` into concrete cell counts.
---
---`window.dimensions` may be either
---  * a table:    `{ width = 55, height = 20 }`, or
---  * a function: `function() return { width = ..., height = ... } end`
---
---The function form is evaluated on every call, so the returned size may depend
---on the current editor dimensions (`vim.o.columns` / `vim.o.lines`).
---@return { width: integer, height: integer }
function M.get_window_dimensions()
	local value = (M.options.window or {}).dimensions

	if type(value) == "function" then
		local ok, result = pcall(value)
		if not ok then
			vim.notify("dooing: `window.dimensions` function failed: " .. tostring(result), vim.log.levels.ERROR)
			result = nil
		end
		value = result
	end

	local dimensions = unpack_dimensions(value)
	if not dimensions then
		if value ~= nil then
			vim.notify(
				"dooing: `window.dimensions` must be (or return) a table "
					.. "`{ width = <n>, height = <n> }`; falling back to defaults",
				vim.log.levels.WARN
			)
		end
		dimensions = FALLBACK_DIMENSIONS
	end

	-- Clamp to the space actually available, keeping at least one cell
	local max_width = math.max(vim.o.columns, 1)
	local max_height = math.max(vim.o.lines - 4, 1) -- room for borders, statusline and cmdline
	return {
		width = math.min(math.max(math.floor(dimensions.width), 1), max_width),
		height = math.min(math.max(math.floor(dimensions.height), 1), max_height),
	}
end

---Whether the redesigned ("modern") interface is enabled
---@return boolean
function M.is_modern()
	local ui = M.options.ui
	return type(ui) == "table" and ui.style == "modern"
end

---Whether a modern sub-feature is active. Every sub-feature additionally
---requires `ui.style == "modern"`, so the classic layout is never affected.
---@param name string key in `ui`, e.g. "sections"
---@return boolean
function M.modern_feature(name)
	if not M.is_modern() then
		return false
	end
	return M.options.ui[name] ~= false
end

---Reads an icon from `ui.icons`, falling back to the shipped default
---@param name string
---@return string
function M.ui_icon(name)
	local icons = (M.options.ui or {}).icons or {}
	local value = icons[name]
	if type(value) == "string" then
		return value
	end
	return M.defaults.ui.icons[name] or ""
end

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
	migrate_legacy_dimensions(opts)
end

return M
