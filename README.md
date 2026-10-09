# blink-cmp-fuzzy-path

A Neovim plugin that provides true file path completion for [blink.cmp](https://github.com/saghen/blink.cmp). Uses blink.cmp's built-in fuzzy matcher for intelligent matching across all file paths.

## Features

- 🎯 **True fuzzy matching** - Uses blink.cmp's built-in fuzzy matcher
- 🌍 **Works everywhere** - Active in all filetypes
- 🔍 **Fast search** - Lists the files once with `fd`/`ripgrep`, in the background, then fuzzy matches the listing on each key
- 🧭 **Whole paths** - Matches and replaces the whole path typed (`lua/util/pl`), not only its last word
- 📍 **Relative paths** - Shows paths relative to the working directory
- ⚙️ **Highly configurable** - Customize search depth, results limit, and more
- ⚡ **No external dependencies** - Pure Neovim plugin using blink.cmp's fuzzy engine

## Requirements

- **Neovim** ≥ 0.11.0
- **blink.cmp** - The completion framework (includes fuzzy matcher)
- **fd** or **ripgrep** - For listing files
  - [fd](https://github.com/sharkdp/fd) (recommended)
  - [ripgrep](https://github.com/BurntSushi/ripgrep)
  - Debian's `fdfind` is found as well

## Installation

### Using lazy.nvim

```lua
{
  'dynamotn/blink-cmp-fuzzy-path',
  dependencies = { 'saghen/blink.cmp' },
  opts = {
    max_results = 10,
    max_depth = 20,
  }
}
```

Then register it with blink.cmp:

```lua
{
  'saghen/blink.cmp',
  opts = {
    sources = {
      default = { 'fuzzy-path', 'lsp', 'path', 'snippets', 'buffer' },
      providers = {
        ['fuzzy-path'] = {
          name = 'fuzzy_path',
          module = 'blink-cmp-fuzzy-path',
          score_offset = 0,
        }
      }
    }
  }
}
```

## Configuration

Default configuration:

```lua
{
  max_results = 10,
  max_depth = 20,
  search_tool = "fd",
  search_hidden = false,
  search_gitignore = true,
  relative_paths = true,
  search_dir = nil,
  max_files = 50000,
  timeout = 5000,
  cache_ttl = 30,
  min_query_length = 1,
}
```

### Configuration Options

- `max_results` - Maximum number of fuzzy matches to show (default: 10)
- `max_depth` - Maximum directory depth to search (default: 20)
- `search_tool` - 'fd' or 'rg' for listing files, the other one when it is
  missing (default: 'fd')
- `search_hidden` - Include hidden files (default: false)
- `search_gitignore` - Respect .gitignore (default: true)
- `relative_paths` - Show paths relative to the working directory, else
  absolute ones (default: true)
- `search_dir` - Specific directory to search in (default: nil = use cwd)
- `max_files` - Most files kept of one listing (default: 50000)
- `timeout` - Milliseconds the listing may take (default: 5000)
- `cache_ttl` - Seconds a listing is reused; a write, a new file or a change
  of directory lists again sooner (default: 30)
- `min_query_length` - Characters the path typed needs before files are
  offered (default: 1)

The directory searched can be changed at runtime:

```lua
require('blink-cmp-fuzzy-path').set_path('~/projects/app') -- nil or '' goes back
require('blink-cmp-fuzzy-path').get_path()
```

### Example

```lua
{
  'dynamotn/blink-cmp-fuzzy-path',
  opts = {
    max_results = 15,
    max_depth = 10,
    search_tool = "rg",
    search_hidden = true,
    relative_paths = true,
  }
}
```

## Usage

Simply start typing a filename or path pattern. The plugin will fuzzy match against all file paths in your project.

### Examples

**Fuzzy matching across full paths:**

In any file, type:
```
lbcfp
```

Will match files like:
- `lua/blink-cmp-fuzzy-path/init.lua`
- `lua/blink_cmp_fuzzy_path.lua`

**Partial path patterns:**

Type:
```
src/auth
```

Will fuzzy match:
- `src/auth/login.lua`
- `src/authentication/index.lua`
- `src/lib/auth_helper.lua`

## How It Works

This plugin uses a two-stage approach:

1. **File Discovery**: Uses `fd` or `ripgrep` to list the files in the
   background, with a deadline and at most `max_files`, and keeps the listing
   for `cache_ttl` seconds
2. **Fuzzy Matching**: Matches the whole path typed against the listing with
   blink.cmp's built-in fuzzy matcher, keeping only the best `max_results`
3. **Scoring & Ranking**: Ranks results by fuzzy match score (exact matches,
   prefix matches, delimiter bonuses), shorter paths first on a tie
4. **Path Formatting**: Converts to relative paths (if configured)
5. **Completion**: Shows ranked results in blink.cmp menu, each replacing the
   whole path typed

This approach provides true fuzzy matching across entire file paths using the same high-performance matcher that powers blink.cmp's completions.

## Troubleshooting

### No completions appearing

- **Check fd/rg**: Verify that `fd` or `rg` is installed:
  ```bash
  which fd
  # or
  which rg
  ```

### Slow performance

- Reduce `max_depth` or `max_files` to list less of a large tree
- Raise `min_query_length` to offer files only once a few characters are typed
- Use `fd` instead of `rg` (usually faster for file listing)
- Ensure `.gitignore` is respected (`search_gitignore = true`)

## Development

### Project Structure

```
blink-cmp-fuzzy-path/
├── lua/
│   └── blink-cmp-fuzzy-path/
│       ├── init.lua           # Main source integration
│       ├── config.lua         # Configuration management
│       └── file_search.lua    # File listing + fuzzy matching
├── tests/spec/                # plenary specs: `make test`
└── README.md
```

## License

MIT License

## Acknowledgments

- [blink.cmp](https://github.com/saghen/blink.cmp) for the fuzzy matching engine
- [fd](https://github.com/sharkdp/fd)
- [ripgrep](https://github.com/BurntSushi/ripgrep)
