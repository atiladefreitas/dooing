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

---

## 📦 Installation

### Prerequisites

- Neovim `>= 0.10.0`
- [Lazy.nvim](https://github.com/folke/lazy.nvim) as your plugin manager

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
    save_path = vim.fn.stdpath('data') .. '/dooing_todos.json',

	confirm_when_delete = true, -- ask for confirmation when deleting a todo
    
    -- Window appearance
    window = {
        width = 40,         -- Width of the floating window
        height = 20,        -- Height of the floating window
        border = 'rounded', -- Border style
    },
    
    -- Icons
    icons = {
        pending = '○',      -- Pending todo icon
        done = '✓',        -- Completed todo icon
        calendar = "",    -- due date todo icon
    },
    
    -- Keymaps
    keymaps = {
        toggle_window = "<leader>td", -- Toggle the main window
        new_todo = "i",              -- Add a new todo
        toggle_todo = "x",           -- Toggle todo status
        delete_todo = "d",           -- Delete the current todo
        delete_completed = "D",      -- Delete all completed todos
        close_window = "q",          -- Close the window
        add_due_date = "h",          -- Add due date to todo
        remove_due_date = "r",       -- Remove due date from todo
        toggle_help = "?",           -- Toggle help window
        toggle_tags = "t",           -- Toggle tags window
        clear_filter = "c",          -- Clear active tag filter
        edit_todo = "e",             -- Edit todo item
        edit_tag = "e",              -- Edit tag [on tag window]
        delete_tag = "d",            -- Delete tag [on tag window]
        search_todo = "/",           -- Toggle todo searching
        toggle_priority = "<Space>"  -- Toggle todo priority on creation
    },

    prioritization = false,
	priorities = {                   -- Defines priorities one can assign to tasks
		{
			name = "important",
			weight = 4,              -- Weight of each priority. E.g. here, `important` is ranked higher than `urgent`.
		},
		{
			name = "urgent",
			weight = 2,
		},
	},
	priority_thresholds = {
		{
			min = 5, -- Corresponds to `urgent` and `important` tasks
			max = 999,
			color = nil,
			hl_group = "DiagnosticError",
		},
		{
			min = 3, -- Corresponds to `important` tasks
			max = 4,
			color = nil,
			hl_group = "DiagnosticWarn",
		},
		{
			min = 1, -- Corresponds to `urgent tasks`
			max = 2,
			color = nil,
			hl_group = "DiagnosticInfo",
		},
	},

    -- Calendar settings
    calendar = {
        language = "en",             -- Calendar language ("en" or "pt")
        keymaps = {
            previous_day = "h",      -- Move to previous day
            next_day = "l",          -- Move to next day
            previous_week = "k",     -- Move to previous week
            next_week = "j",         -- Move to next week
            previous_month = "H",    -- Move to previous month
            next_month = "L",        -- Move to next month
            select_day = "<CR>",     -- Select the current day
            close_calendar = "q",    -- Close the calendar
        },
    },
}
```

## Commands

Dooing can be controlled through user commands:

- `:Dooing` opens the main window,
- `:Dooing add Your Simple Task`, adds a task.
- `:Dooing -p important,urgent Your Important and Urgent task`, assigns priority to it.

---

## 🔑 Keybindings

Dooing comes with intuitive keybindings:

#### Main Window
| Key           | Action                      |
|--------------|----------------------------|
| `<leader>td` | Toggle todo window         |
| `i`          | Add new todo               |
| `x`          | Toggle todo status         |
| `d`          | Delete current todo        |
| `D`          | Delete all completed todos |
| `h`          | Add due date               |
| `r`          | Remove due date            |
| `q`          | Close window               |
| `?`          | Toggle help window         |
| `t`          | Toggle tags window         |
| `c`          | Clear active tag filter    |
| `e`          | Edit todo                  |
| `/`          | Toggle todo searching      |

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

---

## 📥 Backlog

Planned features and improvements for future versions of Dooing:

#### Core Features

- [x] Due Dates Support
- [x] Priority Levels
- [x] Todo Filtering by Tags
- [x] Todo Search
- [ ] Todo List Per Project

#### UI Enhancements

- [x] Tag Highlighting
- [ ] Custom Todo Colors
- [ ] Todo Categories View

#### Quality of Life

- [ ] Multiple Todo Lists
- [ ] Import/Export Features

---

## 📝 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## 🔖 Versioning

We use [Semantic Versioning](https://semver.org/) for versioning. For the available versions, see the [tags on this repository](https://github.com/atiladefreitas/dooing/tags).

---

## 🤝 Contributing

Contributions are welcome! If you'd like to improve Dooing, feel free to:

- Submit an issue for bugs or feature requests
- Create a pull request with your enhancements

---

## 🌟 Acknowledgments

Dooing was built with the Neovim community in mind. Special thanks to all the developers who contribute to the Neovim ecosystem and plugins like [Lazy.nvim](https://github.com/folke/lazy.nvim).

---

## 📬 Contact

If you have any questions, feel free to reach out:
- [LinkedIn](https://linkedin.com/in/atilafreitas)
- Email: [contact@atiladefreitas.com](mailto:contact@atiladefreitas.com)
