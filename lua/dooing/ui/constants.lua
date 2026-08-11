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

-- Window to restore focus to when closing dooing
M.previous_win = nil

-- Maps a 1-based buffer line in the main window to an index into `state.todos`.
-- Rebuilt on every render; consumers should go through
-- `ui/utils.todo_index_at_line()` rather than reading this directly.
M.line_to_todo = {}

-- Maps a 1-based buffer line to its fold level, used by the modern style's
-- 'foldexpr'. Rebuilt on every render.
M.fold_levels = {}

-- Maps a todo index to the first buffer line of its row. A row can span several
-- lines (metadata overflow, note preview), all of which appear in
-- `line_to_todo`, so this is what identifies a todo's canonical position.
M.primary_lines = {}

return M 
