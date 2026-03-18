# CLAUDE.md

Dooing is a minimalist todo list manager for Neovim. It provides a floating window UI for managing tasks with tags, priorities, due dates, nested subtasks, and per-project todo lists. Target: Neovim users who want lightweight task tracking without leaving the editor.

## Tech Stack & Constraints

- **Language:** Lua only (no Vimscript except the 4-line bootstrap in `plugin/dooing.vim`)
- **Runtime:** Neovim ≥ 0.10.0 plugin, managed by [lazy.nvim](https://github.com/folke/lazy.nvim)
- **Dependencies:** None (no luarocks, no build step, no external tools)
- **Testing:** No test framework or CI — all testing is manual (check `:messages` for errors, visual inspection)
- **Linting/Formatting:** No `.luarc.json`, `.stylua.toml`, or `.editorconfig` — follow existing code style

## Architecture

```
plugin/dooing.vim          ← Bootstrap: calls require('dooing').setup()
lua/dooing/
├── init.lua               ← Entry point: setup(), user commands (:Dooing, :DooingLocal, :DooingDue), keymaps
├── config.lua             ← M.defaults + M.setup(opts) merges user config via vim.tbl_deep_extend
├── state.lua              ← Data layer: todo CRUD, persistence (JSON), sorting, filtering, undo, git detection
├── server.lua             ← QR code share server (raw TCP via vim.loop) — self-contained, rarely touched
└── ui/
    ├── init.lua            ← UI coordinator: public API that delegates to sub-modules
    ├── constants.lua       ← Shared mutable state: win/buf IDs, namespace, highlight cache
    ├── highlights.lua      ← Highlight group setup and priority-based coloring
    ├── utils.lua           ← Utility functions: time formatting, time parsing, todo text rendering
    ├── window.lua          ← Main floating window creation, positioning, quick-keys panel
    ├── rendering.lua       ← Todo list rendering and highlight application
    ├── actions.lua         ← Todo CRUD UI operations (new, edit, toggle, delete, import/export, etc.)
    ├── components.lua      ← Sub-windows: help, tags, search, scratchpad
    ├── keymaps.lua         ← Keymap registration for the todo buffer
    ├── calendar.lua        ← Calendar picker for due dates (multi-language)
    └── due_notification.lua ← Due/overdue item notification window
```

### Module Dependency Flow

```
init.lua → config.lua, state.lua, ui/init.lua
ui/init.lua → ui/constants, ui/window, ui/rendering, ui/actions, ui/keymaps, ui/utils
ui/actions.lua → ui/constants, ui/utils, state, config, ui/calendar, server
ui/rendering.lua → ui/constants, ui/utils, ui/highlights, state, config
state.lua → config (for save_path, priorities, nested_tasks settings)
```

All modules are singletons accessed via `require()`. No events or callback systems between modules.

## Data Model

Todos are stored as a **flat JSON array** in a single file (default: `vim.fn.stdpath("data") .. "/dooing_todos.json"`). Nesting is simulated via `parent_id`/`depth` fields — **not** nested JSON.

### Todo Object Fields

| Field              | Type           | Description                                       |
|--------------------|----------------|---------------------------------------------------|
| `id`               | `string`       | Unique ID: `os.time() .. "_" .. math.random()`    |
| `text`             | `string`       | Todo text, may contain `#tags` inline              |
| `done`             | `boolean`      | Completion status                                  |
| `in_progress`      | `boolean`      | In-progress status (3-state cycle: pending → in_progress → done) |
| `category`         | `string`       | First `#tag` extracted from text                   |
| `created_at`       | `number`       | Unix timestamp                                     |
| `completed_at`     | `number\|nil`  | Unix timestamp when marked done                    |
| `priorities`       | `string[]\|nil`| List of priority names (e.g. `{"important","urgent"}`) |
| `estimated_hours`  | `number\|nil`  | Estimated completion time in hours                 |
| `due_at`           | `number\|nil`  | Due date as Unix timestamp (end of day)            |
| `notes`            | `string`       | Scratchpad notes for this todo                     |
| `parent_id`        | `string\|nil`  | ID of parent todo (nil = top-level)                |
| `depth`            | `number`       | Nesting level (0 = top-level)                      |

**Critical rule:** `state.lua` owns all data mutations. Always call `state.save_todos()` after modifying `state.todos`.

## Configuration Pattern

- `config.lua` defines `M.defaults` with all default values
- `M.setup(opts)` merges user config: `vim.tbl_deep_extend("force", M.defaults, opts or {})`
- All runtime access goes through `config.options.*`
- Keymaps can be disabled by setting them to `false` (checked in `init.lua` before `vim.keymap.set`)
- When adding a new config option: add default to `M.defaults`, access via `config.options.your_option`

## Code Conventions

- Use `vim.api.*` for all buffer/window operations
- Use `vim.api.nvim_buf_set_option()` / `nvim_win_set_option()` (the codebase uses this style consistently, not `vim.bo`/`vim.wo`)
- Floating windows: `vim.api.nvim_open_win()` with `relative = "editor"`
- Shared mutable state (window IDs, buffer IDs): stored in `ui/constants.lua`
- Functions are `local` unless exported in the module's return table
- Standard Lua naming: `snake_case` for variables and functions
- Comments for complex logic; no docstring convention beyond `---@class` annotations in `ui/init.lua`

## Common Development Recipes

### Adding a new keymap action

1. Add default key to `config.lua` → `M.defaults.keymaps.your_action = "<key>"`
2. Add handler in `ui/keymaps.lua` → `vim.keymap.set("n", keys.your_action, function() ... end, opts)`
3. Implement logic in `ui/actions.lua` (for todo operations) or `ui/components.lua` (for new UI panels)
4. Update `doc/dooing.txt` and `README.md` keybinding tables

### Adding a new todo field

1. Add field with default value in `state.add_todo()` and `state.add_nested_todo()`
2. Add migration logic in `state.migrate_todos()` for existing data
3. Update rendering in `ui/rendering.lua` to display the field
4. Add to format options in `config.lua` `M.defaults.formatting` if user-configurable
5. Add UI actions (add/remove/edit) in `ui/actions.lua` + keymap in `ui/keymaps.lua`

### Adding a new UI component (sub-window)

1. Create the function in `ui/components.lua` (or a new file under `ui/` if substantial)
2. Wire a keymap in `ui/keymaps.lua`
3. If the component needs its own win/buf IDs, add them to `ui/constants.lua`
4. Export through `ui/init.lua` if needed externally
5. Ensure cleanup in `ui/window.lua` → `close_window()`

## Gotchas & Pitfalls

- **Duplicate function definitions in `state.lua`:** `delete_todo()` and `delete_completed()` are defined twice — the second definitions (near the bottom) override the first to add undo support. This is intentional.
- **`---@diagnostic disable` lines** at the top of UI files suppress known warnings — don't remove them.
- **Git root detection** uses `io.popen("git rev-parse --show-toplevel")` — synchronous/blocking. Keep this in mind for performance.
- **No automated tests** — verify changes manually with various configurations, empty/full todo lists, and nested task scenarios. Check `:messages` for Lua errors.
- **`server.lua`** is a standalone QR-code share feature using raw TCP (`vim.loop`). It's isolated and rarely needs changes.
- **Per-project todos** store a separate JSON file in the git root (default `dooing.json`), loaded/saved through the same `state.lua` machinery with `state.load_todos_from_path()`.

## Git & Contribution Workflow

- **Upstream:** `atiladefreitas/dooing` (remote `upstream`)
- **Fork:** `<your-username>/dooing` (remote `origin`)
- Branch off `main`, submit PRs to `upstream/main`
- Commit messages: conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`)
- PR template and guidelines: see `CONTRIBUTING.md`

## Maintaining This File

Update `CLAUDE.md` whenever a change affects the information documented here. Specifically:

- **Architecture / file organization:** New modules, renamed files, or changed module responsibilities → update the file tree and dependency flow
- **Data model:** New or removed todo fields → update the field table
- **Configuration:** New config sections or changed defaults structure → update the configuration pattern section
- **Requirements:** Changed minimum Neovim version or new external dependencies → update tech stack
- **Conventions:** New patterns adopted or old ones deprecated → update code conventions
- **Gotchas:** Newly discovered pitfalls or resolved ones → update the gotchas section
