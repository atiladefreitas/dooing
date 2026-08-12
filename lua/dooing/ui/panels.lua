---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Modern sub-windows: centered input, help, tags and search.
--
-- Everything here is only reached when `ui.style = "modern"`; the classic
-- implementations in `ui/components.lua` are left untouched. Each panel is
-- centered on the editor and sized from its own content, rather than being
-- positioned against a hard-coded assumption about the main window's width.

local M = {}

local constants = require("dooing.ui.constants")
local config = require("dooing.config")
local state = require("dooing.state")
local utils = require("dooing.ui.utils")

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

---Editor dimensions, falling back to `vim.o` when no UI is attached
local function editor_size()
	local ui = vim.api.nvim_list_uis()[1]
	if ui then
		return ui.width, ui.height
	end
	return vim.o.columns, vim.o.lines
end

---Window options for a float centered on the editor, clamped to fit.
---@param width number desired width
---@param height number desired height
---@param opts table|nil { zindex_offset, title, footer }
---@return table
function M.centered(width, height, opts)
	opts = opts or {}
	local editor_width, editor_height = editor_size()

	-- Leave room for the border, plus the statusline and cmdline
	width = math.max(math.min(width, editor_width - 4), 10)
	height = math.max(math.min(height, editor_height - 6), 1)

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(math.floor((editor_height - height) / 2) - 1, 0),
		col = math.max(math.floor((editor_width - width) / 2), 0),
		style = "minimal",
		border = config.options.window.border,
		zindex = config.options.window.zindex + (opts.zindex_offset or 3),
	}

	if opts.title then
		win_opts.title = opts.title
		win_opts.title_pos = "center"
	end
	if opts.footer then
		win_opts.footer = opts.footer
		win_opts.footer_pos = "center"
	end

	return win_opts
end

---Returns focus to the main todo window if it is still open
local function focus_main()
	if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
		vim.api.nvim_set_current_win(constants.win_id)
	end
end

--------------------------------------------------------------------------------
-- Centered input
--------------------------------------------------------------------------------

