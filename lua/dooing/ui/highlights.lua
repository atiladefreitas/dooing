---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Highlights management for UI module

local M = {}
local constants = require("dooing.ui.constants")
local config = require("dooing.config")

-- Set up highlights
function M.setup_highlights()
	-- Clear highlight cache
	constants.highlight_cache = {}

	-- Set up base highlights
	vim.api.nvim_set_hl(0, "DooingPending", { link = "Question", default = true })
	vim.api.nvim_set_hl(0, "DooingDone", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "DooingHelpText", { link = "Directory", default = true })
	vim.api.nvim_set_hl(0, "DooingTimestamp", { link = "Comment", default = true })

	-- Cache the base highlight groups
	constants.highlight_cache.pending = "DooingPending"
	constants.highlight_cache.done = "DooingDone"
	constants.highlight_cache.help = "DooingHelpText"
end

-- Get highlight group for a set of priorities
function M.get_priority_highlight(priorities)
	if not priorities or #priorities == 0 then
		return constants.highlight_cache.pending
	end

	-- Sort priority groups by number of members (descending)
	local sorted_groups = {}
	for name, group in pairs(config.options.priority_groups) do
		table.insert(sorted_groups, { name = name, group = group })
	end
	table.sort(sorted_groups, function(a, b)
		return #a.group.members > #b.group.members
	end)

	-- Check priority groups from largest to smallest
	for _, group_data in ipairs(sorted_groups) do
		local group = group_data.group
		-- Check if all group members are present in the priorities
		local all_members_match = true
		for _, member in ipairs(group.members) do
			local found = false
			for _, priority in ipairs(priorities) do
				if priority == member then
					found = true
					break
				end
			end
			if not found then
				all_members_match = false
				break
			end
		end

		if all_members_match then
			-- Create cache key from group definition
			local cache_key = table.concat(group.members, "_")
			if constants.highlight_cache[cache_key] then
				return constants.highlight_cache[cache_key]
			end

			local hl_group = constants.highlight_cache.pending
			if group.color and type(group.color) == "string" and group.color:match("^#%x%x%x%x%x%x$") then
				local hl_name = "Dooing" .. group.color:gsub("#", "")
				vim.api.nvim_set_hl(0, hl_name, { fg = group.color })
				hl_group = hl_name
			elseif group.hl_group then
				hl_group = group.hl_group
			end

			constants.highlight_cache[cache_key] = hl_group
			return hl_group
		end
	end

	return constants.highlight_cache.pending
end

return M 