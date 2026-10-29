local M = {}
local runtime, lsp = require('nodot.runtime'), require('nodot.lsp')
local configured = false
local defaults = { godot = 'godot', lsp_port = 6005, dap_port = 6006, debug_port = 6007, timeout_ms = 15000 }
local function notify(message, level) vim.notify(message, level or vim.log.levels.INFO, { title = 'nodot.nvim' }) end
function M.start(path)
  runtime.start(path, function(err) notify(err or 'Godot is ready', err and vim.log.levels.ERROR) end)
end
function M.stop() lsp.disconnect(); runtime.stop() end
function M.restart(path)
  local root = path or runtime.status().root or runtime.project()
  local reconnect = lsp.status() ~= 'disconnected'
  M.stop()
  runtime.start(root, function(err, ready_root)
    if err then notify(err, vim.log.levels.ERROR)
    elseif reconnect then lsp.connect(ready_root)
    else notify('Godot is ready') end
  end)
end
function M.connect(path)
  local root = runtime.project(path)
  local state = runtime.status()
  if state.root and state.root ~= root then error('Stop the active project before connecting another project') end
  if state.state ~= 'stopped' and state.state ~= 'ready' then error('Wait for Godot to become ready before connecting') end
  return lsp.connect(root)
end
function M.disconnect() lsp.disconnect() end
function M.status()
  local state = runtime.status()
  state.lsp = lsp.status()
  return state
end
function M.logs() runtime.logs() end
function M.setup(options)
  if configured then M.stop() end
  local opts = vim.tbl_deep_extend('force', defaults, options or {})
  assert(type(opts.godot) == 'string', 'godot must be an executable name or path')
  assert(type(opts.timeout_ms) == 'number' and opts.timeout_ms > 0, 'timeout_ms must be positive')
  local seen = {}
  for _, key in ipairs({ 'lsp_port', 'dap_port', 'debug_port' }) do
    local port = opts[key]
    assert(type(port) == 'number' and port % 1 == 0 and port > 0 and port < 65536, key .. ' must be a valid port')
    assert(not seen[port], 'Godot ports must be distinct')
    seen[port] = true
  end
  runtime.setup(opts); lsp.setup(opts); configured = true
  local commands = { 'start', 'stop', 'restart', 'connect', 'disconnect', 'status', 'logs' }
  vim.api.nvim_create_user_command('Nodot', function(args)
    local action = args.args
    if not vim.tbl_contains(commands, action) then notify('Usage: :Nodot ' .. table.concat(commands, '|'), vim.log.levels.ERROR); return end
    local ok, result = pcall(M[action])
    if not ok then notify(result, vim.log.levels.ERROR)
    elseif action == 'status' then notify(vim.inspect(result)) end
  end, { nargs = 1, force = true, complete = function(prefix)
    return vim.tbl_filter(function(command) return vim.startswith(command, prefix) end, commands)
  end })
  local group = vim.api.nvim_create_augroup('nodot', { clear = true })
  vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter' }, { group = group, callback = function(args) lsp.attach(args.buf) end })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = M.stop })
end
return M
