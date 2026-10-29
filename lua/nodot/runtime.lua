local M = {}
local uv = vim.uv
local opts, job, root, generation = {}, nil, nil, 0
local phase, lines = 'stopped', {}

local function log(message)
  lines[#lines + 1] = message
  if #lines > 1000 then table.remove(lines, 1) end
end

function M.setup(config) opts = config end

function M.project(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if path == '' then path = uv.cwd() end
  local found = vim.fs.root(path, 'project.godot')
  if not found then error('No project.godot found above ' .. path) end
  return uv.fs_realpath(found) or found
end

-- A TCP probe only establishes availability, not server identity.
local function probe(port, callback)
  local socket, timer = uv.new_tcp(), uv.new_timer()
  local done = false
  local function finish(open)
    if done then return end
    done = true
    timer:stop()
    timer:close()
    socket:close()
    vim.schedule(function() callback(open) end)
  end
  timer:start(300, 0, function() finish(false) end)
  socket:connect('127.0.0.1', port, function(err) finish(not err) end)
end

function M.status()
  return { state = phase, root = root, owned = job ~= nil, job = job, lsp_port = opts.lsp_port }
end

function M.stop()
  generation = generation + 1
  if job then
    phase = 'stopping'
    local id = job
    vim.fn.jobstop(id)
    if vim.fn.jobwait({ id }, 3000)[1] == -1 then
      error('Godot is still stopping; try again before starting another instance')
    end
    job = nil
  end
  phase, root = 'stopped', nil
end

function M.start(path, callback)
  callback = callback or function() end
  local target = M.project(path)
  if root and root ~= target then error('Stop the active project before switching projects') end
  if phase == 'ready' then callback(nil, root); return end
  if phase ~= 'stopped' then error('Godot is ' .. phase .. '; wait or stop it first') end
  if vim.fn.executable(opts.godot) ~= 1 then error('Godot executable not found: ' .. opts.godot) end
  generation = generation + 1
  local token = generation
  root, phase = target, 'checking'
  local ports = { opts.lsp_port, opts.dap_port, opts.debug_port }
  local function fail(message)
    if generation ~= token then return end
    M.stop()
    log(message)
    callback(message)
  end
  local function launch()
    phase = 'starting'
    log('Starting Godot in ' .. target)
    local id
    id = vim.fn.jobstart({ opts.godot, '--headless', '--editor', '--path', target,
      '--lsp-port', tostring(opts.lsp_port), '--dap-port', tostring(opts.dap_port),
      '--debug-server', 'tcp://127.0.0.1:' .. opts.debug_port }, {
      cwd = target,
      on_stdout = function(_, data) for _, line in ipairs(data) do if line ~= '' then log(line) end end end,
      on_stderr = function(_, data) for _, line in ipairs(data) do if line ~= '' then log(line) end end end,
      on_exit = function(_, code)
        if generation ~= token then return end
        job = nil
        local starting = phase == 'starting'
        phase, root = 'stopped', nil
        log('Godot exited with code ' .. code)
        if starting then callback('Godot exited before readiness; see :Nodot logs') end
      end,
    })
    if id <= 0 then fail('Could not start Godot'); return end
    job = id
    local deadline = uv.hrtime() + opts.timeout_ms * 1e6
    local function poll()
      if generation ~= token or phase ~= 'starting' then return end
      probe(opts.lsp_port, function(open)
        if generation ~= token or phase ~= 'starting' then return end
        if open then
          phase = 'ready'
          callback(nil, target)
        elseif uv.hrtime() >= deadline then
          fail('Timed out waiting for Godot LSP; see :Nodot logs')
        else
          vim.defer_fn(poll, 100)
        end
      end)
    end
    poll()
  end
  local function check(index)
    if generation ~= token then return end
    if not ports[index] then launch(); return end
    probe(ports[index], function(open)
      if generation ~= token then return end
      if open then
        fail('Port ' .. ports[index] .. ' is occupied. Use :Nodot connect for an existing Godot LSP, or choose different ports.')
      else check(index + 1) end
    end)
  end
  check(1)
end

function M.logs()
  vim.cmd('botright new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'nofile', 'wipe', false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { 'No Godot output yet.' })
  vim.bo[buf].modifiable = false
end

return M
