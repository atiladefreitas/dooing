local Cal = {}

local config = require("dooing.config")

-- Month names in different languages
Cal.MONTH_NAMES = {
	en = {
		"January",
		"February",
		"March",
		"April",
		"May",
		"June",
		"July",
		"August",
		"September",
		"October",
		"November",
		"December",
	},
	pt = {
		"Janeiro",
		"Fevereiro",
		"Março",
		"Abril",
		"Maio",
		"Junho",
		"Julho",
		"Agosto",
		"Setembro",
		"Outubro",
		"Novembro",
		"Dezembro",
	},
	es = {
		"Enero",
		"Febrero",
		"Marzo",
		"Abril",
		"Mayo",
		"Junio",
		"Julio",
		"Agosto",
		"Septiembre",
		"Octubre",
		"Noviembre",
		"Diciembre",
	},
	fr = {
		"Janvier",
		"Février",
		"Mars",
		"Avril",
		"Mai",
		"Juin",
		"Juillet",
		"Août",
		"Septembre",
		"Octobre",
		"Novembre",
		"Décembre",
	},
	de = {
		"Januar",
		"Februar",
		"März",
		"April",
		"Mai",
		"Juni",
		"Juli",
		"August",
		"September",
		"Oktober",
		"November",
		"Dezember",
	},
	it = {
		"Gennaio",
		"Febbraio",
		"Marzo",
		"Aprile",
		"Maggio",
		"Giugno",
		"Luglio",
		"Agosto",
		"Settembre",
		"Ottobre",
		"Novembre",
		"Dicembre",
	},
	jp = {
		"一月",
		"二月",
		"三月",
		"四月",
		"ご月",
		"六月",
		"七月",
		"八月",
		"九月",
		"十月",
		"十一月",
		"十二月",
	},
}

-- Weekday abbreviations for each language
Cal.WEEKDAY_NAMES = {
	en = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" },
	pt = { "Do", "Se", "Te", "Qa", "Qi", "Se", "Sa" },
	es = { "Do", "Lu", "Ma", "Mi", "Ju", "Vi", "Sa" },
	fr = { "Di", "Lu", "Ma", "Me", "Je", "Ve", "Sa" },
	de = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" },
	it = { "Do", "Lu", "Ma", "Me", "Gi", "Ve", "Sa" },
	jp = { "日", "月", "火", "水", "木", "金", "土" },
}

-- Helper function get calendar language to use on ui
function Cal.get_language()
	local calendar_opts = config.options.calendar or {}
	return calendar_opts.language or "en"
end

