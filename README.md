# Dooing

Dooing is a minimalist todo list manager for Neovim, designed with simplicity and efficiency in mind. It provides a clean, distraction-free interface to manage your tasks directly within Neovim. Perfect for users who want to keep track of their todos without leaving their editor.

![dooing demo](https://github.com/user-attachments/assets/ffb921d6-6dd8-4a01-8aaa-f2440891b22e)



## 🚀 Features

- 📝 Manage todos in a clean **floating window**
- 🏷️ Categorize tasks with **#tags**
- ✅ Simple task management with clear visual feedback
- 💾 **Persistent storage** of your todos
- 🎨 Adapts to your Neovim **colorscheme**
- 🛠️ Compatible with **Lazy.nvim** for effortless installation
- ⏰ **Relative timestamps** showing when todos were created
- 📂 **Per-project todos** with git integration
- 🔔 **Smart due date notifications** on startup and when opening todos
- 📅 **Due items window** to view and jump to all due tasks

---

## 📦 Installation

### Prerequisites

- Neovim `>= 0.10.0`

### Using Neovim Native Package Manager (v0.12+)

Neovim 0.12 ships with a built-in package manager exposed via `vim.pkg`. Add the following to your `init.lua`:

```lua
vim.pkg.add("atiladefreitas/dooing")

require("dooing").setup({
    -- your custom config here (optional)
})
```

### Using Lazy.nvim

```lua
return {
    "atiladefreitas/dooing",
    config = function()
        require("dooing").setup({
            -- your custom config here (optional)
        })
    end,
}
```

Run the following commands in Neovim to install Dooing:

```vim
:Lazy sync
```

### Default Configuration
Dooing comes with sensible defaults that you can override:
```lua
{
    -- Core settings
    save_path = vim.fn.stdpath("data") .. "/dooing_todos.json",
    pretty_print_json = false, -- Pretty-print JSON output (requires jq or python)

    -- Timestamp settings
    timestamp = {
        enabled = true,  -- Show relative timestamps (e.g., @5m ago, @2h ago)
    },

    -- Interface style (see "Modern UI" below). Opt-in: the default keeps the
    -- original look, so updating never changes your interface.
    ui = {
        style = "classic",          -- "classic" | "modern"
        sections = true,            -- group top-level todos under status headings
        priority_bar = true,        -- colored marker instead of coloring the whole row
        tree_connectors = true,     -- draw ├─ / └─ / │ guides for nested tasks
        note_preview = true,        -- first line of a todo's notes, dimmed, beneath it
        progress = true,            -- progress bar in the title, summary in the footer
        compact_quick_keys = true,  -- single strip instead of the tall quick keys panel
        section_titles = {
            in_progress = "IN PROGRESS",
            pending = "PENDING",
            done = "DONE",
        },
        icons = {
            priority_bar = "▎",
            overdue = "󰀦",
            progress_on = "▰",
            progress_off = "▱",
        },
    },

    -- Window settings
    window = {
        -- Size of the floating window; may also be a function returning a
        -- table with these keys (see "Adaptive Window Size" below)
        dimensions = {
            width = 55,     -- Width of the floating window
            height = 20,    -- Height of the floating window
        },
        border = 'rounded', -- Border style: 'single', 'double', 'rounded', 'solid'
        zindex = 50,        -- Base z-index for floating windows (uses zindex to zindex+5)
        position = 'center', -- Window position: 'right', 'left', 'top', 'bottom', 'center',
                           -- 'top-right', 'top-left', 'bottom-right', 'bottom-left'
        padding = {
            top = 1,
            bottom = 1,
            left = 2,
            right = 2,
        },
    },

    -- To-do formatting
    formatting = {
        pending = {
            icon = "○",
            format = { "icon", "notes_icon", "text", "due_date", "ect" },
        },
        in_progress = {
            icon = "◐",
            format = { "icon", "text", "due_date", "ect" },
        },
        done = {
            icon = "✓",
            format = { "icon", "notes_icon", "text", "due_date", "ect" },
        },
    },

    quick_keys = true,      -- Quick keys window
    
    notes = {
        icon = "📓",
    },

    scratchpad = {
        syntax_highlight = "markdown",
    },

    -- Per-project todos
    per_project = {
        enabled = true,                        -- Enable per-project todos
        default_filename = "dooing.json",      -- Default filename for project todos
        auto_gitignore = false,                -- Auto-add to .gitignore (true/false/"prompt")
        on_missing = "prompt",                 -- What to do when file missing ("prompt"/"auto_create")
        auto_open_project_todos = false,       -- Auto-open project todos on startup if they exist
    },

    -- Nested tasks
    nested_tasks = {
        enabled = true,                        -- Enable nested subtasks
        indent = 2,                           -- Spaces per nesting level
        retain_structure_on_complete = true,   -- Keep nested structure when completing tasks
        move_completed_to_end = true,         -- Move completed nested tasks to end of parent group
        inherit_priority = false,             -- Inherit parent priorities and skip the priority prompt
    },

    -- Due date notifications
    due_notifications = {
        enabled = true,                        -- Enable due date notifications
        on_startup = true,                    -- Show notification on Neovim startup
        on_open = true,                       -- Show notification when opening todos
    },

    -- Keymaps
    keymaps = {
        toggle_window = "<leader>td",          -- Toggle global todos
        open_project_todo = "<leader>tD",      -- Toggle project-specific todos
        show_due_notification = "<leader>tN",  -- Show due items window
        new_todo = "i",
        create_nested_task = "<leader>tn",     -- Create nested subtask under current todo
        toggle_todo = "x",
        delete_todo = "d",
        delete_completed = "D",
        close_window = "q",
        undo_delete = "u",
        add_due_date = "H",
        remove_due_date = "r",
        toggle_help = "?",
        toggle_tags = "t",
        toggle_priority = "<Space>",
        clear_filter = "c",
        edit_todo = "e",
        edit_tag = "e",
        edit_priorities = "p",
        delete_tag = "d",
        search_todos = "/",
        add_time_estimation = "T",
        remove_time_estimation = "R",
        import_todos = "I",
        export_todos = "E",
        remove_duplicates = "<leader>D",
        open_todo_scratchpad = "<leader>p",
        refresh_todos = "f",
    },

    calendar = {
        language = "en",
        start_day = "sunday", -- or "monday"
        icon = "",
        keymaps = {
            previous_day = "h",
            next_day = "l",
            previous_week = "k",
            next_week = "j",
            previous_month = "H",
            next_month = "L",
            select_day = "<CR>",
            close_calendar = "q",
        },
    },


    -- Priority settings
    priorities = {
        {
            name = "important",
            weight = 4,
        },
        {
            name = "urgent",
            weight = 2,
        },
    },
    priority_groups = {
        high = {
            members = { "important", "urgent" },
            color = nil,
            hl_group = "DiagnosticError",
        },
        medium = {
            members = { "important" },
            color = nil,
            hl_group = "DiagnosticWarn",
        },
        low = {
            members = { "urgent" },
            color = nil,
            hl_group = "DiagnosticInfo",
        },
    },
    hour_score_value = 1/8,
    done_sort_by_completed_time = false,
}
```

### Modern UI

Dooing ships a redesigned interface behind `ui.style = "modern"`. It is **opt-in** —
the default `"classic"` style is byte-for-byte what it always was, so updating the
plugin never changes your interface.

```lua
require("dooing").setup({
    ui = { style = "modern" },
})
```

Classic (default):

```
   ○ Fix login redirect #work [≈ 2h] [!August 8, 2026]  @just now
     ○ Reproduce on staging                             @just now
       ○ Capture HAR file                               @just now
     ○ Add regression test                              @just now
  󱞁 ◐ Write release notes #docs [≈ 1d] [August 11, 2026] @just now
   ✓ Update CI matrix #ops                              @just now
```

Modern:

```
╭──────────── Global to-dos  1/8 ▰▰▱▱▱▱▱▱ ────────────╮
│  IN PROGRESS ───────────────────────────────────── 1 │
│  ◐ 󱞁 Write release notes #docs                       │
│                             ≈1d  due today  just now │
│                                                      │
│  PENDING ───────────────────────────────────────── 3 │
│ ▎○ Fix login redirect #work                          │
│                          ≈2h  󰀦 overdue 3d  just now │
│  ├─ ○ Reproduce on staging                  just now │
│  │  └─ ○ Capture HAR file                   just now │
│  └─ ○ Add regression test                   just now │
│ ▎○ Plan Q3 roadmap #work      September 20  just now │
│                                                      │
│  DONE ──────────────────────────────────────────── 1 │
│  ✓ Update CI matrix #ops                    just now │
╰──────── [?] for help · 1 overdue ────────────────────╯
```

What changes:

- **Status sections.** Top-level todos are grouped under `IN PROGRESS` / `PENDING` /
  `DONE` with a count. Subtasks always stay under their parent, so nesting is never
  split across sections.
- **Priority as a marker.** Only the `▎` marker and the status icon carry the priority
  color, instead of tinting the entire row, so the text stays readable.
- **Right-aligned dimmed metadata.** Estimate, due date and age move to the right of the
  row, or onto their own dimmed line when the row would otherwise be squeezed.
- **Tree connectors.** Nested tasks are drawn with `├─` / `└─` / `│` guides.
- **Sharper due dates.** Overdue reads `󰀦 overdue 3d` in red, with distinct accents for
  `due today`, `due tomorrow` and `in 5d`; anything further out degrades to a plain date.
- **Progress indicators.** The title carries a completion bar and the footer reports
  overdue counts.
- **Compact quick keys.** The fixed 8-line panel becomes a width-adaptive strip.
- **Working fold support.** Folds are computed from each todo's real nesting depth, so
  `zc` on a parent collapses exactly its own subtree. The classic style folds on
  character indent, which does nothing unless `shiftwidth` happens to be small.
- **Note previews.** A todo's description lives in its notes (`<leader>p` opens the
  scratchpad). The first line is shown beneath the todo, dimmed and aligned with the
  text, truncated with `…` when it does not fit:

  ```
    ◐ 󱞁 Ship the v2 release notes #docs     ≈1d  due today  2d
        Highlight the new folding support and the modern UI opt-in.
  ```

  Every line a todo occupies — its own row, an overflowed metadata line and the note
  preview — resolves back to that todo, so pressing `<leader>p`, `x` or `d` works from
  any of them. Set `ui.note_preview = false` to show only the `󱞁` indicator.
