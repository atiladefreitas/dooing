---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- Constants and shared state for UI module

local M = {}

-- Namespace for highlighting
M.ns_id = vim.api.nvim_create_namespace("dooing")

-- Cache for highlight groups
M.highlight_cache = {}

-- Window and buffer IDs
M.win_id = nil
M.buf_id = nil
M.help_win_id = nil
M.help_buf_id = nil
M.tag_win_id = nil
M.tag_buf_id = nil
M.search_win_id = nil
M.search_buf_id = nil

return M 