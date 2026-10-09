local file_search = require('blink-cmp-fuzzy-path.file_search')
local config_module = require('blink-cmp-fuzzy-path.config')
local source = require('blink-cmp-fuzzy-path')

describe('blink-cmp-fuzzy-path', function()
  local dir, path_before, cwd

  --- A fake `fd`, first on `$PATH`, printing `lines` and logging each call
  local function fake_fd(lines)
    local out = dir .. '/files.txt'
    vim.fn.writefile(lines, out)
    vim.fn.writefile({
      '#!/bin/sh',
      'echo "$*" >> "' .. dir .. '/calls"',
      'cat "' .. out .. '"',
    }, dir .. '/bin/fd')
    vim.fn.setfperm(dir .. '/bin/fd', 'rwxr-xr-x')
  end

  local function calls()
    return vim.fn.filereadable(dir .. '/calls') == 1
        and vim.fn.readfile(dir .. '/calls')
      or {}
  end

  --- Search `query` and wait for the answer
  local function search(query, opts)
    local config = config_module.setup(opts or {})
    local result
    file_search.search_files_async(
      query,
      config,
      nil,
      function(files) result = files end
    )
    assert.is_true(vim.wait(5000, function() return result ~= nil end))
    return result
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/bin', 'p')
    vim.fn.mkdir(dir .. '/work', 'p')
    path_before = vim.env.PATH
    vim.env.PATH = dir .. '/bin:' .. path_before
    cwd = vim.fn.getcwd()
    vim.cmd.cd(dir .. '/work')
    file_search.invalidate()
  end)
  after_each(function()
    vim.cmd.cd(cwd)
    vim.env.PATH = path_before
    vim.fn.delete(dir, 'rf')
  end)

  it('lists the tree once, then answers from the listing', function()
    fake_fd({ 'lua/util/plugin.lua', 'README.md', './init.lua' })
    assert.same({ 'lua/util/plugin.lua' }, search('plugin'))
    assert.same({ 'init.lua' }, search('init'))
    assert.equal(1, #calls())
  end)

  it('lists again after a write or a change of directory', function()
    fake_fd({ 'a.lua' })
    search('a')
    source.new({})
    vim.api.nvim_exec_autocmds('BufWritePost', {})
    search('a')
    assert.equal(2, #calls())
  end)

  it('stops listing at max_files', function()
    local lines = {}
    for index = 1, 100 do
      lines[index] = ('file%03d.lua'):format(index)
    end
    fake_fd(lines)
    local files
    file_search.list(
      dir .. '/work',
      config_module.setup({ max_files = 10 }),
      function(f, cut) files = { f, cut } end
    )
    assert.is_true(vim.wait(5000, function() return files ~= nil end))
    assert.equal(10, #files[1])
    assert.is_true(files[2])
  end)

  it('answers at the deadline though the tool hangs', function()
    vim.fn.writefile(
      { '#!/bin/sh', 'echo early.lua', 'sleep 10 & sleep 10' },
      dir .. '/bin/fd'
    )
    vim.fn.setfperm(dir .. '/bin/fd', 'rwxr-xr-x')
    local started = vim.uv.hrtime()
    assert.same({ 'early.lua' }, search('early', { timeout = 100 }))
    assert.is_true((vim.uv.hrtime() - started) / 1e6 < 3000)
  end)

  it('keeps the best few, exact and short ones first', function()
    local files = {}
    for index = 1, 2000 do
      files[index] = ('deep/path/number%d/util.lua'):format(index)
    end
    table.insert(files, 'util.lua')
    assert.same({ 'util.lua' }, file_search.best('util.lua', files, 1))
    assert.equal(10, #file_search.best('u', files, 10))
  end)

  it('passes the depth to rg too', function()
    vim.fn.writefile({ '#!/bin/sh', 'true' }, dir .. '/bin/rg')
    vim.fn.setfperm(dir .. '/bin/rg', 'rwxr-xr-x')
    local argv = file_search.command(
      config_module.setup({ search_tool = 'rg', max_depth = 3 })
    )
    assert.same(
      { 'rg', '--files', '--max-depth', '3' },
      vim.list_slice(argv, 1, 4)
    )
  end)

  it('takes the whole path typed, not only its last word', function()
    local query, start = source.query('local x = require("lua/util/pl', 30)
    assert.equal('lua/util/pl', query)
    assert.equal(19, start)
    assert.equal('./src/a', (source.query('see ./src/a', 11)))
  end)

  it('replaces the whole path typed with the file', function()
    fake_fd({ 'lua/util/plugin.lua' })
    local src = source.new({})
    local response
    src:get_completions(
      { line = 'x lua/util/pl', cursor = { 3, 13 } },
      function(r) response = r end
    )
    assert.is_true(vim.wait(5000, function() return response ~= nil end))
    local item = response.items[1]
    assert.equal('lua/util/plugin.lua', item.textEdit.newText)
    assert.same({ line = 2, character = 2 }, item.textEdit.range.start)
    assert.same({ line = 2, character = 13 }, item.textEdit.range['end'])
  end)

  it('searches the directory set_path chose, and back', function()
    vim.fn.mkdir(dir .. '/other', 'p')
    assert.is_true(source.set_path(dir .. '/other'))
    assert.equal(vim.fs.normalize(dir .. '/other'), source.get_path())
    assert.is_false(source.set_path(dir .. '/missing'))
    assert.is_true(source.set_path(nil))
    assert.equal(vim.fs.normalize(dir .. '/work'), source.get_path())
  end)

  it('shows a file outside the working directory from home', function()
    local config = config_module.setup({})
    assert.equal(
      'a.lua',
      file_search.display('a.lua', vim.fs.normalize(vim.fn.getcwd()), config)
    )
    assert.equal(
      vim.fn.fnamemodify(dir .. '/work-other/a.lua', ':~'),
      file_search.display('a.lua', dir .. '/work-other', config)
    )
  end)
end)
