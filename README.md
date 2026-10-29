# nodot.nvim

A small Neovim-first Godot companion: manage a headless editor and connect
Neovim to its GDScript language server.

First pass: one active project per Neovim instance, explicit commands, no
DAP integration or game launching yet. Requires Neovim 0.11+ and a Godot 4
editor supporting `--lsp-port`, `--dap-port`, and `--debug-server`.

## Installation with lazy.nvim

```lua
{
  "VoidAlone/nodot.nvim",
  lazy = false,
  opts = {},
}
```

For local development, replace `"VoidAlone/nodot.nvim"` with
`dir = "/path/to/nodot.nvim"` in the spec above.

Alternatively, add the repository to your runtime path and call
`require("nodot").setup({})`.
Disable your existing automatic Godot LSP configuration before using nodot's
connection commands to avoid duplicate clients. Setup does not launch Godot.

## Commands

Open a file inside a Godot project, run `:Nodot start`, wait for the ready
notification, then run `:Nodot connect`.

| Command | Behavior |
| --- | --- |
| `:Nodot start` | Start headless Godot; reuse the plugin's running process. |
| `:Nodot stop` | Disconnect nodot's LSP and stop only its own Godot process. |
| `:Nodot restart` | Stop/start the managed process; reconnect if previously connected. |
| `:Nodot connect` | Connect/reconnect to the configured localhost LSP port. |
| `:Nodot disconnect` | Disconnect nodot's LSP, leaving Godot running. |
| `:Nodot status` | Show process state, ownership, project, port, and LSP state. |
| `:Nodot logs` | Open a snapshot of recent Godot output (up to 1,000 chunks). |

Project discovery walks upward from the current file to `project.godot`.
An unnamed buffer uses the working directory. There is no `.git` fallback.
Stop the active project before switching projects. Godot stays alive until
stop or Neovim exit. Startup is asynchronous and can be cancelled by stop.

`connect` can use an externally started Godot editor. Ensure that editor has
opened the same project and uses the configured port: TCP availability alone
cannot verify identity. External processes are never terminated by nodot.
Start refuses occupied service ports rather than adopting an unknown process;
restart cannot restart external Godot instances.

Readiness means the LSP TCP port accepts connections. LSP status reports
`connected` only after initialization. Only GDScript buffers in the selected
project are attached. Godot may write its normal `.godot` cache when started.

## Configuration

```lua
require("nodot").setup({
  godot = "godot", -- executable name or absolute path
  lsp_port = 6005,
  dap_port = 6006,
  debug_port = 6007,
  timeout_ms = 15000,
  -- capabilities = require("cmp_nvim_lsp").default_capabilities(),
  -- on_attach = function(client, bufnr) end,
})
```

All ports must be distinct. DAP and runtime-debugger ports are reserved for
the headless editor; this version does not configure nvim-dap. Use different
ports when another editor or Neovim instance occupies them.

Lua API: `start(path?)`, `stop()`, `restart(path?)`, `connect(path?)`,
`disconnect()`, `status()`, and `logs()`. Optional paths select the project;
`status()` returns a table without a notification. Call setup first.

## Integration test

From the repository root:

```sh
nvim --headless -u NONE -l tests/integration.lua
```

Requires Godot and free localhost ports 16005–16007. Creates and removes a
temporary project, checks lifecycle operations and real LSP initialization,
and verifies cancellation and occupied-port refusal.
