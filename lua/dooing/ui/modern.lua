---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Modern rendering style for the todo list.
--
-- Enabled with `ui.style = "modern"`. Unlike the classic renderer, which writes
-- the lines first and then finds things again with patterns, this module builds
-- each line from typed segments and records exact byte ranges for every
-- highlight. That keeps the coloring precise (a tag is highlighted because it
-- is a tag, not because `#%w+` matched) and lets the layout contain lines that
-- are not todos at all.

local M = {}

local config = require("dooing.config")
local highlights = require("dooing.ui.highlights")
local utils = require("dooing.ui.utils")
local calendar = require("dooing.ui.calendar")

local DAY = 86400

--------------------------------------------------------------------------------
-- Line builder
--------------------------------------------------------------------------------

-- Accumulates text segments and their highlight ranges for a single line.
local Line = {}
Line.__index = Line

function Line.new()
	return setmetatable({ text = "", spans = {} }, Line)
end

---Appends `text`, optionally highlighted with `hl_group`
function Line:add(text, hl_group)
	if not text or text == "" then
		return
	end
	local start_col = #self.text
	self.text = self.text .. text
	if hl_group then
		table.insert(self.spans, { start_col = start_col, end_col = #self.text, hl_group = hl_group })
	end
end

---Current display width (not byte length) of the line
function Line:width()
	return vim.fn.strdisplaywidth(self.text)
end

--------------------------------------------------------------------------------
-- Metadata formatting
--------------------------------------------------------------------------------

-- Formats an estimated-completion time as a compact "≈2h" style string
local function format_estimate(hours)
	if hours >= 168 then
		return string.format("≈%gw", hours / 168)
	elseif hours >= 24 then
		return string.format("≈%gd", hours / 24)
	elseif hours >= 1 then
		return string.format("≈%gh", hours)
	end
	return string.format("≈%.0fm", hours * 60)
end

-- Absolute date, localized through the calendar month names
local function format_absolute_date(timestamp, lang)
	local date = os.date("*t", timestamp)
	local months = calendar.MONTH_NAMES[lang] or calendar.MONTH_NAMES.en
	local month = months[date.month]

	if lang == "jp" then
		return string.format("%d年%s%d日", date.year, month, date.day)
	elseif lang == "pt" or lang == "es" then
		return string.format("%d de %s", date.day, month)
	elseif lang == "fr" or lang == "de" or lang == "it" then
		return string.format("%d %s", date.day, month)
	end
	return string.format("%s %d", month, date.day)
end

-- Number of whole calendar days between two timestamps
local function day_delta(from, to)
	local a = os.date("*t", from)
	local b = os.date("*t", to)
	local a_midnight = os.time({ year = a.year, month = a.month, day = a.day, hour = 12 })
	local b_midnight = os.time({ year = b.year, month = b.month, day = b.day, hour = 12 })
	return math.floor((b_midnight - a_midnight) / DAY + 0.5)
end

---Renders a due date into text plus the highlight that conveys urgency.
---Overdue reads as "󰀦 overdue 3d" in red, today/tomorrow get their own accent,
---anything further out degrades to a plain dimmed date.
---@return string text, string hl_group
local function format_due(todo, lang, now)
	local days = day_delta(now, todo.due_at)
	local icon = config.options.calendar and config.options.calendar.icon or ""
	local prefix = (icon ~= "" and icon .. " ") or ""

	if todo.done then
		return prefix .. format_absolute_date(todo.due_at, lang), "DooingMeta"
	end

	if days < 0 then
		local overdue_icon = config.ui_icon("overdue")
		local amount = -days
		local text = amount == 1 and "overdue 1d" or string.format("overdue %dd", amount)
		return (overdue_icon ~= "" and overdue_icon .. " " or "") .. text, "DooingOverdue"
	elseif days == 0 then
		return prefix .. "due today", "DooingDueToday"
	elseif days == 1 then
		return prefix .. "due tomorrow", "DooingDueSoon"
	elseif days <= 7 then
		return prefix .. string.format("in %dd", days), "DooingDueSoon"
	end

	return prefix .. format_absolute_date(todo.due_at, lang), "DooingMeta"
end

-- Age of the todo, without the classic "@" prefix and "ago" suffix
local function format_age(timestamp)
	return (utils.format_relative_time(timestamp):gsub(" ago$", ""))
end

---Builds the ordered metadata chips shown on the right of a row
---@return table[] list of { text = string, hl_group = string }
local function build_metadata(todo, lang, now)
	local parts = {}

	if todo.estimated_hours then
		table.insert(parts, { text = format_estimate(todo.estimated_hours), hl_group = "DooingMeta" })
	end

	if todo.due_at then
		local text, hl_group = format_due(todo, lang, now)
		table.insert(parts, { text = text, hl_group = hl_group })
	end

	if todo.created_at and config.options.timestamp and config.options.timestamp.enabled then
		table.insert(parts, { text = format_age(todo.created_at), hl_group = "DooingMeta" })
	end

	return parts
end

--------------------------------------------------------------------------------
-- Tree structure
--------------------------------------------------------------------------------

---Determines, for each visible todo, whether it is the last entry at its depth
---within its subtree. Works purely off the depth sequence of the *visible*
---list, so it still behaves sensibly when a filter hides a parent.
---@param visible table[] list of { todo = ..., index = ... }
---@return boolean[]
local function compute_last_at_depth(visible)
	local is_last = {}
	for i, entry in ipairs(visible) do
		local depth = entry.todo.depth or 0
		is_last[i] = true
		for j = i + 1, #visible do
			local other_depth = visible[j].todo.depth or 0
			if other_depth <= depth then
				-- A sibling follows, so this is not the last one
				is_last[i] = other_depth < depth
				break
			end
		end
	end
	return is_last
end

---Whether each visible todo has at least one child shown beneath it
---@param visible table[]
---@return boolean[]
local function compute_has_children(visible)
	local has_children = {}
	for i, entry in ipairs(visible) do
		local next_entry = visible[i + 1]
		has_children[i] = next_entry ~= nil and (next_entry.todo.depth or 0) > (entry.todo.depth or 0)
	end
	return has_children
end

---Builds the tree guide prefix for a row.
---
---Top-level todos have no guide column of their own, so the vertical
---continuation columns belong to ancestors at depths 1..depth-1; the final
---column is this row's own connector.
---@param depth number
---@param is_last boolean
---@param ancestor_continues boolean[] whether the ancestor at each depth has more siblings
---@return string
local function build_tree_prefix(depth, is_last, ancestor_continues)
	if depth == 0 then
		return ""
	end

	-- The connector plus its trailing space occupies three columns, so the
	-- continuation columns must be three wide too or each level drifts left.
	local segments = {}
	for level = 1, depth - 1 do
		table.insert(segments, ancestor_continues[level] and "│  " or "   ")
	end
	table.insert(segments, is_last and "└─" or "├─")
	return table.concat(segments)
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------

local SECTION_ORDER = { "in_progress", "pending", "done" }

local function status_of(todo)
	if todo.done then
		return "done"
	elseif todo.in_progress then
		return "in_progress"
	end
	return "pending"
end

---Groups the visible list into status sections.
---
---Only top-level todos decide which section a subtree lands in; descendants
---always stay directly under their parent so nesting is never broken apart.
---@param visible table[]
---@return table[] groups, table<string, number> counts
local function group_into_sections(visible)
	local groups = {}
	local counts = { in_progress = 0, pending = 0, done = 0 }
	local current = nil

	for i, entry in ipairs(visible) do
		local depth = entry.todo.depth or 0
		if depth == 0 or current == nil then
			local section = status_of(entry.todo)
			current = { section = section, entries = {} }
			counts[section] = counts[section] + 1
			table.insert(groups, current)
		end
		table.insert(current.entries, { entry = entry, visible_index = i })
	end

	return groups, counts
end

--------------------------------------------------------------------------------
-- Row rendering
--------------------------------------------------------------------------------

---Splits a todo's text into plain and tag segments so tags can be highlighted
---by structure rather than by re-matching the finished line.
---@return table[] list of { text = string, is_tag = boolean }
local function split_tags(text)
	local segments = {}
	local cursor = 1

	while true do
		local tag_start, tag_end = text:find("#[%w_%-/]+", cursor)
		if not tag_start then
			break
		end
		if tag_start > cursor then
			table.insert(segments, { text = text:sub(cursor, tag_start - 1), is_tag = false })
		end
		table.insert(segments, { text = text:sub(tag_start, tag_end), is_tag = true })
		cursor = tag_end + 1
	end

	if cursor <= #text then
		table.insert(segments, { text = text:sub(cursor), is_tag = false })
	end

	return segments
end

---First non-blank line of a todo's notes, truncated to `available` columns
---@return string|nil
local function note_summary(todo, available)
	if not todo.notes or todo.notes == "" or available < 8 then
		return nil
	end

	local first
	for chunk in tostring(todo.notes):gmatch("[^\r\n]+") do
		local trimmed = chunk:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then
			first = trimmed
			break
		end
	end
	if not first then
		return nil
	end

	if vim.fn.strdisplaywidth(first) > available then
		-- strcharpart keeps multibyte characters intact
		first = vim.fn.strcharpart(first, 0, available - 1) .. "…"
	end
	return first
end

---Renders one todo into its row of lines.
---
---Metadata is right-aligned on the same line when it fits, and moves to its own
---dimmed continuation line when the text would otherwise be squeezed. When the
---todo carries notes, the first line of them follows underneath, dimmed and
---aligned with the todo text.
---@return Line[] lines the first of which is the todo's primary line
local function render_row(todo, opts)
	local line = Line.new()
	local formatting = config.options.formatting

	-- Priority marker: the only part that carries the priority color
	if opts.priority_bar then
		local bar = config.ui_icon("priority_bar")
		if todo.done or not todo.priorities or #todo.priorities == 0 then
			line:add(string.rep(" ", vim.fn.strdisplaywidth(bar)))
		else
			line:add(bar, highlights.get_priority_highlight(todo.priorities))
		end
		line:add(" ")
	else
		line:add("  ")
	end

	-- Tree guides
	if opts.tree_prefix ~= "" then
		line:add(opts.tree_prefix, "DooingTreeGuide")
		line:add(" ")
	end

	-- Status icon
	local icon
	if todo.done then
		icon = formatting.done.icon
	elseif todo.in_progress then
		icon = formatting.in_progress.icon
	else
		icon = formatting.pending.icon
	end
	local icon_hl = todo.done and "DooingDone" or highlights.get_priority_highlight(todo.priorities)
	line:add(icon, icon_hl)
	line:add(" ")

	-- Notes indicator
	if todo.notes and todo.notes ~= "" then
		line:add(config.options.notes.icon, "DooingMeta")
		line:add(" ")
	end

	-- Column the todo text starts at, so a note preview can line up under it
	local text_col = line:width()

	-- Text, with tags highlighted as their own segments
	local text_hl = todo.done and "DooingDone" or "DooingText"
	for _, segment in ipairs(split_tags((todo.text:gsub("\n", " ")))) do
		line:add(segment.text, segment.is_tag and "DooingTag" or text_hl)
	end

	-- Dimmed first line of the notes, indented to the todo text
	local note_line
	if opts.note_preview then
		local summary = note_summary(todo, opts.width - text_col - 2)
		if summary then
			note_line = Line.new()
			note_line:add(string.rep(" ", text_col))
			note_line:add(summary, "DooingMeta")
		end
	end

	local metadata = build_metadata(todo, opts.lang, opts.now)
	if #metadata == 0 then
		return note_line and { line, note_line } or { line }
	end

	-- Lay the metadata out on a throwaway line to measure it
	local meta = Line.new()
	for i, part in ipairs(metadata) do
		if i > 1 then
			meta:add("  ")
		end
		meta:add(part.text, part.hl_group)
	end

	local gap = opts.width - line:width() - meta:width() - 2
	if gap >= 2 then
		-- Fits alongside the text: right-align it
		line:add(string.rep(" ", gap))
		for _, span in ipairs(meta.spans) do
			table.insert(line.spans, {
				start_col = span.start_col + #line.text,
				end_col = span.end_col + #line.text,
				hl_group = span.hl_group,
			})
		end
		line.text = line.text .. meta.text
		return note_line and { line, note_line } or { line }
	end

	-- Does not fit: give the metadata its own right-aligned line
	local continuation = Line.new()
	local indent = math.max(opts.width - meta:width() - 2, 2)
	continuation:add(string.rep(" ", indent))
	for _, span in ipairs(meta.spans) do
		table.insert(continuation.spans, {
			start_col = span.start_col + #continuation.text,
			end_col = span.end_col + #continuation.text,
			hl_group = span.hl_group,
		})
	end
	continuation.text = continuation.text .. meta.text

	if note_line then
		return { line, continuation, note_line }
	end
	return { line, continuation }
end

---Builds a section heading: title, a rule filling the width, and a count
local function render_section_header(section, count, width)
	local line = Line.new()
	local titles = (config.options.ui or {}).section_titles or {}
	local title = titles[section] or section:upper()

	line:add("  ")
	line:add(title, "DooingSectionTitle")
	line:add(" ")

	local count_text = tostring(count)
	local rule_width = width - line:width() - #count_text - 3
	if rule_width > 0 then
		line:add(string.rep("─", rule_width), "DooingSectionRule")
	end
	line:add(" ")
	line:add(count_text, "DooingSectionCount")

	return line
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---Builds the full buffer contents for the modern style.
---@param todos table[] `state.todos`
---@param active_filter string|nil
---@return table result { lines = string[], spans = table[], line_to_todo = table }
function M.build(todos, active_filter)
	local width = config.get_window_dimensions().width
	local lang = calendar and calendar.get_language() or "en"
	local now = os.time()

	local opts_base = {
		width = width,
		lang = lang,
		now = now,
		priority_bar = config.modern_feature("priority_bar"),
		note_preview = config.modern_feature("note_preview"),
	}

	-- Collect the visible todos, keeping their real index in `state.todos`
	local visible = {}
	for index, todo in ipairs(todos) do
		if not active_filter or utils.has_tag(todo.text, active_filter) then
			table.insert(visible, { todo = todo, index = index })
		end
	end

	local is_last = compute_last_at_depth(visible)
	local has_children = compute_has_children(visible)
	local use_tree = config.modern_feature("tree_connectors")
	local use_sections = config.modern_feature("sections")
	local indent_size = (config.options.nested_tasks and config.options.nested_tasks.indent) or 2

	local lines = {}
	local spans = {}
	local line_to_todo = {}
	-- Todo index -> the first line of its row. `line_to_todo` maps every line a
	-- row occupies, so this is what identifies a todo's canonical position.
	local primary_lines = {}
	local fold_levels = {}
	local ancestor_continues = {}

	local function emit(line, todo_index, fold_level)
		table.insert(lines, line.text)
		local line_nr = #lines - 1
		for _, span in ipairs(line.spans) do
			table.insert(spans, {
				line = line_nr,
				start_col = span.start_col,
				end_col = span.end_col,
				hl_group = span.hl_group,
			})
		end
		if todo_index then
			line_to_todo[#lines] = todo_index
		end
		fold_levels[#lines] = fold_level or 0
		return #lines
	end

	local function emit_blank()
		table.insert(lines, "")
		fold_levels[#lines] = 0
	end

	if active_filter then
		local header = Line.new()
		header:add("  Filtered by ", "DooingMeta")
		header:add("#" .. active_filter, "DooingTag")
		emit(header)
		emit_blank()
	else
		emit_blank()
	end

	local function emit_entry(entry, visible_index)
		local todo = entry.todo
		local depth = todo.depth or 0
		local last = is_last[visible_index]

		local tree_prefix = ""
		if use_tree then
			tree_prefix = build_tree_prefix(depth, last, ancestor_continues)
			ancestor_continues[depth] = not last
		elseif depth > 0 then
			tree_prefix = string.rep(" ", depth * indent_size)
		end

		local opts = vim.tbl_extend("force", opts_base, { tree_prefix = tree_prefix })
		local row_lines = render_row(todo, opts)

		-- A todo with children opens a fold on its own line, so collapsing it
		-- keeps the parent visible and hides only its own subtree.
		local parent = has_children[visible_index]
		local level = parent and depth + 1 or depth

		for i, row_line in ipairs(row_lines) do
			-- Every line a row occupies resolves to that todo, so acting from a
			-- metadata or note line does the expected thing instead of nothing.
			-- They share the row's fold level so they collapse with it.
			local fold_level = (parent and i == 1) and (">" .. level) or level
			local line_nr = emit(row_line, entry.index, fold_level)
			if i == 1 then
				primary_lines[entry.index] = line_nr
			end
		end
	end

	if use_sections then
		local groups, counts = group_into_sections(visible)

		for _, section in ipairs(SECTION_ORDER) do
			local section_groups = {}
			for _, group in ipairs(groups) do
				if group.section == section then
					table.insert(section_groups, group)
				end
			end

			if #section_groups > 0 then
				emit(render_section_header(section, counts[section], width))
				for _, group in ipairs(section_groups) do
					for _, item in ipairs(group.entries) do
						emit_entry(item.entry, item.visible_index)
					end
				end
				emit_blank()
			end
		end
	else
		for visible_index, entry in ipairs(visible) do
			emit_entry(entry, visible_index)
		end
		emit_blank()
	end

	return {
		lines = lines,
		spans = spans,
		line_to_todo = line_to_todo,
		primary_lines = primary_lines,
		fold_levels = fold_levels,
	}
end

---'foldexpr' for the modern style.
---
---Every row sits at the same character indent, so `foldmethod = "indent"` cannot
---see the nesting. Folding by the todo's real depth instead also makes it
---independent of the user's 'shiftwidth'.
---@param lnum number|nil defaults to the line being evaluated
---@return number
function M.foldexpr(lnum)
	local constants = require("dooing.ui.constants")
	return (constants.fold_levels or {})[lnum or vim.v.lnum] or 0
end

---Completion statistics for the progress indicators
---@return table { done = number, total = number, overdue = number }
function M.stats(todos, active_filter)
	local done, total, overdue = 0, 0, 0
	local now = os.time()

	for _, todo in ipairs(todos) do
		if not active_filter or utils.has_tag(todo.text, active_filter) then
			total = total + 1
			if todo.done then
				done = done + 1
			else
				if todo.due_at and todo.due_at < now then
					overdue = overdue + 1
				end
			end
		end
	end

	return { done = done, total = total, overdue = overdue }
end

---Renders a small progress bar, as `[text, hl_group]` chunks suitable for a
---floating window title
---@param stats table result of `M.stats`
---@param bar_width number
---@return table[]
function M.progress_chunks(stats, bar_width)
	local on_icon = config.ui_icon("progress_on")
	local off_icon = config.ui_icon("progress_off")
	local filled = 0
	if stats.total > 0 then
		filled = math.floor((stats.done / stats.total) * bar_width + 0.5)
	end

	local chunks = {}
	table.insert(chunks, { string.format(" %d/%d ", stats.done, stats.total), "DooingSectionCount" })
	if filled > 0 then
		table.insert(chunks, { string.rep(on_icon, filled), "DooingProgressOn" })
	end
	if bar_width - filled > 0 then
		table.insert(chunks, { string.rep(off_icon, bar_width - filled), "DooingProgressOff" })
	end
	table.insert(chunks, { " ", "DooingSectionCount" })

	return chunks
end

return M