- **Redesigned sub-windows.** Help, tags, search, the calendar and every text prompt are
  centered on the editor and sized from their own content (see below).

#### Sub-windows

In the modern style all secondary windows are centered on the editor and sized from
their content, instead of being positioned against a hard-coded guess at the main
window's width.

- **Prompts** (new to-do, sub-task, edit, time estimation, tag rename, search) use a
  centered input box that opens straight into insert mode, rather than the cmdline:

  ```
  ╭───────────────── New to-do ──────────────────╮
  │ buy milk #groceries                          │
  ╰─ <CR> confirm · <Esc> cancel · #tag to categorise ─╯
  ```

  Import/export keep using `vim.ui.input`, since they rely on filename completion.

- **Help** is grouped by what the keys actually do, with the key column aligned across
  all groups, and it skips any keymap you have disabled:

  ```
    TODOS ──────────────────────────────────────
     i            Add new to-do
     <leader>tn   Add nested sub-task
     x            Toggle to-do status
    METADATA ───────────────────────────────────
     H            Add due date
  ```

- **Tags** shows how many todos carry each tag:

  ```
    #docs                         1
    #ops                          1
    #work                         2
  ```

- **Search** prompts in the centered input, then lists matches with the matched text
  highlighted and the result count in the footer. `<CR>` jumps to the todo in the main
  list, clearing an active tag filter first if it would hide the match.

