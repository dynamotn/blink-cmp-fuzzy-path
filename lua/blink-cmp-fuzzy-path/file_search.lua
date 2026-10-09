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

---@class blink-cmp-fuzzy-path.Listing
---@field files string[] Relative to the root, as the tool printed them
---@field time integer `os.time()` the listing finished
---@field cut boolean Stopped at `max_files`
---@field done boolean The listing has answered
---@field waiting fun(files: string[])[] Called once it is done

--- Listings by root and by the options that shape them
---@type table<string, blink-cmp-fuzzy-path.Listing>
M.listings = {}

--- Forget every listing, so the next completion reads the tree again
function M.invalidate() M.listings = {} end

--- The listing command, `fd` (or Debian's `fdfind`) or `rg`, as configured
--- when it is installed and the other one otherwise
---@param config table
---@return string[]? argv
function M.command(config)
  local tools = config.search_tool == 'rg' and { 'rg', 'fd', 'fdfind' }
    or { 'fd', 'fdfind', 'rg' }
  for _, tool in ipairs(tools) do
    if vim.fn.executable(tool) == 1 then
      local argv = { tool }
      if tool == 'rg' then
        vim.list_extend(argv, {
          '--files',
          '--max-depth',
          tostring(config.max_depth),
        })
      else
        vim.list_extend(argv, {
          '--type',
          'f',
          '--max-depth',
          tostring(config.max_depth),
        })
      end
      if config.search_hidden then table.insert(argv, '--hidden') end
      if not config.search_gitignore then table.insert(argv, '--no-ignore') end
      return argv
    end
  end
  return nil
end

--- List the files under `root` in the background, at most `max_files`, and
--- hand them to `on_done` on the main loop; a failed or timed-out listing
--- hands over what it read before
---@param root string
---@param config table
---@param on_done fun(files: string[], cut: boolean)
---@return vim.SystemObj?
function M.list(root, config, on_done)
  local argv = M.command(config)
  if not argv then
    vim.notify(
      "blink-cmp-fuzzy-path: Neither 'fd' nor 'rg' found.",
      vim.log.levels.WARN
    )
    vim.schedule(function() on_done({}, false) end)
    return nil
  end

  local files, partial, cut, answered = {}, '', false, false
  ---@type vim.SystemObj?
  local process
  local function answer()
    if answered then return end
    answered = true
    vim.schedule(function() on_done(files, cut) end)
  end
  local started_ok, started = pcall(vim.system, argv, {
    cwd = root,
    text = true,
    timeout = config.timeout,
    stdout = function(_, data)
      if not data or cut then return end
      -- Lines are taken as they come: the output of a large tree is never
      -- held whole, and the listing stops at `max_files`
      local text = partial .. data
      local last = 1
      for line, next_at in text:gmatch('([^\n]*)\n()') do
        last = next_at
        if line ~= '' then
          table.insert(files, (line:gsub('^%./', '')))
          if #files >= config.max_files then
            cut = true
            if process then pcall(process.kill, process, 'sigterm') end
            return
          end
        end
      end
      partial = text:sub(last)
    end,
  }, function() answer() end)
  if not started_ok then
    vim.schedule(function() on_done({}, false) end)
    return nil
  end
  process = started
  -- The exit is only reported once the output closes, and something the
  -- tool started can hold it open past the deadline: give up on it then
  local guard = assert(vim.uv.new_timer())
  guard:start(config.timeout + 1000, 0, function()
    guard:close()
    if not answered then
      pcall(started.kill, started, 'sigkill')
      answer()
    end
  end)
  return process
end

--- Hand `on_done` the files under `root`: from the listing kept while it
--- is younger than `cache_ttl`, else from a new one, which every request
--- made meanwhile waits for
---@param root string
---@param config table
---@param on_done fun(files: string[])
function M.files(root, config, on_done)
  local key = table.concat({
    root,
    config.search_tool,
    config.max_depth,
    tostring(config.search_hidden),
    tostring(config.search_gitignore),
    config.max_files,
  }, '\0')
  local listing = M.listings[key]
  if listing and not listing.done then
    return table.insert(listing.waiting, on_done)
  end
  if listing and os.time() - listing.time < config.cache_ttl then
    return on_done(listing.files)
  end

  listing =
    { files = {}, time = 0, cut = false, done = false, waiting = { on_done } }
  M.listings[key] = listing
  M.list(root, config, function(files, cut)
    -- Forgotten meanwhile: the answer still goes to whoever waited for it
    listing.files, listing.cut, listing.time = files, cut, os.time()
    listing.done = true
    local waiting = listing.waiting
    listing.waiting = {}
    for _, callback in ipairs(waiting) do
      callback(files)
    end
  end)
end

--- The `limit` best matches of `query` among `files`, best first
---
--- Kept in a short sorted list as they are found: a short query matches
--- nearly every file of a large tree, and sorting all of them on every key
--- is what held the editor up.
---@param query string
---@param files string[]
---@param limit integer
---@return string[]
function M.best(query, files, limit)
  ---@type { path: string, score: number, exact: boolean }[]
  local best = {}
  local function better(a, b)
    if a.exact ~= b.exact then return a.exact end
    if a.score ~= b.score then return a.score > b.score end
    return #a.path < #b.path
  end
  for _, file in ipairs(files) do
    local score, exact = fuzzy_match(query, file)
    if score then
      local entry = { path = file, score = score, exact = exact == true }
      if #best < limit or better(entry, best[#best]) then
        local at = #best + 1
        while at > 1 and better(entry, best[at - 1]) do
          at = at - 1
        end
        table.insert(best, at, entry)
        if #best > limit then table.remove(best) end
      end
    end
  end
  return vim.tbl_map(function(entry) return entry.path end, best)
end

--- `file`, listed relative to `root`, as it is inserted: relative to the
--- working directory when it is under it, else from the home directory
---@param file string
---@param root string
---@param config table
---@return string
function M.display(file, root, config)
  local path = vim.fs.joinpath(root, file)
  if not config.relative_paths then return path end
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  if root == cwd then return file end
  -- With the separator: `/x/proj` does not hold `/x/proj-other`
  if vim.startswith(path, cwd .. '/') then return path:sub(#cwd + 2) end
  return vim.fn.fnamemodify(path, ':~')
end

--- Search the files under the configured directory, or the working one,
--- for `query`, and hand the best of them to `callback` on the main loop
---@param query string
---@param config table
---@param callback fun(files: string[])
---@return fun() cancel Drops the answer; the listing itself carries on, for
--- the next request to use
function M.search_files_async(query, config, _, callback)
  if not query or query == '' then
    callback({})
    return function() end
  end
  local root = config.search_dir or vim.fs.normalize(vim.fn.getcwd())
  local cancelled = false
  M.files(root, config, function(files)
    if cancelled then return end
    local results = M.best(query, files, config.max_results)
    callback(
      vim.tbl_map(
        function(file) return M.display(file, root, config) end,
        results
      )
    )
  end)
  return function() cancelled = true end
end

return M