---Calculates the number of days in a given month and year
local function get_days_in_month(month, year)
	local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	if month == 2 then
		if (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0 then
			return 29
		end
	end
	return days_in_month[month]
end

---Calculates the day of week for a given date
local function get_day_of_week(year, month, day)
	local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
	if month < 3 then
		year = year - 1
	end
	return (year + math.floor(year / 4) - math.floor(year / 100) + math.floor(year / 400) + t[month] + day) % 7
end

---Sets up the calendar highlight groups
local function setup_highlights()
	vim.api.nvim_set_hl(0, "CalendarHeader", { link = "Title" })
	vim.api.nvim_set_hl(0, "CalendarWeekday", { link = "Normal" })
	vim.api.nvim_set_hl(0, "CalendarWeekend", { link = "Special" })
	vim.api.nvim_set_hl(0, "CalendarCurrentDay", { link = "Visual" })
	vim.api.nvim_set_hl(0, "CalendarSelectedDay", { link = "Search" })
	vim.api.nvim_set_hl(0, "CalendarToday", { link = "Directory" })

	-- The modern style dims out-of-focus parts so the grid reads more clearly
	vim.api.nvim_set_hl(0, "CalendarWeekdayHeader", { link = "DooingSectionCount", default = true })
end

local function shift_first_day(first_day, start_day)
	if start_day == "monday" then
		return (first_day - 1) % 7
	end
	return first_day
end

local function validate_start_day(start_day)
	start_day = (start_day or "sunday"):lower()
	if start_day ~= "sunday" and start_day ~= "monday" then
		return "sunday"
	end
	return start_day
end

function Cal.create(callback, opts)
	opts = opts or {}
	local calendar_opts = config.options.calendar
	local language = calendar_opts.language or "en"
	local start_day = validate_start_day(calendar_opts.start_day)

	local cal = {
		year = os.date("*t").year,
		month = os.date("*t").month,
		day = os.date("*t").day,
		today = {
			year = os.date("*t").year,
			month = os.date("*t").month,
			day = os.date("*t").day,
		},
		win_id = nil,
		buf_id = nil,
		ns_id = vim.api.nvim_create_namespace("calendar_highlights"),
	}

	setup_highlights()

	cal.buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(cal.buf_id, "bufhidden", "wipe")

	-- Grid geometry. The rendering, the cursor placement and the reverse
	-- position -> day lookup all derive from these, so the layout can change
	-- without the three drifting apart.
	--   pad         columns of padding before the first cell
	--   cell        width of one day cell
	--   num_off     offset of the two-digit number inside a cell
	--   header_rows lines above the first row of days
	local layout = config.is_modern()
			-- Roomier cells, and a blank line between the weekday names and the grid
			-- height fits the worst case: 3 header rows + 6 week rows + 1 trailing blank
		and { pad = 3, cell = 4, num_off = 1, header_rows = 3, width = 32, height = 10 }
		or { pad = 2, cell = 3, num_off = 0, header_rows = 2, width = 26, height = 9 }

	local width = layout.width
	local height = layout.height
	local title = string.format(" %s %d ", Cal.MONTH_NAMES[language][cal.month], cal.year)

	local win_opts
	if config.is_modern() then
		-- Centered on the editor, with the navigation keys spelled out, instead
		-- of being anchored to wherever the cursor happened to be
		local keys = calendar_opts.keymaps
		win_opts = require("dooing.ui.panels").centered(width, height, {
			zindex_offset = 4,
			title = title,
			footer = string.format(
				" %s%s%s%s move · %s select ",
				keys.previous_day or "",
				keys.next_week or "",
				keys.previous_week or "",
				keys.next_day or "",
				keys.select_day or ""
			),
		})
	else
		local parent_win = vim.api.nvim_get_current_win()
		local cursor_pos = vim.api.nvim_win_get_cursor(parent_win)
		win_opts = {
			relative = "win",
			win = parent_win,
			row = cursor_pos[1],
			col = 3,
			width = width,
			height = height,
			style = "minimal",
			border = "single",
			title = title,
			title_pos = "center",
			zindex = config.options.window.zindex + 4,
		}
	end

	cal.win_id = vim.api.nvim_open_win(cal.buf_id, true, win_opts)

	--- Gets the cursor position for a given day
	local function get_cursor_position(day)
		if not day then
			return nil
		end

		local first_day = shift_first_day(get_day_of_week(cal.year, cal.month, 1), start_day)
		local days_in_month = get_days_in_month(cal.month, cal.year)

		if day < 1 or day > days_in_month then
			return nil
		end

		local pos = first_day + day - 1
		local row = math.floor(pos / 7) + layout.header_rows + 1
		local col = (pos % 7) * layout.cell + layout.pad + layout.num_off

		return row, col
	end

	--- Gets the day from a given cursor position
	local function get_day_from_position(row, col)
		if row <= layout.header_rows then
			return nil
		end

		col = col - layout.pad
		if col < 0 then
			return nil
		end
		local col_index = math.floor(col / layout.cell)
		local first_day = shift_first_day(get_day_of_week(cal.year, cal.month, 1), start_day)
		local day = (row - layout.header_rows - 1) * 7 + col_index - first_day + 1

		if day < 1 or day > get_days_in_month(cal.month, cal.year) then
			return nil
		end

		return day
	end

	--- Renders the calendar
	local function render()
		local lines = {}

		table.insert(lines, "")
		local weekday_names = Cal.WEEKDAY_NAMES[language] or Cal.WEEKDAY_NAMES["en"]
		-- Shift weekday names based on start_day
		local shift = 0
		if start_day == "monday" then
			shift = 1
		end
		local shifted_weekdays = {}
		for i = 1, 7 do
			shifted_weekdays[i] = weekday_names[((i - 1 + shift) % 7) + 1]
		end

		-- Each weekday name sits at the same offset within its cell as the day
		-- numbers below it, so the columns line up whatever the cell width is
		local header = string.rep(" ", layout.pad)
		for _, name in ipairs(shifted_weekdays) do
			local trailing = layout.cell - layout.num_off - vim.fn.strdisplaywidth(name)
			header = header .. string.rep(" ", layout.num_off) .. name .. string.rep(" ", math.max(trailing, 0))
		end
		table.insert(lines, header)

		-- Blank line between the weekday names and the grid, when the layout asks for one
		for _ = 3, layout.header_rows do
			table.insert(lines, "")
		end

		local first_day = shift_first_day(get_day_of_week(cal.year, cal.month, 1), start_day)
		local days_in_month = get_days_in_month(cal.month, cal.year)
		local day_count = 1
		local empty_cell = string.rep(" ", layout.cell)

		while day_count <= days_in_month do
			local current_line = string.rep(" ", layout.pad)
			for i = 0, 6 do
				if day_count == 1 and i < first_day then
					current_line = current_line .. empty_cell
				elseif day_count <= days_in_month then
					current_line = current_line
						.. string.rep(" ", layout.num_off)
						.. string.format("%2d", day_count)
						.. string.rep(" ", layout.cell - layout.num_off - 2)
					day_count = day_count + 1
				else
					current_line = current_line .. empty_cell
				end
			end
			table.insert(lines, current_line)
		end

		while #lines < height do
			table.insert(lines, "")
		end

		vim.api.nvim_buf_set_lines(cal.buf_id, 0, -1, false, lines)
		vim.api.nvim_buf_clear_namespace(cal.buf_id, cal.ns_id, 0, -1)
		vim.api.nvim_buf_add_highlight(
			cal.buf_id,
			cal.ns_id,
			config.is_modern() and "CalendarWeekdayHeader" or "CalendarHeader",
			1,
			0,
			-1
		)

		for row = layout.header_rows + 1, #lines do
			local line = lines[row]
			for col = 0, 6 do
				local start_col = col * layout.cell + layout.pad + layout.num_off
				local day_str = line:sub(start_col + 1, start_col + 2)
				local day_num = tonumber(day_str)

				if day_num then
					-- Weekend columns: Sunday=0,6; Monday=5,6
					local is_weekend = false
					if start_day == "monday" then
						is_weekend = (col == 5 or col == 6)
					else
						is_weekend = (col == 0 or col == 6)
					end
					if is_weekend then
						vim.api.nvim_buf_add_highlight(
							cal.buf_id,
							cal.ns_id,
							"CalendarWeekend",
							row - 1,
							start_col,
							start_col + 2
						)
					else
						vim.api.nvim_buf_add_highlight(
							cal.buf_id,
							cal.ns_id,
							"CalendarWeekday",
							row - 1,
							start_col,
							start_col + 2
						)
					end

					if day_num == cal.day then
						vim.api.nvim_buf_add_highlight(
							cal.buf_id,
							cal.ns_id,
							"CalendarCurrentDay",
							row - 1,
							start_col,
							start_col + 2
						)
					end

					if cal.year == cal.today.year and cal.month == cal.today.month and day_num == cal.today.day then
						vim.api.nvim_buf_add_highlight(
							cal.buf_id,
							cal.ns_id,
							"CalendarToday",
							row - 1,
							start_col,
							start_col + 2
						)
					end
				end
			end
		end

		vim.api.nvim_win_set_config(cal.win_id, {
			title = string.format(" %s %d ", Cal.MONTH_NAMES[language][cal.month], cal.year),
			title_pos = "center",
		})

		local row, col = get_cursor_position(cal.day)
		if row and col then
			vim.api.nvim_win_set_cursor(cal.win_id, { row, col })
		end
	end

	-- Navigates to a different day
	local function navigate_day(direction)
		local current_pos = vim.api.nvim_win_get_cursor(cal.win_id)
		local current_day = get_day_from_position(current_pos[1], current_pos[2])

		if not current_day then
			cal.day = 1
		else
			cal.day = current_day

			if direction == "left" then
				cal.day = cal.day - 1
			elseif direction == "right" then
				cal.day = cal.day + 1
			elseif direction == "up" then
				cal.day = cal.day - 7
			elseif direction == "down" then
				cal.day = cal.day + 7
			end
		end

		local days_in_month = get_days_in_month(cal.month, cal.year)
		if cal.day < 1 then
			cal.month = cal.month - 1
			if cal.month < 1 then
				cal.month = 12
				cal.year = cal.year - 1
			end
			cal.day = get_days_in_month(cal.month, cal.year)
			render()
		elseif cal.day > days_in_month then
			cal.month = cal.month + 1
			if cal.month > 12 then
				cal.month = 1
				cal.year = cal.year + 1
			end
			cal.day = 1
			render()
		else
			local row, col = get_cursor_position(cal.day)
			if row and col then
				vim.api.nvim_win_set_cursor(cal.win_id, { row, col })
			end
			render()
		end
	end

	-- Set up keymaps
	local keymaps = calendar_opts.keymaps
	local keyopts = { buffer = cal.buf_id, nowait = true }

	if keymaps.previous_day then
		vim.keymap.set("n", keymaps.previous_day, function()
			navigate_day("left")
		end, keyopts)
	end
	if keymaps.next_day then
		vim.keymap.set("n", keymaps.next_day, function()
			navigate_day("right")
		end, keyopts)
	end
	if keymaps.previous_week then
		vim.keymap.set("n", keymaps.previous_week, function()
			navigate_day("up")
		end, keyopts)
	end
	if keymaps.next_week then
		vim.keymap.set("n", keymaps.next_week, function()
			navigate_day("down")
		end, keyopts)
	end

	if keymaps.previous_month then
		vim.keymap.set("n", keymaps.previous_month, function()
			cal.month = cal.month - 1
			if cal.month < 1 then
				cal.month = 12
				cal.year = cal.year - 1
			end
			render()
		end, keyopts)
	end

	if keymaps.next_month then
		vim.keymap.set("n", keymaps.next_month, function()
			cal.month = cal.month + 1
			if cal.month > 12 then
				cal.month = 1
				cal.year = cal.year + 1
			end
			render()
		end, keyopts)
	end

	if keymaps.select_day then
		vim.keymap.set("n", keymaps.select_day, function()
			local cursor = vim.api.nvim_win_get_cursor(cal.win_id)
			local day = get_day_from_position(cursor[1], cursor[2])

			if day then
				local date_str = string.format("%02d/%02d/%04d", cal.month, day, cal.year)
				vim.api.nvim_win_close(cal.win_id, true)
				callback(date_str)
			end
		end, keyopts)
	end

	if keymaps.close_calendar then
		vim.keymap.set("n", keymaps.close_calendar, function()
			vim.api.nvim_win_close(cal.win_id, true)
		end, keyopts)
	end

	render()

	return cal
end

return Cal
