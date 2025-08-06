---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- UI Components (help, tags, search windows, etc.)

local M = {}
local constants = require("dooing.ui.constants")
local state = require("dooing.state")
local config = require("dooing.config")
local calendar = require("dooing.ui.calendar")

-- Creates and manages the help window
function M.create_help_window()
  if constants.help_win_id and vim.api.nvim_win_is_valid(constants.help_win_id) then
    vim.api.nvim_win_close(constants.help_win_id, true)
    constants.help_win_id = nil
    constants.help_buf_id = nil
    return
  end

  constants.help_buf_id = vim.api.nvim_create_buf(false, true)

  local width = 50
  local height = 45
  local ui = vim.api.nvim_list_uis()[1]
  local col = math.floor((ui.width - width) / 2) + width + 2
  local row = math.floor((ui.height - height) / 2)

  constants.help_win_id = vim.api.nvim_open_win(constants.help_buf_id, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " help ",
    title_pos = "center",
    zindex = 100,
  })

  local keys = config.options.keymaps
  local help_content = {
    " Main window:",
    string.format(" %-12s - Add new to-do", keys.new_todo),
    string.format(" %-12s - Add nested sub-task", keys.create_nested_task),
    string.format(" %-12s - Toggle to-do status", keys.toggle_todo),
    string.format(" %-12s - Delete current to-do", keys.delete_todo),
    string.format(" %-12s - Delete all completed todos", keys.delete_completed),
    string.format(" %-12s - Close window", keys.close_window),
    string.format(" %-12s - Add due date to to-do", keys.add_due_date),
    string.format(" %-12s - Remove to-do due date", keys.remove_due_date),
    string.format(" %-12s - Add time estimation", keys.add_time_estimation),
    string.format(" %-12s - Remove time estimation", keys.remove_time_estimation),
    string.format(" %-12s - Toggle this help window", keys.toggle_help),
    string.format(" %-12s - Toggle tags window", keys.toggle_tags),
    string.format(" %-12s - Clear active tag filter", keys.clear_filter),
    string.format(" %-12s - Edit to-do item", keys.edit_todo),
    string.format(" %-12s - Edit to-do priorities", keys.edit_priorities),
    string.format(" %-12s - Undo deletion", keys.undo_delete),
    string.format(" %-12s - Search todos", keys.search_todos),
    string.format(" %-12s - Import todos", keys.import_todos),
    string.format(" %-12s - Export todos", keys.export_todos),
    string.format(" %-12s - Remove duplicates", keys.remove_duplicates),
    string.format(" %-12s - Open todo scratchpad", keys.open_todo_scratchpad),
    string.format(" %-12s - Toggle priority on add todo", keys.toggle_priority),
    string.format(" %-12s - Refresh todo list", keys.refresh_todos),
    string.format(" %-12s - Share todos (experimental - app functionality)", keys.share_todos),
    "",
    " Tags window:",
    string.format(" %-12s - Edit tag", keys.edit_tag),
    string.format(" %-12s - Delete tag", keys.delete_tag),
    string.format(" %-12s - Filter by tag", " <CR>"),
    string.format(" %-12s - Close window", keys.close_window),
    "",
    " Calendar window:",
    string.format(" %-12s - Previous day", config.options.calendar.keymaps.previous_day),
    string.format(" %-12s - Next day", config.options.calendar.keymaps.next_day),
    string.format(" %-12s - Previous week", config.options.calendar.keymaps.previous_week),
    string.format(" %-12s - Next week", config.options.calendar.keymaps.next_week),
    string.format(" %-12s - Previous month", config.options.calendar.keymaps.previous_month),
    string.format(" %-12s - Next month", config.options.calendar.keymaps.next_month),
    string.format(" %-12s - Select date", config.options.calendar.keymaps.select_day),
    string.format(" %-12s - Close calendar", config.options.calendar.keymaps.close_calendar),
    "",
  }

  vim.api.nvim_buf_set_lines(constants.help_buf_id, 0, -1, false, help_content)
  vim.api.nvim_buf_set_option(constants.help_buf_id, "modifiable", false)
  vim.api.nvim_buf_set_option(constants.help_buf_id, "buftype", "nofile")

  for i = 0, #help_content - 1 do
    vim.api.nvim_buf_add_highlight(constants.help_buf_id, constants.ns_id, "DooingHelpText", i, 0, -1)
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = constants.help_buf_id,
    callback = function()
      if constants.help_win_id and vim.api.nvim_win_is_valid(constants.help_win_id) then
        vim.api.nvim_win_close(constants.help_win_id, true)
        constants.help_win_id = nil
        constants.help_buf_id = nil
      end
      return true
    end,
  })

  local function close_help()
    if constants.help_win_id and vim.api.nvim_win_is_valid(constants.help_win_id) then
      vim.api.nvim_win_close(constants.help_win_id, true)
      constants.help_win_id = nil
      constants.help_buf_id = nil
    end
  end

  vim.keymap.set("n", config.options.keymaps.close_window, close_help, { buffer = constants.help_buf_id, nowait = true })
  vim.keymap.set("n", config.options.keymaps.toggle_help, close_help, { buffer = constants.help_buf_id, nowait = true })