---A centered single-line input box.
---
---Used instead of `vim.ui.input` in the modern style so prompts appear in the
---middle of the screen next to the todo list, rather than down on the cmdline.
---@param opts table { title, default, width, footer }
---@param on_confirm fun(value: string|nil)
function M.input(opts, on_confirm)
	opts = opts or {}
	local default = opts.default or ""

	local editor_width = select(1, editor_size())
	local width = opts.width or math.max(math.min(60, editor_width - 10), 30)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " " .. default })

	local win = vim.api.nvim_open_win(
		buf,
		true,
		M.centered(width, 1, {
			zindex_offset = 4,
			title = opts.title or " Input ",
			footer = opts.footer or " <CR> confirm · <Esc> cancel ",
		})
	)

	vim.api.nvim_win_set_option(win, "wrap", false)
	vim.api.nvim_win_set_option(win, "cursorline", false)

	local finished = false

	local function close()
		if finished then
			return
		end
		finished = true
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end

	local function confirm()
		if finished then
			return
		end
		local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
		-- Strip the single leading padding space, then trim
		local value = line:gsub("^ ", ""):gsub("^%s+", ""):gsub("%s+$", "")
		vim.cmd("stopinsert")
		close()
		focus_main()
		on_confirm(value ~= "" and value or nil)
	end

	local function cancel()
		if finished then
			return
		end
		vim.cmd("stopinsert")
		close()
		focus_main()
		on_confirm(nil)
	end

	local keyopts = { buffer = buf, nowait = true }
	vim.keymap.set({ "n", "i" }, "<CR>", confirm, keyopts)
	vim.keymap.set("n", "<Esc>", cancel, keyopts)
	vim.keymap.set("i", "<C-c>", cancel, keyopts)
	vim.keymap.set("n", "q", cancel, keyopts)

	-- Closing the window any other way counts as cancelling
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			if not finished then
				finished = true
				vim.schedule(function()
					focus_main()
					on_confirm(nil)
				end)
			end
		end,
	})

	vim.schedule(function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_set_cursor(win, { 1, #(" " .. default) })
			vim.cmd("startinsert!")
		end
	end)
end

---Prompts for a line of text, using the centered input in the modern style and
---`vim.ui.input` otherwise.
---@param opts table { title, prompt, default }
---@param on_confirm fun(value: string|nil)
function M.prompt(opts, on_confirm)
	if config.is_modern() then
		M.input({ title = opts.title, default = opts.default, footer = opts.footer }, on_confirm)
	else
		vim.ui.input({ prompt = opts.prompt, default = opts.default }, on_confirm)
	end
end

--------------------------------------------------------------------------------
-- Shared rendering helpers
--------------------------------------------------------------------------------

---Builds a section heading line: title, rule, optional trailing count
---@return string text, table[] spans
local function section_line(title, count, width)
	local text = "  " .. title .. " "
	local spans = { { start_col = 2, end_col = 2 + #title, hl_group = "DooingSectionTitle" } }

	local suffix = count and tostring(count) or ""
	local rule_width = width - vim.fn.strdisplaywidth(text) - #suffix - (count and 3 or 2)
	if rule_width > 0 then
		local rule_start = #text
		text = text .. string.rep("─", rule_width)
		table.insert(spans, { start_col = rule_start, end_col = #text, hl_group = "DooingSectionRule" })
	end

	if count then
		text = text .. " "
		local count_start = #text
		text = text .. suffix
		table.insert(spans, { start_col = count_start, end_col = #text, hl_group = "DooingSectionCount" })
	end

	return text, spans
end

---Applies a list of { line, start_col, end_col, hl_group } spans to a buffer
local function apply_spans(buf, spans)
	for _, span in ipairs(spans) do
		vim.api.nvim_buf_add_highlight(buf, constants.ns_id, span.hl_group, span.line, span.start_col, span.end_col)
	end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

-- Grouped key listing, so the help window mirrors how the keys are actually used
local function help_sections()
	local keys = config.options.keymaps
	local cal = config.options.calendar.keymaps

	return {
		{
			title = "TODOS",
			items = {
				{ keys.new_todo, "Add new to-do" },
				{ keys.create_nested_task, "Add nested sub-task" },
				{ keys.toggle_todo, "Toggle to-do status" },
				{ keys.edit_todo, "Edit to-do item" },
				{ keys.delete_todo, "Delete current to-do" },
				{ keys.delete_completed, "Delete all completed" },
				{ keys.undo_delete, "Undo deletion" },
				{ keys.remove_duplicates, "Remove duplicates" },
			},
		},
		{
			title = "METADATA",
			items = {
				{ keys.add_due_date, "Add due date" },
				{ keys.remove_due_date, "Remove due date" },
				{ keys.add_time_estimation, "Add time estimation" },
				{ keys.remove_time_estimation, "Remove time estimation" },
				{ keys.edit_priorities, "Edit priorities" },
				{ keys.toggle_priority, "Toggle priority on add" },
				{ keys.open_todo_scratchpad, "Open todo scratchpad" },
			},
		},
		{
			title = "VIEW",
			items = {
				{ keys.toggle_tags, "Toggle tags window" },
				{ keys.clear_filter, "Clear active tag filter" },
				{ keys.search_todos, "Search todos" },
				{ keys.refresh_todos, "Refresh todo list" },
				{ keys.toggle_help, "Toggle this help window" },
				{ keys.close_window, "Close window" },
			},
		},
		{
			title = "IMPORT / EXPORT",
			items = {
				{ keys.import_todos, "Import todos" },
				{ keys.export_todos, "Export todos" },
				{ keys.share_todos, "Share todos (QR)" },
			},
		},
		{
			title = "TAGS WINDOW",
			items = {
				{ "<CR>", "Filter by tag" },
				{ keys.edit_tag, "Edit tag" },
				{ keys.delete_tag, "Delete tag" },
				{ keys.close_window, "Close window" },
			},
		},
		{
			title = "CALENDAR",
			items = {
				{ cal.previous_day, "Previous day" },
				{ cal.next_day, "Next day" },
				{ cal.previous_week, "Previous week" },
				{ cal.next_week, "Next week" },
				{ cal.previous_month, "Previous month" },
				{ cal.next_month, "Next month" },
				{ cal.select_day, "Select date" },
				{ cal.close_calendar, "Close calendar" },
			},
		},
	}
end

---Modern help window: grouped, aligned, sized from its content and centered.
function M.help()
	if constants.help_win_id and vim.api.nvim_win_is_valid(constants.help_win_id) then
		vim.api.nvim_win_close(constants.help_win_id, true)
		constants.help_win_id = nil
		constants.help_buf_id = nil
		return
	end

	local sections = help_sections()

	-- Widest key decides the column, so descriptions line up across all sections
	local key_width = 0
	for _, section in ipairs(sections) do
		for _, item in ipairs(section.items) do
			if item[1] then
				key_width = math.max(key_width, vim.fn.strdisplaywidth(tostring(item[1])))
			end
		end
	end

	local width = math.max(key_width + 34, 46)
	local lines, spans = {}, {}

	local function push(text, line_spans)
		table.insert(lines, text)
		for _, span in ipairs(line_spans or {}) do
			table.insert(spans, {
				line = #lines - 1,
				start_col = span.start_col,
				end_col = span.end_col,
				hl_group = span.hl_group,
			})
		end
	end

	for index, section in ipairs(sections) do
		if index > 1 then
			push("")
		end
		local text, header_spans = section_line(section.title, nil, width)
		push(text, header_spans)

		for _, item in ipairs(section.items) do
			local key, desc = item[1], item[2]
			-- Keys set to false are disabled, so they are not worth listing
			if key then
				key = tostring(key)
				local padded = key .. string.rep(" ", key_width - vim.fn.strdisplaywidth(key))
				local line = "   " .. padded .. "   " .. desc
				push(line, {
					{ start_col = 3, end_col = 3 + #key, hl_group = "DooingQuickKey" },
					{ start_col = 3 + #padded + 3, end_col = #line, hl_group = "DooingQuickDesc" },
				})
			end
		end
	end

	constants.help_buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(constants.help_buf_id, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(constants.help_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(constants.help_buf_id, "buftype", "nofile")

	constants.help_win_id = vim.api.nvim_open_win(
		constants.help_buf_id,
		true,
		M.centered(width, #lines, {
			title = " Keymaps ",
			footer = string.format(" %s or %s to close ", config.options.keymaps.toggle_help, config.options.keymaps.close_window),
		})
	)
	vim.api.nvim_win_set_option(constants.help_win_id, "cursorline", true)

	apply_spans(constants.help_buf_id, spans)

	local function close_help()
		if constants.help_win_id and vim.api.nvim_win_is_valid(constants.help_win_id) then
			vim.api.nvim_win_close(constants.help_win_id, true)
		end
		constants.help_win_id = nil
		constants.help_buf_id = nil
		focus_main()
	end

	local keyopts = { buffer = constants.help_buf_id, nowait = true }
	vim.keymap.set("n", config.options.keymaps.close_window, close_help, keyopts)
	vim.keymap.set("n", config.options.keymaps.toggle_help, close_help, keyopts)
	vim.keymap.set("n", "<Esc>", close_help, keyopts)
end

--------------------------------------------------------------------------------
-- Tags
--------------------------------------------------------------------------------

---Number of todos carrying a given tag
local function tag_count(tag)
	local count = 0
	for _, todo in ipairs(state.todos) do
		if utils.has_tag(todo.text, tag) then
			count = count + 1
		end
	end
	return count
end

---Modern tags window: each tag with a usage count, centered and content-sized.
function M.tags()
	if constants.tag_win_id and vim.api.nvim_win_is_valid(constants.tag_win_id) then
		vim.api.nvim_win_close(constants.tag_win_id, true)
		constants.tag_win_id = nil
		constants.tag_buf_id = nil
		return
	end

	-- Maps a buffer line to the tag it shows, so the display can carry counts
	-- without the tag name having to be parsed back out of the line.
	local line_to_tag = {}

	local function build()
		local tags = state.get_all_tags()
		local lines, spans = {}, {}
		line_to_tag = {}

		if #tags == 0 then
			return { "", "   No tags found", "" }, {
				{ line = 1, start_col = 3, end_col = -1, hl_group = "DooingMeta" },
			}, 34
		end

		local width = 34
		for _, tag in ipairs(tags) do
			width = math.max(width, #tag + 14)
		end

		table.insert(lines, "")
		for _, tag in ipairs(tags) do
			local label = "#" .. tag
			local count = tostring(tag_count(tag))
			local gap = width - 3 - vim.fn.strdisplaywidth(label) - #count
			local line = "  " .. label .. string.rep(" ", math.max(gap, 1)) .. count
			table.insert(lines, line)
			line_to_tag[#lines] = tag
			table.insert(spans, { line = #lines - 1, start_col = 2, end_col = 2 + #label, hl_group = "DooingTag" })
			table.insert(
				spans,
				{ line = #lines - 1, start_col = #line - #count, end_col = #line, hl_group = "DooingSectionCount" }
			)
		end
		table.insert(lines, "")

		return lines, spans, width
	end

	local lines, spans, width = build()

	constants.tag_buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(constants.tag_buf_id, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(constants.tag_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(constants.tag_buf_id, "buftype", "nofile")

	constants.tag_win_id = vim.api.nvim_open_win(
		constants.tag_buf_id,
		true,
		M.centered(width, #lines, {
			title = " Tags ",
			footer = string.format(
				" <CR> filter · %s edit · %s delete ",
				config.options.keymaps.edit_tag,
				config.options.keymaps.delete_tag
			),
		})
	)
	vim.api.nvim_win_set_option(constants.tag_win_id, "cursorline", true)
	apply_spans(constants.tag_buf_id, spans)

	-- Start on the first tag rather than the leading blank line
	if next(line_to_tag) then
		pcall(vim.api.nvim_win_set_cursor, constants.tag_win_id, { 2, 0 })
	end

	local function refresh()
		local new_lines, new_spans = build()
		vim.api.nvim_buf_set_option(constants.tag_buf_id, "modifiable", true)
		vim.api.nvim_buf_set_lines(constants.tag_buf_id, 0, -1, false, new_lines)
		vim.api.nvim_buf_set_option(constants.tag_buf_id, "modifiable", false)
		vim.api.nvim_buf_clear_namespace(constants.tag_buf_id, constants.ns_id, 0, -1)
		apply_spans(constants.tag_buf_id, new_spans)
	end

	local function close_tags()
		if constants.tag_win_id and vim.api.nvim_win_is_valid(constants.tag_win_id) then
			vim.api.nvim_win_close(constants.tag_win_id, true)
		end
		constants.tag_win_id = nil
		constants.tag_buf_id = nil
		focus_main()
	end

	local function tag_under_cursor()
		if not (constants.tag_win_id and vim.api.nvim_win_is_valid(constants.tag_win_id)) then
			return nil
		end
		return line_to_tag[vim.api.nvim_win_get_cursor(constants.tag_win_id)[1]]
	end

	local keyopts = { buffer = constants.tag_buf_id, nowait = true }

	vim.keymap.set("n", "<CR>", function()
		local tag = tag_under_cursor()
		if tag then
			state.set_filter(tag)
			close_tags()
			require("dooing.ui.rendering").render_todos()
		end
	end, keyopts)

	vim.keymap.set("n", config.options.keymaps.edit_tag, function()
		local tag = tag_under_cursor()
		if not tag then
			return
		end
		M.prompt({ title = " Edit tag ", prompt = "Edit tag: ", default = tag }, function(new_tag)
			if new_tag and new_tag ~= tag then
				state.rename_tag(tag, new_tag:gsub("^#", ""))
				refresh()
				require("dooing.ui.rendering").render_todos()
			end
			if constants.tag_win_id and vim.api.nvim_win_is_valid(constants.tag_win_id) then
				vim.api.nvim_set_current_win(constants.tag_win_id)
			end
		end)
	end, keyopts)

	vim.keymap.set("n", config.options.keymaps.delete_tag, function()
		local tag = tag_under_cursor()
		if not tag then
			return
		end
		state.delete_tag(tag)
		refresh()
		require("dooing.ui.rendering").render_todos()
	end, keyopts)

	vim.keymap.set("n", config.options.keymaps.close_window, close_tags, keyopts)
	vim.keymap.set("n", "<Esc>", close_tags, keyopts)
end

--------------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------------

---Finds the buffer line currently showing a given todo index
local function line_for_todo(todo_index)
	return (constants.primary_lines or {})[todo_index]
end

---Renders the results of a search into a centered window
local function show_results(query, results)
	local formatting = config.options.formatting
	local editor_width = select(1, editor_size())
	local width = math.max(math.min(64, editor_width - 8), 40)

	local lines, spans = {}, {}
	local line_to_result = {}

	table.insert(lines, "")
	for _, result in ipairs(results) do
		local todo = result.todo
		local icon
		if todo.done then
			icon = formatting.done.icon
		elseif todo.in_progress then
			icon = formatting.in_progress.icon
		else
			icon = formatting.pending.icon
		end

		local text = (todo.text:gsub("\n", " "))
		local line = "  " .. icon .. " " .. text
		table.insert(lines, line)
		line_to_result[#lines] = result

		local line_nr = #lines - 1
		local base_hl = todo.done and "DooingDone" or "DooingText"
		table.insert(spans, { line = line_nr, start_col = 2, end_col = 2 + #icon, hl_group = base_hl })

		-- Highlight the text, then overlay tags and the matched substring
		local text_start = 2 + #icon + 1
		table.insert(spans, { line = line_nr, start_col = text_start, end_col = #line, hl_group = base_hl })

		for tag_start, tag in text:gmatch("()(#[%w_%-/]+)") do
			local from = text_start + tag_start - 1
			table.insert(spans, { line = line_nr, start_col = from, end_col = from + #tag, hl_group = "DooingTag" })
		end

		local match_start = text:lower():find(query:lower(), 1, true)
		if match_start then
			local from = text_start + match_start - 1
			table.insert(spans, { line = line_nr, start_col = from, end_col = from + #query, hl_group = "Search" })
		end
	end
	table.insert(lines, "")

	constants.search_buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(constants.search_buf_id, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(constants.search_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(constants.search_buf_id, "buftype", "nofile")

	local count = #results
	constants.search_win_id = vim.api.nvim_open_win(
		constants.search_buf_id,
		true,
		M.centered(width, #lines, {
			title = string.format(" Search: %s ", query),
			footer = string.format(" %d %s · <CR> jump ", count, count == 1 and "result" or "results"),
		})
	)
	vim.api.nvim_win_set_option(constants.search_win_id, "cursorline", true)
	apply_spans(constants.search_buf_id, spans)

	if next(line_to_result) then
		pcall(vim.api.nvim_win_set_cursor, constants.search_win_id, { 2, 0 })
	end

	local function close_search()
		if constants.search_win_id and vim.api.nvim_win_is_valid(constants.search_win_id) then
			vim.api.nvim_win_close(constants.search_win_id, true)
		end
		constants.search_win_id = nil
		constants.search_buf_id = nil
		focus_main()
	end

	local keyopts = { buffer = constants.search_buf_id, nowait = true }

	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(constants.search_win_id)[1]
		local result = line_to_result[cursor]
		close_search()
		if not result then
			return
		end

		-- A filter can hide the match, so clear it before jumping
		if state.active_filter then
			state.set_filter(nil)
			require("dooing.ui.rendering").render_todos()
		end

		local target = line_for_todo(result.lnum)
		if target and constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
			pcall(vim.api.nvim_win_set_cursor, constants.win_id, { target, 0 })
		end
	end, keyopts)

	vim.keymap.set("n", config.options.keymaps.close_window, close_search, keyopts)
	vim.keymap.set("n", "<Esc>", close_search, keyopts)
end

---Modern search: a centered prompt, then a centered result list.
function M.search()
	if constants.search_win_id and vim.api.nvim_win_is_valid(constants.search_win_id) then
		vim.api.nvim_win_close(constants.search_win_id, true)
		constants.search_win_id = nil
		constants.search_buf_id = nil
	end

	M.input({ title = " Search to-dos ", footer = " <CR> search · <Esc> cancel " }, function(query)
		if not query then
			return
		end

		local results = state.search_todos(query)
		if #results == 0 then
			vim.notify(string.format("dooing: no todos match %q", query), vim.log.levels.INFO)
			return
		end

		show_results(query, results)
	end)
end

return M
