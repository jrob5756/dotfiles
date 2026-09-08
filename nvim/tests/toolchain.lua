package.path = "nvim/lua/?.lua;" .. package.path

local environment
local notifications

vim.v = { shell_error = 0, count1 = 1 }
vim.fn.exepath = function(command) return environment.paths[command] or "" end
vim.fn.executable = function(command) return (environment.paths[command] or environment.executables[command]) and 1 or 0 end
vim.fn.has = function(feature) return feature == "win32" and environment.windows and 1 or 0 end
vim.fn.system = function(command)
  if command[1] == "dotnet" then
    vim.v.shell_error = environment.sdk_error and 1 or 0
    return environment.sdk and "10.0.100 [SDK path]" or ""
  end
  assert(command[2] == "-c" and command[3] == "import debugpy", "Unexpected external command")
  vim.v.shell_error = environment.debugpy and 0 or 1
  return ""
end
vim.notify = function(message) table.insert(notifications, message) end

package.loaded.astrocore = {
  list_insert_unique = function(existing, additions)
    local result = vim.deepcopy(existing)
    for _, value in ipairs(additions) do
      if not vim.tbl_contains(result, value) then table.insert(result, value) end
    end
    return result
  end,
}
package.loaded["mason.settings"] = { current = { install_root_dir = "/mock/mason" } }
package.loaded["astronvim.plugins.configs.nvim-dap"] = function() end

local function reset(overrides)
  environment = vim.tbl_extend("force", {
    paths = {},
    executables = {},
    sdk = false,
    windows = false,
    debugpy = false,
  }, overrides or {})
  vim.env.DOTFILES_NIX = environment.nix and "1" or nil
  vim.env.VIRTUAL_ENV = environment.virtual_env
  vim.env.CONDA_PREFIX = environment.conda_prefix
  notifications = {}
  package.loaded.toolchain = assert(loadfile "nvim/lua/toolchain.lua")()
  package.loaded.dap = { adapters = {}, configurations = {} }
end

local function spec(file, name)
  for _, plugin in ipairs(assert(loadfile("nvim/lua/plugins/" .. file .. ".lua"))()) do
    if plugin[1] == name then return plugin end
  end
  error("Missing plugin: " .. name)
end

local function mason_options(ensure_installed)
  local opts = { ensure_installed = ensure_installed or { "basedpyright", "ruff", "debugpy" } }
  spec("mason", "WhoIsSethDaniel/mason-tool-installer.nvim").opts(nil, opts)
  return opts
end