end

-- Creates and manages the tags window
function M.create_tag_window()
  if constants.tag_win_id and vim.api.nvim_win_is_valid(constants.tag_win_id) then
    vim.api.nvim_win_close(constants.tag_win_id, true)
    constants.tag_win_id = nil
    constants.tag_buf_id = nil
    return
  end

  constants.tag_buf_id = vim.api.nvim_create_buf(false, true)

  local width = 30
  local height = 10
  local ui = vim.api.nvim_list_uis()[1]
  local main_width = 40
  local main_col = math.floor((ui.width - main_width) / 2)
  local col = main_col - width - 2
  local row = math.floor((ui.height - height) / 2)

  constants.tag_win_id = vim.api.nvim_open_win(constants.tag_buf_id, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " tags ",
    title_pos = "center",
  })

  local tags = state.get_all_tags()
  if #tags == 0 then
    tags = { "No tags found" }
  end

  vim.api.nvim_buf_set_lines(constants.tag_buf_id, 0, -1, false, tags)
  vim.api.nvim_buf_set_option(constants.tag_buf_id, "modifiable", true)

  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(constants.tag_win_id)
    local tag = vim.api.nvim_buf_get_lines(constants.tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
    if tag ~= "No tags found" then
      state.set_filter(tag)
      vim.api.nvim_win_close(constants.tag_win_id, true)
      constants.tag_win_id = nil
      constants.tag_buf_id = nil
      local rendering = require("dooing.ui.rendering")
      rendering.render_todos()
    end
  end, { buffer = constants.tag_buf_id })

  vim.keymap.set("n", config.options.keymaps.edit_tag, function()
    local cursor = vim.api.nvim_win_get_cursor(constants.tag_win_id)
    local old_tag = vim.api.nvim_buf_get_lines(constants.tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
    if old_tag ~= "No tags found" then
      vim.ui.input({ prompt = "Edit tag: ", default = old_tag }, function(new_tag)
        if new_tag and new_tag ~= "" and new_tag ~= old_tag then
          state.rename_tag(old_tag, new_tag)
          local tags = state.get_all_tags()
          vim.api.nvim_buf_set_lines(constants.tag_buf_id, 0, -1, false, tags)
          local rendering = require("dooing.ui.rendering")
          rendering.render_todos()
        end
      end)
    end
  end, { buffer = constants.tag_buf_id })

  vim.keymap.set("n", config.options.keymaps.delete_tag, function()
    local cursor = vim.api.nvim_win_get_cursor(constants.tag_win_id)
    local tag = vim.api.nvim_buf_get_lines(constants.tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
    if tag ~= "No tags found" then
      state.delete_tag(tag)
      local tags = state.get_all_tags()
      if #tags == 0 then
        tags = { "No tags found" }
      end
      vim.api.nvim_buf_set_lines(constants.tag_buf_id, 0, -1, false, tags)
      local rendering = require("dooing.ui.rendering")
      rendering.render_todos()
    end
  end, { buffer = constants.tag_buf_id })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(constants.tag_win_id, true)
    constants.tag_win_id = nil
    constants.tag_buf_id = nil
    vim.api.nvim_set_current_win(constants.win_id)
  end, { buffer = constants.tag_buf_id })
end

-- Handle search queries
local function handle_search_query(query)
  if not query or query == "" then
    if constants.search_win_id and vim.api.nvim_win_is_valid(constants.search_win_id) then
      vim.api.nvim_win_close(constants.search_win_id, true)
      vim.api.nvim_set_current_win(constants.win_id)
      constants.search_win_id = nil
      constants.search_buf_id = nil
    end
    return
  end

  local done_icon = config.options.formatting.done.icon
  local pending_icon = config.options.formatting.pending.icon
  local in_progress_icon = config.options.formatting.in_progress.icon

  -- Prepare the search results
  local results = state.search_todos(query)
  vim.api.nvim_buf_set_option(constants.search_buf_id, "modifiable", true)
  local lines = { "Search Results for: " .. query, "" }
  local valid_lines = {} -- Store valid todo lines
  if #results > 0 then
    for _, result in ipairs(results) do
      local icon = result.todo.done and done_icon or pending_icon
      local line = string.format("  %s %s", icon, result.todo.text)
      table.insert(lines, line)
      table.insert(valid_lines, { line_index = #lines, result = result })
    end
  else
    table.insert(lines, "  No results found")
    vim.api.nvim_set_current_win(constants.win_id)
  end

  -- Add search results to window
  vim.api.nvim_buf_set_lines(constants.search_buf_id, 0, -1, false, lines)

  -- After adding search results, make it unmodifiable
  vim.api.nvim_buf_set_option(constants.search_buf_id, "modifiable", false)

  -- Highlight todos on search results
  for i, line in ipairs(lines) do
    if line:match("%s+[" .. done_icon .. pending_icon .. in_progress_icon .. "]") then
      local hl_group = line:match(done_icon) and "DooingDone" or "DooingPending"
      vim.api.nvim_buf_add_highlight(constants.search_buf_id, constants.ns_id, hl_group, i - 1, 0, -1)
      for tag in line:gmatch("#(%w+)") do
        local start_idx = line:find("#" .. tag) - 1
        vim.api.nvim_buf_add_highlight(constants.search_buf_id, constants.ns_id, "Type", i - 1, start_idx,
          start_idx + #tag + 1)
      end
    elseif line:match("Search Results") then
      vim.api.nvim_buf_add_highlight(constants.search_buf_id, constants.ns_id, "WarningMsg", i - 1, 0, -1)
    end
  end

  -- Close search window
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(constants.search_win_id, true)
    constants.search_win_id = nil
    constants.search_buf_id = nil
    if constants.win_id and vim.api.nvim_win_is_valid(constants.win_id) then
      vim.api.nvim_set_current_win(constants.win_id)
    end
  end, { buffer = constants.search_buf_id, nowait = true })

  -- Jump to todo in main window
  vim.keymap.set("n", "<CR>", function()
    local current_line = vim.api.nvim_win_get_cursor(constants.search_win_id)[1]
    local matched_result = nil
    for _, item in ipairs(valid_lines) do
      if item.line_index == current_line then
        matched_result = item.result
        break
      end
    end
    if matched_result then
      vim.api.nvim_win_close(constants.search_win_id, true)
      constants.search_win_id = nil
      constants.search_buf_id = nil
      vim.api.nvim_set_current_win(constants.win_id)
      vim.api.nvim_win_set_cursor(constants.win_id, { matched_result.lnum + 1, 3 })
    end
  end, { buffer = constants.search_buf_id, nowait = true })
end

-- Search for todos
function M.create_search_window()
  -- If search window exists and is valid, focus on the existing window and return
  if constants.search_win_id and vim.api.nvim_win_is_valid(constants.search_win_id) then
    vim.api.nvim_set_current_win(constants.search_win_id)
    vim.ui.input({ prompt = "Search todos: " }, function(query)
      handle_search_query(query)
    end)
    return
  end

  -- If search window exists but is not valid, reset IDs
  if constants.search_win_id and vim.api.nvim_win_is_valid(constants.search_win_id) then
    constants.search_win_id = nil
    constants.search_buf_id = nil
  end

  -- Create search results buffer
  constants.search_buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(constants.search_buf_id, "buflisted", true)
  vim.api.nvim_buf_set_option(constants.search_buf_id, "modifiable", false)
  vim.api.nvim_buf_set_option(constants.search_buf_id, "filetype", "todo_search")
  local width = 40
  local height = 10
  local ui = vim.api.nvim_list_uis()[1]
  local main_width = 40
  local main_col = math.floor((ui.width - main_width) / 2)
  local col = main_col - width - 2
  local row = math.floor((ui.height - height) / 2)
  constants.search_win_id = vim.api.nvim_open_win(constants.search_buf_id, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Search Todos ",
    title_pos = "center",
  })

  -- Create search query pane
  vim.ui.input({ prompt = "Search todos: " }, function(query)
    handle_search_query(query)
  end)

  -- Close the search window if main window is closed
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(constants.win_id),
    callback = function()
      if constants.search_win_id and vim.api.nvim_win_is_valid(constants.search_win_id) then
        vim.api.nvim_win_close(constants.search_win_id, true)
        constants.search_win_id = nil
        constants.search_buf_id = nil
      end
    end,
  })
