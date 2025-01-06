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
    save_path = vim.fn.stdpath("data") .. "/dooing_todos.json",

    -- Window settings
    window = {
        width = 55,         -- Width of the floating window
        height = 20,        -- Height of the floating window
        border = 'rounded', -- Border style
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
    
    -- Keymaps
    keymaps = {
        toggle_window = "<leader>td",
        new_todo = "i",
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
    },

    calendar = {
        language = "en",
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
}
```

## Commands

Dooing provides several commands for task management:

- `:Dooing` - Opens the main window
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
| `<leader>td` | Toggle todo window           |
| `i`          | Add new todo                 |
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
| `<Space>`    | Toggle priority              |
| `<leader>p`  | Open todo scratchpad         |

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
- [X] Import/Export Features

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
