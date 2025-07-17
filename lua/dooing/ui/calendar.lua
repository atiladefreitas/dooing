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
end

function Cal.create(callback, opts)
	opts = opts or {}
	local calendar_opts = config.options.calendar
	local language = calendar_opts.language or "en"

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

	local width = 26
	local height = 9
	local parent_win = vim.api.nvim_get_current_win()
	local cursor_pos = vim.api.nvim_win_get_cursor(parent_win)

	cal.win_id = vim.api.nvim_open_win(cal.buf_id, true, {
		relative = "win",
		win = parent_win,
		row = cursor_pos[1],
		col = 3,
		width = width,
		height = height,
		style = "minimal",
		border = "single",
		title = string.format(" %s %d ", Cal.MONTH_NAMES[language][cal.month], cal.year),
		title_pos = "center",
	})

	--- Gets the cursor position for a given day
	local function get_cursor_position(day)
		if not day then
			return nil
		end

		local first_day = get_day_of_week(cal.year, cal.month, 1)
		local days_in_month = get_days_in_month(cal.month, cal.year)

		if day < 1 or day > days_in_month then
			return nil
		end

		local pos = first_day + day - 1
		local row = math.floor(pos / 7) + 3
		local col = (pos % 7) * 3 + 2

		return row, col
	end

	--- Gets the day from a given cursor position
	local function get_day_from_position(row, col)
		if row <= 2 then
			return nil
		end

		col = col - 2
		local col_index = math.floor(col / 3)
		local first_day = get_day_of_week(cal.year, cal.month, 1)
		local day = (row - 3) * 7 + col_index - first_day + 1

		if day < 1 or day > get_days_in_month(cal.month, cal.year) then
			return nil
		end

		return day
	end

	--- Renders the calendar
	local function render()
		local lines = {}

		table.insert(lines, "")
		table.insert(lines, "  Su Mo Tu We Th Fr Sa  ")

		local first_day = get_day_of_week(cal.year, cal.month, 1)
		local days_in_month = get_days_in_month(cal.month, cal.year)
		local day_count = 1

		while day_count <= days_in_month do
			local current_line = "  "
			for i = 0, 6 do
				if day_count == 1 and i < first_day then
					current_line = current_line .. "   "
				elseif day_count <= days_in_month then
					current_line = current_line .. string.format("%2d ", day_count)
					day_count = day_count + 1
				else
					current_line = current_line .. "   "
				end
			end
			current_line = current_line .. " "
			table.insert(lines, current_line)
		end

		while #lines < height do
			table.insert(lines, string.rep(" ", width))
		end

		vim.api.nvim_buf_set_lines(cal.buf_id, 0, -1, false, lines)
		vim.api.nvim_buf_clear_namespace(cal.buf_id, cal.ns_id, 0, -1)
		vim.api.nvim_buf_add_highlight(cal.buf_id, cal.ns_id, "CalendarHeader", 1, 0, -1)

		for row = 3, #lines do
			local line = lines[row]
			for col = 0, 6 do
				local start_col = col * 3 + 2
				local day_str = line:sub(start_col + 1, start_col + 2)
				local day_num = tonumber(day_str)

				if day_num then
					if col == 0 or col == 6 then
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