end

-- Scratchpad component
function M.open_todo_scratchpad()
  local cursor = vim.api.nvim_win_get_cursor(constants.win_id)
  local todo_index = cursor[1] - 1
  local todo = state.todos[todo_index]

  if not todo then
    vim.notify("No todo selected", vim.log.levels.WARN)
    return
  end

  if todo.notes == nil then
    todo.notes = ""
  end

  local function is_valid_filetype(filetype)
    local syntax_file = vim.fn.globpath(vim.o.runtimepath, "syntax/" .. filetype .. ".vim")
    return syntax_file ~= ""
  end

  local scratch_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(scratch_buf, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(scratch_buf, "swapfile", false)

  local syntax_highlight = config.options.scratchpad.syntax_highlight
  if not is_valid_filetype(syntax_highlight) then
    vim.notify(
      "Invalid scratchpad syntax highlight '" .. syntax_highlight .. "'. Using default 'markdown'.",
      vim.log.levels.WARN
    )
    syntax_highlight = "markdown"
  end

  vim.api.nvim_buf_set_option(scratch_buf, "filetype", syntax_highlight)

  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * 0.6)
  local height = math.floor(ui.height * 0.6)
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local scratch_win = vim.api.nvim_open_win(scratch_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Scratchpad ",
    title_pos = "center",
  })

  local initial_notes = todo.notes or ""
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, vim.split(initial_notes, "\n"))

  local function close_notes()
    if vim.api.nvim_win_is_valid(scratch_win) then
      vim.api.nvim_win_close(scratch_win, true)
    end

    if vim.api.nvim_buf_is_valid(scratch_buf) then
      vim.api.nvim_buf_delete(scratch_buf, { force = true })
    end
  end

  local function save_notes()
    local lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
    local new_notes = table.concat(lines, "\n")

    if new_notes ~= initial_notes then
      todo.notes = new_notes
      state.save_todos()
      vim.notify("Notes saved", vim.log.levels.INFO)
    end

    close_notes()
  end

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = scratch_buf,
    callback = save_notes,
  })

  vim.keymap.set("n", "<CR>", save_notes, { buffer = scratch_buf })
  vim.keymap.set("n", "<Esc>", save_notes, { buffer = scratch_buf })
end

return M
