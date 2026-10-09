local config_module = require('blink-cmp-fuzzy-path.config')
local file_search = require('blink-cmp-fuzzy-path.file_search')

--- The directory `set_path` chose, for every source; nil for the working
--- directory or `search_dir`
---@type string?
local shared_search_dir = nil

local Source = {}
Source.__index = Source

--- A new file, a write or another working directory changes the files to
--- offer: the listing is read again on the next completion
local function watch()
  local group =
    vim.api.nvim_create_augroup('blink-cmp-fuzzy-path', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufNewFile', 'DirChanged' }, {
    group = group,
    callback = function() file_search.invalidate() end,
  })
end

function Source:new(opts)
  local self =
    setmetatable({ config = config_module.setup(opts or {}) }, Source)
  watch()
  return self
end

function Source:enabled() return true end

function Source:get_trigger_characters() return {} end

--- The path being typed: everything back to a space, a quote or a bracket,
--- not only the keyword, which stops at `/` and `.`
---@param line string
---@param col integer Bytes before the cursor
---@return string query
---@return integer start 0-based byte column it starts at
function Source.query(line, col)
  local before = line:sub(1, col)
  local query = before:match('[^%s"\'`(){}%[%]<>=,;|]+$') or ''
  return query, col - #query
end

function Source:get_completions(ctx, callback)
  local line = ctx.line or ''
  local col = ctx.cursor and ctx.cursor[2] or #line
  local query, start = Source.query(line, col)

  if #query < self.config.min_query_length then
    callback({ items = {} })
    return function() end
  end

  local config = vim.tbl_extend('force', self.config, {})
  if shared_search_dir ~= nil then config.search_dir = shared_search_dir end

  local row = (ctx.cursor and ctx.cursor[1] or 1) - 1
  return file_search.search_files_async(query, config, nil, function(files)
    local items = {}
    for index, file in ipairs(files) do
      table.insert(items, {
        label = file,
        kind = vim.lsp.protocol.CompletionItemKind.File,
        filterText = file,
        sortText = string.format('%04d', index),
        score_offset = 5,
        -- Over the whole path typed, which the keyword alone does not cover
        textEdit = {
          newText = file,
          range = {
            start = { line = row, character = start },
            ['end'] = { line = row, character = col },
          },
        },
      })
    end

    callback({
      items = items,
      is_incomplete_forward = true,
      is_incomplete_backward = true,
    })
  end)
end

--- Search `path` from now on, instead of the working directory; nil or ''
--- goes back to it
---@param path? string
---@return boolean
local function set_path(path)
  if not path or path == '' then
    shared_search_dir = nil
    return true
  end

  local abs_path =
    vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ':p'))
  if vim.fn.isdirectory(abs_path) ~= 1 then
    vim.notify(
      string.format("fuzzy-path: '%s' is not a valid directory", path),
      vim.log.levels.ERROR
    )
    return false
  end

  shared_search_dir = abs_path
  vim.notify(
    string.format("fuzzy-path: Search directory set to '%s'", abs_path),
    vim.log.levels.INFO
  )
  return true
end

--- The directory searched
---@return string
local function get_path()
  return shared_search_dir or vim.fs.normalize(vim.fn.getcwd())
end

function Source:set_path(path) return set_path(path) end

function Source:get_path()
  return shared_search_dir or self.config.search_dir or get_path()
end

return {
  new = function(opts) return Source:new(opts) end,
  setup = function(opts) return Source:new(opts) end,
  set_path = set_path,
  get_path = get_path,
  query = Source.query,
}
