local M = {}

-- Default configuration
M.defaults = {
  max_results = 10,
  max_depth = 20,
  search_tool = 'fd',
  search_hidden = false,
  search_gitignore = true,
  relative_paths = true,
  search_dir = nil,
  -- Files kept of one listing; the rest of a huge tree is left out
  max_files = 50000,
  -- Milliseconds the listing may take
  timeout = 5000,
  -- Seconds a listing is reused before the tree is read again; a write, a
  -- new file or a change of directory reads it again sooner
  cache_ttl = 30,
  -- Characters the path being typed needs before files are offered
  min_query_length = 1,
}

local function positive(name, value)
  if value < 1 then error(name .. ' must be at least 1') end
end

-- Validate configuration
local function validate_config(config)
  vim.validate('max_results', config.max_results, 'number')
  vim.validate('max_depth', config.max_depth, 'number')
  vim.validate('search_tool', config.search_tool, 'string')
  vim.validate('search_hidden', config.search_hidden, 'boolean')
  vim.validate('search_gitignore', config.search_gitignore, 'boolean')
  vim.validate('relative_paths', config.relative_paths, 'boolean')
  vim.validate('search_dir', config.search_dir, 'string', true)
  vim.validate('max_files', config.max_files, 'number')
  vim.validate('timeout', config.timeout, 'number')
  vim.validate('cache_ttl', config.cache_ttl, 'number')
  vim.validate('min_query_length', config.min_query_length, 'number')

  if config.search_tool ~= 'fd' and config.search_tool ~= 'rg' then
    error("search_tool must be 'fd' or 'rg'")
  end
  positive('max_results', config.max_results)
  positive('max_depth', config.max_depth)
  positive('max_files', config.max_files)
  positive('timeout', config.timeout)

  if config.search_dir ~= nil and config.search_dir ~= '' then
    local abs_path = vim.fn.fnamemodify(vim.fn.expand(config.search_dir), ':p')
    if vim.fn.isdirectory(abs_path) ~= 1 then
      error(
        string.format(
          "search_dir '%s' is not a valid directory",
          config.search_dir
        )
      )
    end
    -- Normalize to an absolute path, without the trailing separator
    config.search_dir = vim.fs.normalize(abs_path)
  end
end

-- Merge user config with defaults
function M.setup(user_config)
  local config = vim.tbl_deep_extend('force', M.defaults, user_config or {})
  validate_config(config)
  return config
end

return M
