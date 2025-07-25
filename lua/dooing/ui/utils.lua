---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Utility functions for UI module

local M = {}
local calendar = require("dooing.ui.calendar")
local config = require("dooing.config")

-- Helper function to format relative time
function M.format_relative_time(timestamp)
	local now = os.time()
	local diff = now - timestamp

	-- Less than a minute
	if diff < 60 then
		return "just now"
	end
	-- Less than an hour
	if diff < 3600 then
		local mins = math.floor(diff / 60)
		return mins .. "m ago"
	end
	-- Less than a day
	if diff < 86400 then
		local hours = math.floor(diff / 3600)
		return hours .. "h ago"
	end
	-- Less than a week
	if diff < 604800 then
		local days = math.floor(diff / 86400)
		return days .. "d ago"
	end
	-- More than a week
	local weeks = math.floor(diff / 604800)
	return weeks .. "w ago"
end

-- Parse time estimation string (e.g., "2h", "1d", "0.5w")
function M.parse_time_estimation(time_str)
	local number, unit = time_str:match("^(%d+%.?%d*)([mhdw])$")

	if not (number and unit) then
		return nil,
			"Invalid format. Use number followed by m (minutes), h (hours), d (days), or w (weeks). E.g., 30m, 2h, 1d, 0.5w"
	end

	local hours = tonumber(number)
	if not hours then
		return nil, "Invalid number format"
	end

	-- Convert to hours
	if unit == "m" then
		hours = hours / 60
	elseif unit == "d" then
		hours = hours * 24
	elseif unit == "w" then
		hours = hours * 24 * 7
	end

	return hours
end

-- Helper function to clean up priority selection resources
function M.cleanup_priority_selection(select_buf, select_win, keymaps)
	-- Remove all keymaps
	for _, keymap in ipairs(keymaps) do
		pcall(vim.keymap.del, "n", keymap, { buffer = select_buf })
	end

	-- Close window if it's still valid
	if select_win and vim.api.nvim_win_is_valid(select_win) then
		vim.api.nvim_win_close(select_win, true)
	end

	-- Delete buffer if it still exists
	if select_buf and vim.api.nvim_buf_is_valid(select_buf) then
		vim.api.nvim_buf_delete(select_buf, { force = true })
	end
end

-- Helper function for formatting based on format config
function M.render_todo(todo, formatting, lang, notes_icon, window_width)
	if not formatting or not formatting.pending or not formatting.done then
		error("Invalid 'formatting' configuration in config.lua")
	end

	local components = {}
	local timestamp = ""

	-- Get config formatting
	local format = todo.done and formatting.done.format or formatting.pending.format
	if not format then
		format = { "notes_icon", "icon", "text", "ect", "relative_time" }
	end

	-- Breakdown config format and get dynamic text based on other configs
	for _, part in ipairs(format) do
		if part == "icon" then
			local icon
			if todo.done then
				icon = formatting.done.icon
			elseif todo.in_progress then
				icon = formatting.in_progress.icon
			else
				icon = formatting.pending.icon
			end
			table.insert(components, icon)
		elseif part == "text" then
			table.insert(components, (todo.text:gsub("\n", " ")))
		elseif part == "notes_icon" then
			table.insert(components, notes_icon)
		elseif part == "relative_time" then
			if todo.created_at and config.options.timestamp and config.options.timestamp.enabled then
				timestamp = "@" .. M.format_relative_time(todo.created_at)
			end
		elseif part == "due_date" then
			-- Format due date if exists
			if todo.due_at then
				local date = os.date("*t", todo.due_at)
				local month = calendar.MONTH_NAMES[lang][date.month]
				local formatted_date
				if lang == "pt" or lang == "es" then
					formatted_date = string.format("%d de %s de %d", date.day, month, date.year)
				elseif lang == "fr" then
					formatted_date = string.format("%d %s %d", date.day, month, date.year)
				elseif lang == "de" or lang == "it" then
					formatted_date = string.format("%d %s %d", date.day, month, date.year)
				elseif lang == "jp" then
					formatted_date = string.format("%d年%s%d日", date.year, month, date.day)
				else
					formatted_date = string.format("%s %d, %d", month, date.day, date.year)
				end
				local due_date_str
				if config.options.calendar.icon ~= "" then
					due_date_str = "[" .. config.options.calendar.icon .. " " .. formatted_date .. "]"
				else
					due_date_str = "[" .. formatted_date .. "]"
				end
				local current_time = os.time()
				if not todo.done and todo.due_at < current_time then
					due_date_str = due_date_str .. " [OVERDUE]"
				end
				table.insert(components, due_date_str)
			end
		elseif part == "priority" then
			local state = require("dooing.state")
			local score = state.get_priority_score(todo)
			table.insert(components, string.format("Priority: %d", score))
		elseif part == "ect" then
			if todo.estimated_hours then
				local time_str
				if todo.estimated_hours >= 168 then -- more than a week
					local weeks = todo.estimated_hours / 168
					time_str = string.format("[≈ %gw]", weeks)
				elseif todo.estimated_hours >= 24 then -- more than a day
					local days = todo.estimated_hours / 24
					time_str = string.format("[≈ %gd]", days)
				elseif todo.estimated_hours >= 1 then -- more than an hour
					time_str = string.format("[≈ %gh]", todo.estimated_hours)
				else -- less than an hour
					time_str = string.format("[≈ %gm]", todo.estimated_hours * 60)
				end
				table.insert(components, time_str)
			end
		end
	end

	-- Join the main components (without timestamp)
	local main_content = table.concat(components, " ")
	
	-- If we have a timestamp and window width, position it at the right
	if timestamp ~= "" and window_width then
		local main_length = vim.fn.strdisplaywidth(main_content)
		local timestamp_length = vim.fn.strdisplaywidth(timestamp)
		local available_space = window_width - main_length - timestamp_length - 4 -- Account for padding and borders
		
		if available_space > 1 then
			-- Add spaces to push timestamp to the right
			main_content = main_content .. string.rep(" ", available_space) .. timestamp
		else
			-- If not enough space, just append normally
			main_content = main_content .. " " .. timestamp
		end
	elseif timestamp ~= "" then
		-- Fallback if no window width provided
		main_content = main_content .. " " .. timestamp
	end

	return main_content
end

return M 