- **Calendar** is centered on the editor with the navigation keys spelled out in the
  footer, instead of being anchored to wherever the cursor happened to be. The grid is
  roomier than the classic one (32×10 vs 26×9), with wider day cells and the weekday
  names separated from the days:

  ```
  ╭─────── August 2026 ────────╮
  │                            │
  │    Su  Mo  Tu  We  Th  Fr  Sa │
  │                            │
  │                          1 │
  │     2   3   4   5   6   7   8 │
  │     9  10  11  12  13  14  15 │
  │    16  17  18  19  20  21  22 │
  ╰──── hjkl move · <CR> select ───╯
  ```

Every bullet above has its own toggle under `ui`, so you can mix and match — for example,
sections without tree guides:

```lua
require("dooing").setup({
    ui = { style = "modern", tree_connectors = false },
})
```

All colors are ordinary highlight groups linked to sensible defaults, so a colorscheme
or your own config can override any of them:

```lua
vim.api.nvim_set_hl(0, "DooingSectionTitle", { fg = "#89b4fa", bold = true })
vim.api.nvim_set_hl(0, "DooingOverdue", { fg = "#f38ba8" })
```

### Highlight Groups

Every group is defined as a `default` link, so a colorscheme or your own
`nvim_set_hl` call always wins.

| Group | Default link | Used for |
|-------|--------------|----------|
| `DooingPending` | `Question` | Pending todos (classic rows, modern icons) |
| `DooingDone` | `Comment` | Completed todos |
| `DooingTimestamp` | `Comment` | Relative timestamps (classic) |
| `DooingHelpText` | `Directory` | Help window text |
| `DooingText` | `Normal` | Todo text (modern) |
| `DooingMeta` | `Comment` | Estimates, ages, distant dates (modern) |
| `DooingTag` | `Type` | `#tags` |
| `DooingSectionTitle` | `Title` | Section headings and window title |
| `DooingSectionCount` | `Comment` | Section counts, progress numbers |
| `DooingSectionRule` | `NonText` | Section separator rule |
| `DooingTreeGuide` | `NonText` | Nested task connectors |
| `DooingOverdue` | `DiagnosticError` | Overdue due dates |
| `DooingDueToday` | `DiagnosticWarn` | Due today |
| `DooingDueSoon` | `DiagnosticInfo` | Due tomorrow / within a week |
| `DooingProgressOn` | `DiagnosticOk` | Filled progress bar cells |
| `DooingProgressOff` | `NonText` | Empty progress bar cells |
| `DooingQuickTitle` | `Title` | Quick keys panel title |
| `DooingQuickKey` | `Identifier` | Quick keys panel keys |
| `DooingQuickDesc` | `Comment` | Quick keys panel descriptions |