reset { nix = true }
local opts = mason_options()
assert(#opts.ensure_installed == 0 and opts.run_on_start == false and opts.auto_update == false)
assert(spec("mason", "mason-org/mason.nvim").opts.PATH == "skip")
opts = { ensure_installed = { "basedpyright" } }
spec("mason", "mason-org/mason-lspconfig.nvim").opts(nil, opts)
assert(#opts.ensure_installed == 0 and opts.automatic_enable == false)
opts = { ensure_installed = { "python" }, handlers = { python = function() error "Old Mason adapter enabled" end } }
spec("mason", "jay-babu/mason-nvim-dap.nvim").opts(nil, opts)
assert(#opts.ensure_installed == 0 and opts.automatic_installation == false and opts.handlers == nil)
opts = { ensure_installed = { "stylua" }, handlers = { selene = function() error "Old Mason linter enabled" end } }
spec("mason", "jay-babu/mason-null-ls.nvim").opts(nil, opts)
assert(#opts.ensure_installed == 0 and opts.automatic_installation == false and opts.handlers == nil)
opts = {}
spec("mason", "AstroNvim/astrolsp").opts(nil, opts)
assert(#opts.servers == 0 and opts.handlers.csharp_ls == false)
spec("dotnet", "mfussenegger/nvim-dap").config()
assert(package.loaded.dap.adapters.coreclr == nil, "Missing Nix debugger must not fall back to Mason")

reset()
opts = mason_options()
for _, name in ipairs { "basedpyright", "ruff", "debugpy", "lua-language-server", "stylua", "tree-sitter-cli" } do
  assert(vim.tbl_contains(opts.ensure_installed, name), "Missing manual install: " .. name)
end
assert(not vim.tbl_contains(opts.ensure_installed, "csharp-language-server"))
assert(not vim.tbl_contains(opts.ensure_installed, "csharpier"))
assert(spec("mason", "mason-org/mason.nvim").opts.PATH == "append")
local check_sdk = spec("dotnet", "AstroNvim/astrocore").opts.autocmds.dotnet_sdk_check[1]
assert(check_sdk.pattern == "cs" and check_sdk.once)
check_sdk.callback()
assert(#notifications == 1 and notifications[1]:find("SDK", 1, true))

reset { sdk = true, paths = { dotnet = "/mock/dotnet" } }
opts = mason_options { { "ruff", version = "test-version" } }
assert(vim.tbl_contains(opts.ensure_installed, "csharp-language-server"))
assert(vim.tbl_contains(opts.ensure_installed, "csharpier"))
assert(opts.ensure_installed[1][1] == "ruff" and opts.ensure_installed[1].version == "test-version")
check_sdk = spec("dotnet", "AstroNvim/astrocore").opts.autocmds.dotnet_sdk_check[1]
check_sdk.callback()
assert(#notifications == 0)

reset { sdk = true, sdk_error = true, paths = { dotnet = "/mock/dotnet" } }
assert(not require("toolchain").have_dotnet_sdk(), "A failed SDK probe must not enable C#")

local paths = {}
for _, command in ipairs {
  "dotnet",
  "basedpyright-langserver",
  "ruff",
  "debugpy-adapter",
  "lua-language-server",
  "stylua",
  "selene",
  "csharp-ls",
  "csharpier",
  "netcoredbg",
  "tree-sitter",
} do
  paths[command] = "/mock/" .. command
end
reset { sdk = true, paths = paths }
assert(#mason_options().ensure_installed == 0, "PATH tools must not be installed twice")
assert(#mason_options({ "selene" }).ensure_installed == 0)
package.loaded["null-ls"] = { builtins = { diagnostics = { selene = { with = function(value) return value end } } } }
opts = {}
spec("mason", "nvimtools/none-ls.nvim").opts(nil, opts)
assert(#opts.sources == 1 and type(opts.sources[1].runtime_condition) == "function")
opts = { handlers = {} }
spec("mason", "jay-babu/mason-null-ls.nvim").opts(nil, opts)
assert(type(opts.handlers.selene) == "function")
opts = { servers = { "custom_server" } }
spec("mason", "AstroNvim/astrolsp").opts(nil, opts)
for _, server in ipairs { "custom_server", "basedpyright", "ruff", "lua_ls", "csharp_ls" } do
  assert(vim.tbl_contains(opts.servers, server), "PATH LSP not enabled: " .. server)
end
spec("dotnet", "mfussenegger/nvim-dap").config()
assert(package.loaded.dap.adapters.coreclr.command == "/mock/netcoredbg")
assert(package.loaded.dap.configurations.cs[1].type == "coreclr")
opts = { handlers = {} }
spec("mason", "jay-babu/mason-nvim-dap.nvim").opts(nil, opts)
assert(type(opts.handlers.coreclr) == "function", "Mason must not replace the PATH adapter")

reset { nix = true, sdk = true, paths = paths }
opts = {}
spec("mason", "AstroNvim/astrolsp").opts(nil, opts)
for _, server in ipairs { "lua_ls", "csharp_ls", "basedpyright", "ruff" } do
  assert(vim.tbl_contains(opts.servers, server), "Nix PATH LSP not enabled: " .. server)
end
assert(not opts.handlers or opts.handlers.csharp_ls ~= false)
assert(#mason_options().ensure_installed == 0)

reset { paths = { python3 = "/mock/python3" }, debugpy = true }
assert(not vim.tbl_contains(mason_options().ensure_installed, "debugpy"))
local config = {}
spec("python", "AstroNvim/astrolsp").opts.config.basedpyright.before_init(nil, config)
assert(config.settings.python.pythonPath == "/mock/python3")
config = { settings = { python = { pythonPath = "/project/.venv/python" } } }
spec("python", "AstroNvim/astrolsp").opts.config.basedpyright.before_init(nil, config)
assert(config.settings.python.pythonPath == "/project/.venv/python")

reset { windows = true, paths = { python = "C:/project/.venv/Scripts/python.exe", python3 = "C:/Python/python3.exe" } }
assert(require("toolchain").python() == "C:/project/.venv/Scripts/python.exe")

reset {
  nix = true,
  virtual_env = "/project/.venv",
  paths = { python = "/nix/pinned/python" },
  executables = { ["/project/.venv/bin/python"] = true },
}
assert(require("toolchain").python() == "/project/.venv/bin/python")

reset {
  windows = true,
  conda_prefix = "C:/envs/project",
  paths = { python = "C:/Python/python.exe" },
  executables = { ["C:/envs/project/python.exe"] = true },
}
assert(require("toolchain").python() == "C:/envs/project/python.exe")

reset()
config = {}
spec("python", "AstroNvim/astrolsp").opts.config.basedpyright.before_init(nil, config)
assert(config.settings.python.pythonPath == nil, "Never set a nonexistent Python path")

local setup_path
package.loaded["dap-python"] = {
  setup = function(path)
    setup_path = path
    package.loaded.dap.adapters.python = function(callback, request)
      callback {
        type = request.request == "attach" and "server" or "executable",
        command = path,
        args = { "-m", "debugpy.adapter" },
        port = request.port,
      }
    end
  end,
}

for _, windows in ipairs { false, true } do
  local adapter = windows and "C:/tools/debugpy-adapter.exe" or "/mock/debugpy-adapter"
  reset { windows = windows, paths = { ["debugpy-adapter"] = adapter } }
  spec("python", "mfussenegger/nvim-dap-python").config(nil, {})
  assert(setup_path == adapter)
  local result
  package.loaded.dap.adapters.python(function(value) result = value end, { request = "launch" })
  assert(result.command == adapter and #result.args == 0, "Adapter executables must not receive Python arguments")
  package.loaded.dap.adapters.python(function(value) result = value end, { request = "attach", port = 5678 })
  assert(result.type == "server" and result.port == 5678, "Remote attach must remain unchanged")
end

for _, windows in ipairs { false, true } do
  local python = "/mock/mason/packages/debugpy/venv" .. (windows and "/Scripts/python.exe" or "/bin/python")
  reset { windows = windows, executables = { [python] = true } }
  spec("python", "mfussenegger/nvim-dap-python").config(nil, {})
  assert(setup_path == python and #notifications == 0)
  reset { nix = true, windows = windows, executables = { [python] = true } }
  spec("python", "mfussenegger/nvim-dap-python").config(nil, {})
  assert(package.loaded.dap.adapters.python == nil and #notifications == 1, "Nix must not reuse Mason Python")
end

reset {
  windows = true,
  paths = { ["debugpy-adapter"] = "C:/mason/debugpy-adapter.cmd" },
  executables = { ["/mock/mason/packages/debugpy/venv/Scripts/python.exe"] = true },
}
spec("python", "mfussenegger/nvim-dap-python").config(nil, {})
assert(setup_path == "/mock/mason/packages/debugpy/venv/Scripts/python.exe")

reset { paths = { python = "/mock/python" }, debugpy = true }
spec("python", "mfussenegger/nvim-dap-python").config(nil, {})
assert(setup_path == "/mock/python")

reset { windows = true, paths = { pwsh = "C:/pwsh.exe" } }
local core = assert(loadfile "nvim/lua/plugins/astrocore.lua")().opts
assert(core.options.opt.shell == "pwsh" and core.options.opt.shellcmdflag:find("-NoProfile", 1, true))
assert(core.options.opt.clipboard == "unnamedplus" and core.filetypes == nil)
assert(core.mappings.n.yA and core.mappings.n["<S-Right>"] and core.mappings.n.n[1] == "nzzzv")

print "Neovim toolchain checks passed"
