# CLAUDE.md

Dooing is a minimalist todo list manager for Neovim. It provides a floating window UI for managing tasks with tags, priorities, due dates, nested subtasks, and per-project todo lists. Target: Neovim users who want lightweight task tracking without leaving the editor.

## Tech Stack & Constraints

- **Language:** Lua only (no Vimscript except the 4-line bootstrap in `plugin/dooing.vim`)
- **Runtime:** Neovim ≥ 0.10.0 plugin, managed by [lazy.nvim](https://github.com/folke/lazy.nvim)
- **Dependencies:** None (no luarocks, no build step, no external tools)
- **Testing:** `scripts/test.sh` (or `nvim -l spec/run.lua`) runs `spec/*_spec.lua` under Neovim itself — same ~60-line runner as bloocky.nvim, no busted, no dependencies. `describe`/`it`/`eq`/`neq`/`truthy`/`falsy` are globals from `spec/run.lua`. UI code is still verified manually (check `:messages`, visual inspection)
- **Linting/Formatting:** No `.luarc.json`, `.stylua.toml`, or `.editorconfig` — follow existing code style

## Architecture

```
plugin/dooing.vim          ← Bootstrap: calls require('dooing').setup()
lua/dooing/
├── init.lua               ← Entry point: setup(), user commands (:Dooing, :DooingLocal, :DooingDue), keymaps
├── config.lua             ← M.defaults + M.setup(opts) merges user config via vim.tbl_deep_extend
├── state.lua              ← Data layer: todo CRUD, persistence (JSON), sorting, filtering, undo, git detection
├── server.lua             ← LAN share/sync server: QR pairing page, /version, authenticated data routes
├── sync/
│   ├── httpd.lua          ← Pure HTTP request framing + Host/Origin guards + response builders (spec-covered)
│   ├── devices.lua        ← Paired devices: pairing tokens, hashed bearer tokens, 0600 atomic store
│   ├── canonical.lua      ← Stable canonical serialization; null == absent. PARITY-CRITICAL with the app's canonical.ts
│   ├── merge.lua          ← Three-way per-field-group todo merge — the REFERENCE implementation; the app's merge.ts is a port
│   ├── store.lua          ← Sync sidecar (dooing_sync.json): per-device bases + revisions, conflict trail
│   └── exchange.lua       ← One POST /v2/sync/todos exchange + :DooingSyncStatus/Report/Restore
└── ui/
    ├── init.lua            ← UI coordinator: public API that delegates to sub-modules
    ├── constants.lua       ← Shared mutable state: win/buf IDs, namespace, highlight cache
    ├── highlights.lua      ← Highlight group setup and priority-based coloring
    ├── utils.lua           ← Utility functions: time formatting, time parsing, todo text rendering, line→todo lookup
    ├── window.lua          ← Main floating window creation, positioning, quick-keys panel, title/footer
    ├── rendering.lua       ← Renderer dispatch (classic vs modern) + classic rendering
    ├── modern.lua          ← Opt-in "modern" renderer: sections, tree guides, right-aligned metadata
    ├── panels.lua          ← Opt-in "modern" sub-windows: centered input, help, tags, search
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
ui/rendering.lua → ui/constants, ui/utils, ui/highlights, ui/modern, state, config
ui/modern.lua → ui/highlights, ui/utils, ui/calendar, config
ui/components.lua → ui/panels (modern only; classic implementations stay in place)
ui/panels.lua → ui/constants, config, state
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
| `updated_at`       | `number\|nil`  | Unix timestamp of the last mutation. Optional for readers: absent falls back to `created_at`. Stamped automatically at save time (see gotcha below) |

**Critical rule:** `state.lua` owns all data mutations. Always call `state.save_todos()` after modifying `state.todos`.

## Configuration Pattern

- `config.lua` defines `M.defaults` with all default values
- `M.setup(opts)` merges user config: `vim.tbl_deep_extend("force", M.defaults, opts or {})`
- All runtime access goes through `config.options.*`
- Keymaps can be disabled by setting them to `false` (checked in `init.lua` before `vim.keymap.set`)
- When adding a new config option: add default to `M.defaults`, access via `config.options.your_option`
- **Window size (`window.dimensions`):** may be a table `{ width = <n>, height = <n> }` **or** a function returning such a table (evaluated on every window creation, so sizes can adapt to `vim.o.columns` / `vim.o.lines`). Never read `config.options.window.dimensions` directly — call `config.get_window_dimensions()`, which resolves the function form, accepts positional `{ <w>, <h> }` tables, floors/clamps to the editor size, and falls back to `{ width = 55, height = 20 }` on invalid values
- The legacy `window.width` / `window.height` options are deprecated: `M.setup()` folds user-supplied values into `window.dimensions` (with a `vim.notify` warning) and removes the legacy keys from `config.options.window`
- **LAN server (`sync.server`):** `port` (7283), `bind`, and `allow_v1` (serve `/todos`/`/blocks` without a device token — deprecated compatibility for pre-pairing app builds). See `docs/SYNC-PROTOCOL.md`.
- **UI style (`ui.style`):** `"classic"` (default) or `"modern"`. Never read `config.options.ui.*` directly — use `config.is_modern()`, `config.modern_feature("<name>")` (which returns false whenever the style is not modern, so classic can never be affected by a sub-toggle), and `config.ui_icon("<name>")`

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

- **Never map cursor lines to todos with arithmetic.** The buffer contains lines that are not todos (section headers, metadata continuation lines, blank spacers), so `cursor_line - 1` is wrong. Both renderers publish `constants.line_to_todo` (1-based buffer line → index into `state.todos`); read it via `ui/utils.todo_index_at_cursor()` / `todo_index_at_line()`, which return `nil` on non-todo lines. Always guard with `if todo_index and state.todos[todo_index]`.
- **Any new renderer must populate `constants.line_to_todo`**, or every action silently operates on the wrong todo.
- **`render_todos({ focus_first = true })` parks the cursor on the first todo**, skipping the usual cursor restore. Pass it only when a list is opened or swapped (`toggle_todo_window`, the global/project switch paths in `init.lua`); a plain `render_todos()` after an edit must preserve the cursor, or every toggle would jump the user back to the top.
- **Two maps, different jobs.** `constants.line_to_todo` maps *every* line a row occupies (primary line, overflowed metadata, note preview) → todo index, and is what cursor lookups use. `constants.primary_lines` maps todo index → its first line, and is what fold restore and the search jump use. Don't invert `line_to_todo` to find a todo's position — a row can span several lines, so the result is arbitrary.
- **Modern highlights are byte offsets, not patterns.** `ui/modern.lua` builds each line from typed segments and records exact byte ranges (`#text`, not `strdisplaywidth`) as it goes. Don't re-match the finished line the way the classic renderer does.
- **Sections group whole subtrees.** Only depth-0 todos choose a section; descendants follow their parent, so nesting is never split. Section counts are top-level items, not rendered rows.
- **Tree guide columns are 3 wide** (`"│  "` / `"   "`) to match `"├─ "`. Using 2 makes each nesting level drift left by one column.
- **Prompts go through `panels.prompt()`**, which uses the centered input box in modern and `vim.ui.input` in classic. Import/export deliberately stay on `vim.ui.input` because the centered box has no filename completion.
- **Panels never parse their own display text.** The tags window keeps a `line_to_tag` map and search keeps `line_to_result`, so labels can carry counts and highlights without the value having to be recovered from the rendered line.
- **`state.search_todos()` returns `lnum` = index into `state.todos`, not a buffer line.** Resolve it through `constants.line_to_todo` before moving the cursor.
- **The calendar grid is driven by one `layout` table** (`pad`, `cell`, `num_off`, `header_rows`, `width`, `height`) chosen by style. Rendering, `get_cursor_position()`, `get_day_from_position()` and the highlight loop all derive their offsets from it — never hardcode the old `col * 3 + 2` / `row + 3` numbers again, or day selection silently maps to the wrong date.
- **Folding differs per style.** Classic uses `foldmethod=indent`, which is inert at the default `shiftwidth=8` (indents 2 and 4 both yield level 0) — pre-existing behavior, left alone. Modern uses `foldmethod=expr` with `modern.foldexpr()`, reading `constants.fold_levels`; rows with children emit `">" .. level` so each parent gets its own fold.
- **Duplicate function definitions in `state.lua`:** `delete_todo()` and `delete_completed()` are defined twice — the second definitions (near the bottom) override the first to add undo support. This is intentional.
- **`---@diagnostic disable` lines** at the top of UI files suppress known warnings — don't remove them.
- **`window.width` / `window.height` no longer exist at runtime** — they are migrated into `window.dimensions` during `config.setup()`. Any new code needing the window size must use `config.get_window_dimensions()` (consumers: `ui/window.lua`, `ui/rendering.lua`, `ui/due_notification.lua`).
- **Git root detection** uses `io.popen("git rev-parse --show-toplevel")` — synchronous/blocking. Keep this in mind for performance.
- **UI has no automated tests** — verify UI changes manually with various configurations, empty/full todo lists, and nested task scenarios. Check `:messages` for Lua errors. Data/server logic IS spec-covered: run `scripts/test.sh` before and after touching `state.lua`, `server.lua` or `sync/`.
- **`updated_at` is stamped at save time, not at mutation sites.** `save_todos()` diffs each todo against a snapshot of the last load/save (`updated_at` excluded from the diff) and stamps only what changed. This catches the UI layer's direct field writes without scattering bumps — but it means the snapshot ordering in the load functions is load-bearing: `snapshot_loaded()` must run **before** `migrate_todos()`, or every load re-stamps every todo.
- **`server.lua` serves live data with security guards** — todos are read from disk per request (never a snapshot), every request passes Host/Origin checks (`sync/httpd.lua`), and there are deliberately **no CORS headers**. The protocol (QR payload, pairing, auth posture, `allow_v1` compatibility) is normative in `docs/SYNC-PROTOCOL.md` — change the code and that document together. Device bearer tokens are stored **hashed** in `stdpath("state")/dooing/devices.json` (0600); pairing tokens are single-use, 10-minute, memory-only.
- **The todos file is written `0600`** via `vim.uv.fs_open` (it may be served to paired devices). The old `io.open` write is only a fallback.
- **`state.save_todos()` merges, never clobbers.** If the file's mtime/size moved since we last touched it (another Neovim instance, or the sync server in one), the save three-way-merges in-memory edits with the disk's through `sync/merge.lua`, using the pre-stamp snapshot as base. Related: `state.replace_global_todos()` installs already-merged todos **without re-stamping** `updated_at` (the values are part of the device agreement) and is the only correct way for sync code to write the list; `state.reload_if_changed()` re-reads when the file moved (used by nothing UI-side — `open_global_todo` already reloads unconditionally).
- **The sync store deep-copies bases on commit** (`store.commit_exchange`). The merge result's `base` shares tables with its `todos`; stored by reference, the next edit would mutate the "agreement" and change detection would go blind. Same bug class as bloocky's mutated-account-tables fix — don't undo it.
- **Sync commands:** `:DooingServe` / `:DooingServeStop` (the server; auto-starts when a device is paired — `sync.server.enabled = "auto"` — or always when `true`), `:DooingSyncStatus`, `:DooingSyncReport` (reading it acknowledges, clearing markers), `:DooingSyncRestore <n>`, `:DooingSyncRevoke <number|id|unique name>` (unpairs and wipes that device's sync state; ambiguous names are refused, since pairing the same phone twice yields duplicates).
- **`sync/merge.lua` is the reference implementation of the todo merge** — the app ports it, never the other way round. Its behaviour is pinned by `spec/fixtures/merge/cases.json`, which the app runs verbatim from a vendored copy (with a drift check). Change the algorithm ⇒ change the corpus ⇒ both suites must pass. Semantics that are easy to get wrong: `base` decides *whether* something changed, `updated_at` only breaks ties (smaller device id wins exact ties); delete-vs-edit always resurrects; notes take a strict prefix/suffix superset silently; cycles promote the member with the oldest change; `category` is derived (shared charset `[A-Za-z0-9_/-]`, from PR #88) and `depth` recomputed — neither is ever merged.
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
