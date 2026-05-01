local M = {}

local fuzzy_match
local ok, blink_fuzzy = pcall(require, 'blink.cmp.fuzzy.lua.match')
if ok then
  fuzzy_match = blink_fuzzy
else
  vim.notify(
    'blink-cmp-fuzzy-path: Cannot load blink.cmp fuzzy matcher',
    vim.log.levels.ERROR
  )
  fuzzy_match = function(needle, haystack)
    if haystack:lower():find(needle:lower(), 1, true) then
      return 1, needle:lower() == haystack:lower()
    end
    return nil
  end
end

local function command_exists(cmd) return vim.fn.executable(cmd) == 1 end

local function make_relative_path(filepath, bufpath, search_base)
  if not bufpath or bufpath == '' then return filepath end

  local base_dir = search_base or vim.fn.getcwd()
  base_dir = vim.fn.expand(base_dir)
  base_dir = vim.fn.fnamemodify(base_dir, ':p')
  if vim.endswith(base_dir, '/') then base_dir = base_dir:sub(1, -2) end

  local buf_dir = vim.fn.fnamemodify(bufpath, ':h')
  local abs_filepath = vim.fn.fnamemodify(filepath, ':p')

  if not vim.startswith(filepath, '/') then
    abs_filepath = vim.fn.fnamemodify(base_dir .. '/' .. filepath, ':p')
  end

  if vim.startswith(abs_filepath, buf_dir) then
    local rel_path = vim.fn.fnamemodify(abs_filepath, ':.')
    return rel_path
  end

  if vim.startswith(abs_filepath, base_dir .. '/') then
    return abs_filepath:sub(#base_dir + 2)
  end

  return vim.fn.fnamemodify(abs_filepath, ':~:.')
end

local function list_all_files_async(config, callback)
  local tool = config.search_tool
  if tool ~= 'fd' and tool ~= 'rg' then
    if command_exists('fd') then
      tool = 'fd'
    elseif command_exists('rg') then
      tool = 'rg'
    else
      vim.notify(
        "blink-cmp-fuzzy-path: Neither 'fd' nor 'rg' found.",
        vim.log.levels.WARN
      )
      callback({})
      return nil
    end
  end

  local args = {}
  local cmd = tool

  if tool == 'fd' then
    args = { '--type', 'f', '-d', tostring(config.max_depth or 20) }
    if config.search_hidden then table.insert(args, '--hidden') end
    if not config.search_gitignore then table.insert(args, '--no-ignore') end
  else
    args = { '--files' }
    if config.search_hidden then table.insert(args, '--hidden') end
    if not config.search_gitignore then table.insert(args, '--no-ignore') end
  end

  local search_path = config.search_dir or vim.fn.getcwd()

  local stdout = vim.loop.new_pipe(false)
  local handle
  local all_files = {}
  local stdout_data = ''

  handle = vim.loop.spawn(
    cmd,
    {
      args = args,
      stdio = { nil, stdout, nil },
      cwd = search_path,
    },
    vim.schedule_wrap(function(code, signal)
      if stdout and not stdout:is_closing() then stdout:close() end
      if handle and not handle:is_closing() then handle:close() end

      if stdout_data ~= '' then
        for line in stdout_data:gmatch('([^\n]+)') do
          if line ~= '' then
            line = line:gsub([[^%./]], '')
            table.insert(all_files, line)
          end
        end
      end

      callback(all_files)
    end)
  )

  if not handle then
    callback({})
    return nil
  end

  stdout:read_start(vim.schedule_wrap(function(err, data)
    if err then
      callback({})
      return
    end
    if data then stdout_data = stdout_data .. data end
  end))

  return function()
    if handle and not handle:is_closing() then handle:close() end
    if stdout and not stdout:is_closing() then stdout:close() end
  end
end

function M.search_files_async(query, config, bufpath, callback)
  if not query or query == '' then
    callback({})
    return nil
  end

  local cancel_fn = list_all_files_async(config, function(all_files)
    local matches = {}

    for _, file in ipairs(all_files) do
      local score, exact = fuzzy_match(query, file)
      if score then
        table.insert(matches, { path = file, score = score, exact = exact })
      end
    end

    table.sort(matches, function(a, b)
      if a.exact and not b.exact then return true end
      if b.exact and not a.exact then return false end
      return a.score > b.score
    end)

    local results = {}
    for i = 1, math.min(#matches, config.max_results) do
      table.insert(results, matches[i].path)
    end

    if config.relative_paths and bufpath then
      local search_base = config.search_dir or vim.fn.getcwd()
      results = vim.tbl_map(
        function(file) return make_relative_path(file, bufpath, search_base) end,
        results
      )
    end

    callback(results)
  end)

  return cancel_fn
end

return M
