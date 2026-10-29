local M = {}
local opts, client_id, active_root
function M.setup(config) opts = config end
function M.disconnect()
  local client = client_id and vim.lsp.get_client_by_id(client_id)
  if client then client:stop(true) end
  client_id, active_root = nil, nil
end
function M.status()
  local client = client_id and vim.lsp.get_client_by_id(client_id)
  return client and (client.initialized and 'connected' or 'connecting') or 'disconnected'
end
function M.attach(buf)
  if not client_id or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'gdscript' then return end
  local ok, root = pcall(require('nodot.runtime').project, vim.api.nvim_buf_get_name(buf))
  if ok and root == active_root then vim.lsp.buf_attach_client(buf, client_id) end
end
function M.connect(root)
  if active_root and active_root ~= root then error('Disconnect the current LSP before switching projects') end
  M.disconnect()
  active_root = root
  client_id = vim.lsp.start({
    name = 'nodot', root_dir = root,
    cmd = vim.lsp.rpc.connect('127.0.0.1', opts.lsp_port),
    capabilities = opts.capabilities,
    on_attach = opts.on_attach,
  }, { attach = false })
  if not client_id then active_root = nil; error('Failed to create Godot LSP client') end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.attach(buf) end
  end
  return client_id
end
return M
