local config_module = require('blink-cmp-fuzzy-path.config')
local file_search = require('blink-cmp-fuzzy-path.file_search')

local _global_source = nil
local _shared_search_dir = nil

local Source = {}
Source.__index = Source

function Source:new(opts)
  opts = opts or {}
  local config = config_module.setup(opts)

  local self = setmetatable({
    config = config,
  }, Source)

  return self
end

function Source:enabled() return true end

function Source:get_trigger_characters() return {} end

function Source:get_completions(ctx, callback)
  local line = ctx.line or ''

  local query
  if ctx.bounds and ctx.bounds.length > 0 then
    query = line:sub(
      ctx.bounds.start_col,
      ctx.bounds.start_col + ctx.bounds.length - 1
    )
  elseif vim.api.nvim_get_mode().mode == 'c' then
    local cursor_col = ctx.cursor and ctx.cursor[2] or #line
    local before_cursor = line:sub(1, cursor_col)
    local parts = vim.split(before_cursor, '%s+', { trimempty = true })
    query = parts[#parts] or ''
  else
    local cursor_col = ctx.cursor and ctx.cursor[2] or (ctx.col or #line + 1)
    query = line:sub(1, cursor_col):match('(%S+)$') or ''
  end

  if query == '' then
    callback({ items = {} })
    return
  end

  local bufpath = vim.api.nvim_buf_get_name(ctx.bufnr or 0)

  local config = vim.tbl_extend('force', self.config, {})
  if _shared_search_dir ~= nil then config.search_dir = _shared_search_dir end

  local cancel_fn = file_search.search_files_async(
    query,
    config,
    bufpath,
    function(files)
      local items = {}
      for index, file in ipairs(files) do
        table.insert(items, {
          label = file,
          kind = vim.lsp.protocol.CompletionItemKind.File,
          insertText = file,
          filterText = file,
          sortText = string.format('%04d', index),
          score_offset = 5,
        })
      end

      callback({
        items = items,
        is_incomplete_forward = true,
        is_incomplete_backward = true,
      })
    end
  )

  return cancel_fn
end

function Source:set_path(path)
  if not path or path == '' then
    _shared_search_dir = nil
    self.config.search_dir = nil
    return true
  end

  local expanded_path = vim.fn.expand(path)
  local abs_path = vim.fn.fnamemodify(expanded_path, ':p')

  if vim.fn.isdirectory(abs_path) ~= 1 then
    vim.notify(
      string.format("fuzzy-path: '%s' is not a valid directory", path),
      vim.log.levels.ERROR
    )
    return false
  end

  _shared_search_dir = abs_path
  self.config.search_dir = abs_path

  vim.notify(
    string.format("fuzzy-path: Search directory set to '%s'", abs_path),
    vim.log.levels.INFO
  )

  return true
end

function Source:get_path()
  return _shared_search_dir or self.config.search_dir or vim.fn.getcwd()
end

local function set_path(path)
  if not _global_source then
    vim.notify(
      'fuzzy-path: Plugin not initialized. Call setup() first.',
      vim.log.levels.ERROR
    )
    return false
  end
  return _global_source:set_path(path)
end

local function get_path() return _shared_search_dir or vim.fn.getcwd() end

return {
  new = function(opts) return Source:new(opts) end,
  setup = function(opts) return Source:new(opts) end,
  set_path = set_path,
  get_path = get_path,
}
