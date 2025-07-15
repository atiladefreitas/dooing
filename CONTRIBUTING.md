# Contributing to Dooing

Thank you for your interest in contributing to Dooing! This document will guide you through the development process and help you understand the codebase structure.

## 🚀 Getting Started

### Prerequisites

- Neovim >= 0.10.0
- Git
- Basic knowledge of Lua and Neovim plugin development

### Development Setup

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/yourusername/dooing.git
   cd dooing
   ```
3. Create a symlink to your local development version:
   ```bash
   # Option 1: Using Lazy.nvim's dev option
   # Add `dev = true` to your plugin config in Lazy.nvim
   
   # Option 2: Manual symlink
   ln -s /path/to/your/dooing ~/.local/share/nvim/lazy/dooing
   ```

## 📁 Project Structure

Dooing uses a modular architecture where the main functionality is organized into focused modules:

```
dooing/
├── lua/dooing/
│   ├── ui/                 # UI-related modules (NEW STRUCTURE)
│   │   ├── init.lua        # Main UI interface and coordination
│   │   ├── constants.lua   # Shared constants and window IDs
│   │   ├── highlights.lua  # Highlight management and priority colors
│   │   ├── utils.lua       # Utility functions (time, parsing, rendering)
│   │   ├── window.lua      # Main window creation and management
│   │   ├── rendering.lua   # Todo rendering and highlighting logic
│   │   ├── actions.lua     # Todo CRUD operations
│   │   ├── components.lua  # UI components (help, tags, search, scratchpad)
│   │   ├── keymaps.lua     # Keymap setup and management
│   │   └── calendar.lua    # Calendar functionality
│   ├── init.lua            # Main plugin entry point
│   ├── config.lua          # Configuration management
│   ├── state.lua           # State management
│   └── server.lua          # Server functionality
├── plugin/dooing.vim       # Vim plugin bootstrap
└── doc/dooing.txt          # Help documentation
```

## 🏗️ Module Responsibilities

### Core Modules

- **`init.lua`**: Main plugin entry point and setup
- **`config.lua`**: Configuration management and defaults
- **`state.lua`**: Global state management and data persistence
- **`server.lua`**: Server-side functionality and data operations

### UI Modules

- **`ui/init.lua`**: Main UI interface that coordinates all UI modules
- **`ui/constants.lua`**: Shared constants, namespaces, and window IDs
- **`ui/highlights.lua`**: Highlight group management and priority colors
- **`ui/utils.lua`**: Utility functions for time formatting, parsing, and todo rendering
- **`ui/window.lua`**: Main window creation, sizing, and management
- **`ui/rendering.lua`**: Todo rendering logic and highlighting
- **`ui/actions.lua`**: Todo CRUD operations (create, update, delete)
- **`ui/components.lua`**: UI components (help window, tags window, search, scratchpad)
- **`ui/keymaps.lua`**: Keymap setup and management
- **`ui/calendar.lua`**: Calendar functionality for due dates

## 🔧 Development Guidelines

### Adding New Features

1. **Identify the appropriate module**: Determine which module should contain your new feature
2. **UI features**: Add to the appropriate `ui/` module
3. **Core functionality**: Add to the appropriate core module
4. **New UI components**: Consider adding to `ui/components.lua` or create a new module if substantial

### Modifying Existing Features

1. **Locate the feature**: Use the module responsibilities guide above
2. **Update related modules**: Ensure changes are reflected in all dependent modules
3. **Test thoroughly**: Verify the feature works across different scenarios

### Code Style

- Follow standard Lua conventions
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions focused and single-purpose
- Use local variables and functions when possible

### Module Communication

- **Constants**: Use `ui/constants.lua` for shared values
- **State**: Access global state through `state.lua`
- **Configuration**: Access config through `config.lua`
- **Inter-module communication**: Use require() and return public APIs

## 🧪 Testing

### Manual Testing

1. Test your changes with different configurations
2. Verify keymaps work correctly
3. Test with various todo scenarios (empty lists, many todos, etc.)
4. Test window resizing and positioning
5. Verify persistence across Neovim sessions

### Testing Checklist

- [ ] Basic functionality works
- [ ] Keymaps are responsive
- [ ] No Lua errors in `:messages`
- [ ] Configuration changes are respected
- [ ] UI components render correctly
- [ ] Data persistence works
- [ ] Performance is acceptable

## 📝 Documentation

### Code Documentation

- Add comments for complex functions
- Document public APIs
- Update help text when adding new features

### User Documentation

- Update `README.md` for new features
- Update `doc/dooing.txt` for help documentation
- Update keymaps tables when adding new keybindings

## 🔄 Submitting Changes

### Before Submitting

1. **Test thoroughly**: Follow the testing checklist above
2. **Update documentation**: Ensure all documentation is current
3. **Check for conflicts**: Rebase against the latest main branch
4. **Follow commit conventions**: Use clear, descriptive commit messages

### Pull Request Process

1. Create a feature branch from `main`
2. Make your changes following the guidelines above
3. Test your changes thoroughly
4. Update documentation as needed
5. Submit a pull request with:
   - Clear description of changes
   - Testing performed
   - Any breaking changes
   - Screenshots if UI changes are involved

### Pull Request Template

```markdown
## Description
Brief description of changes made.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Manual testing performed
- [ ] No Lua errors
- [ ] All existing features work
- [ ] New features work as expected

## Documentation
- [ ] Updated README.md (if applicable)
- [ ] Updated doc/dooing.txt (if applicable)
- [ ] Updated keymaps documentation (if applicable)
```

## 🐛 Bug Reports

When reporting bugs, please include:

1. **Neovim version**: Output of `:version`
2. **Plugin version**: Git commit hash or version tag
3. **Configuration**: Your dooing configuration
4. **Steps to reproduce**: Clear steps to reproduce the issue
5. **Expected behavior**: What should happen
6. **Actual behavior**: What actually happens
7. **Error messages**: Any error messages from `:messages`

## 💡 Feature Requests

When requesting features:

1. **Use case**: Describe why this feature would be useful
2. **Proposed solution**: How you envision the feature working
3. **Alternatives**: Any alternative solutions you've considered
4. **Implementation hints**: If you have ideas about implementation

## 🔍 Code Review

All contributions go through code review. Reviewers will check for:

- Code quality and style
- Proper module organization
- Testing completeness
- Documentation updates
- Backward compatibility

## 📞 Getting Help

If you need help:

1. Check existing issues on GitHub
2. Read the documentation in `doc/dooing.txt`
3. Create a discussion on GitHub
4. Join the community discussions

## 🎯 Development Priorities

Current focus areas:

1. **Performance improvements**: Optimizing rendering and state management
2. **UI enhancements**: Improving user experience and visual design
3. **Feature completeness**: Implementing planned features from the backlog
4. **Code quality**: Improving maintainability and test coverage

Thank you for contributing to Dooing! Your efforts help make this plugin better for everyone. 