Priority colors come from `priority_groups`, which can set either a `color`
(hex string) or an `hl_group`.

### Adaptive Window Size

`window.dimensions` accepts either a table or a **function** returning one. The
function is evaluated every time the todo window is opened, so the window can
adapt to the current editor size:

```lua
require("dooing").setup({
    window = {
        dimensions = function()
            return {
                width = math.max(40, math.floor(vim.o.columns * 0.4)),
                height = math.max(10, math.floor(vim.o.lines * 0.6)),
            }
        end,
    },
})
```

Values are floored and clamped to the space available in the editor. If the
function raises an error or returns something unusable, Dooing falls back to
`{ width = 55, height = 20 }`.

> [!NOTE]
> The former `window.width` / `window.height` options are deprecated but still
> honoured: they are folded into `window.dimensions` (with a warning), so
> existing configurations keep working.

## 📂 Per-Project Todos

Dooing supports project-specific todo lists that are separate from your global todos. This feature integrates with git repositories to automatically detect project boundaries.

### Usage

- **`<leader>td`** - Open/toggle **global** todos (works everywhere)
- **`<leader>tD`** - Open/toggle **project-specific** todos (only in git repositories)

### How it works

1. When you press `<leader>tD` in a git repository, Dooing looks for a todo file in the project root
2. If the file exists, it loads those todos
3. If not, it prompts you to create one with an optional custom filename
4. Project todos are completely separate from global todos
5. Switch between them anytime using the different keymaps

### Configuration Options

```lua
per_project = {
    enabled = true,                    -- Enable/disable per-project todos
    default_filename = "dooing.json",  -- Default filename for new project todo files
    auto_gitignore = false,           -- Automatically add to .gitignore
                                      -- Set to true for auto-add, "prompt" to ask, false to skip
    on_missing = "prompt",            -- What to do when project todo file doesn't exist
                                      -- "prompt" = ask user, "auto_create" = create automatically
    auto_open_project_todos = false,  -- Auto-open project todos on startup if they exist
                                      -- Opens window automatically when entering a git project with todos
}
```

---

## Commands

Dooing provides several commands for task management:

- `:Dooing` - Opens the global todo window
- `:DooingLocal` - Opens the project-specific todo window (git repositories only)
- `:DooingDue` - Opens a window showing all due and overdue items
- `:Dooing add [text]` - Adds a new task
  - `-p, --priorities [list]` - Comma-separated list of priorities (e.g. "important,urgent")
- `:Dooing list` - Lists all todos with their indices and metadata
- `:Dooing set [index] [field] [value]` - Modifies todo properties
  - `priorities` - Set/update priorities (use "nil" to clear)
  - `ect` - Set estimated completion time (e.g. "30m", "2h", "1d", "0.5w")

---

## 🔑 Keybindings

Dooing comes with intuitive keybindings:

#### Main Window
| Key           | Action                        |
|--------------|------------------------------|
| `<leader>td` | Toggle global todo window    |
| `<leader>tD` | Toggle project todo window   |
| `<leader>tN` | Show due items window        |
| `i`          | Add new todo                 |
| `<leader>tn` | Create nested subtask        |
| `x`          | Toggle todo status           |
| `d`          | Delete current todo          |
| `D`          | Delete all completed todos   |
| `q`          | Close window                 |
| `H`          | Add due date                 |
| `r`          | Remove due date              |
| `T`          | Add time estimation          |
| `R`          | Remove time estimation       |
| `?`          | Toggle help window           |
| `t`          | Toggle tags window           |
| `c`          | Clear active tag filter      |
| `e`          | Edit todo                    |
| `p`          | Edit priorities              |
| `u`          | Undo delete                  |
| `/`          | Search todos                 |
| `I`          | Import todos                 |
| `E`          | Export todos                 |
| `<leader>D`  | Remove duplicates            |
| `<leader>p`  | Open todo scratchpad         |
| `f`          | Refresh todo list            |

#### Tags Window
| Key    | Action        |
|--------|--------------|
| `e`    | Edit tag     |
| `d`    | Delete tag   |
| `<CR>` | Filter by tag|
| `q`    | Close window |

#### Calendar Window
| Key    | Action              |
|--------|-------------------|
| `h`    | Previous day       |
| `l`    | Next day          |
| `k`    | Previous week     |
| `j`    | Next week         |
| `H`    | Previous month    |
| `L`    | Next month        |
| `<CR>` | Select date       |
| `q`    | Close calendar    |

**Calendar Start Day:**

You can configure the start day of the week in the calendar by setting `calendar.start_day` to either `"sunday"` or `"monday"`. Any other value will default to `"sunday"`.

---


## 🔔 Due Date Notifications

Dooing includes smart notifications to keep you aware of upcoming and overdue tasks.

### How it works

- **On Startup**: Automatically checks for due items when Neovim starts
  - Shows project todos if you're in a git repository with a todo file
  - Falls back to global todos otherwise
- **When Opening Todos**: Shows notification when you open global or project todos
- **Due Items Window**: Press `<leader>tN` to see all due items in an interactive window
  - Navigate through items
  - Press `<CR>` to jump to a specific todo

### Notification Format

Notifications appear in red and show:
```
3 items due
```

### Configuration

```lua
due_notifications = {
    enabled = true,        -- Master switch for due notifications
    on_startup = true,    -- Show notification when Neovim starts
    on_open = true,       -- Show notification when opening todo windows
}
```

To disable notifications entirely:
```lua
due_notifications = {
    enabled = false,
}
```

---

## 📥 Backlog

Planned features and improvements for future versions of Dooing:

#### Core Features

- [x] Due Dates Support
- [x] Priority Levels
- [x] Todo Filtering by Tags
- [x] Todo Search
- [x] Todo List Per Project

#### UI Enhancements

- [x] Tag Highlighting
- [ ] Custom Todo Colors
- [ ] Todo Categories View

#### Quality of Life

- [x] Multiple Todo Lists
- [X] Import/Export Features

---

## 📝 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## 🔖 Versioning

We use [Semantic Versioning](https://semver.org/) for versioning. For the available versions, see the [tags on this repository](https://github.com/atiladefreitas/dooing/tags).

---

## 🤝 Contributing

Contributions are welcome! If you'd like to improve Dooing, please read our [Contributing Guide](CONTRIBUTING.md) for detailed information about:

- Setting up the development environment
- Understanding the modular codebase structure
- Adding new features and fixing bugs
- Testing and documentation guidelines
- Submitting pull requests

For quick contributions:
- Submit an issue for bugs or feature requests
- Create a pull request with your enhancements

---

## 🌟 Acknowledgments

Dooing was built with the Neovim community in mind. Special thanks to all the developers who contribute to the Neovim ecosystem and plugins like [Lazy.nvim](https://github.com/folke/lazy.nvim).

---

## All my plugins
| Repository | Description | Stars |
|------------|-------------|-------|
| [LazyClip](https://github.com/atiladefreitas/lazyclip) | A Simple Clipboard Manager | ![Stars](https://img.shields.io/github/stars/atiladefreitas/lazyclip?style=social) |
| [Dooing](https://github.com/atiladefreitas/dooing) | A Minimalist Todo List Manager | ![Stars](https://img.shields.io/github/stars/atiladefreitas/dooing?style=social) |
| [TinyUnit](https://github.com/atiladefreitas/tinyunit) | A Practical CSS Unit Converter | ![Stars](https://img.shields.io/github/stars/atiladefreitas/tinyunit?style=social) |

---

## 📬 Contact

If you have any questions, feel free to reach out:
- [LinkedIn](https://linkedin.com/in/atilafreitas)
- Email: [contact@atiladefreitas.com](mailto:contact@atiladefreitas.com)
