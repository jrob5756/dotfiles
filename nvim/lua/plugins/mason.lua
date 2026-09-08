local toolchain = require "toolchain"

local commands = {
  ["basedpyright"] = "basedpyright-langserver",
  ["ruff"] = "ruff",
  ["lua-language-server"] = "lua-language-server",
  ["stylua"] = "stylua",
  ["selene"] = "selene",
  ["csharp-language-server"] = "csharp-ls",
  ["csharpier"] = "csharpier",
  ["netcoredbg"] = "netcoredbg",
  ["tree-sitter-cli"] = "tree-sitter",
}

---@type LazySpec
return {
  {
    "mason-org/mason.nvim",
    -- System tools take precedence over stale Mason installations.
    opts = { PATH = toolchain.nix and "skip" or "append" },
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = function(_, opts)
      opts.ensure_installed = {}
      if toolchain.nix then opts.automatic_enable = false end
    end,
  },
  {
    "jay-babu/mason-nvim-dap.nvim",
    opts = function(_, opts)
      opts.ensure_installed = {}
      opts.automatic_installation = false
      if toolchain.nix then
        opts.handlers = nil
      elseif vim.fn.executable "netcoredbg" == 1 then
        opts.handlers = opts.handlers or {}
        opts.handlers.coreclr = function() end
      end
    end,
  },
  {
    "jay-babu/mason-null-ls.nvim",
    opts = function(_, opts)
      opts.ensure_installed = {}
      opts.automatic_installation = false
      if toolchain.nix then
        opts.handlers = nil
      elseif vim.fn.executable "selene" == 1 then
        opts.handlers = opts.handlers or {}
        opts.handlers.selene = function() end
      end
    end,
  },
  {
    "nvimtools/none-ls.nvim",
    opts = function(_, opts)
      if vim.fn.executable "selene" ~= 1 then return end
      opts.sources = opts.sources or {}
      table.insert(
        opts.sources,
        require("null-ls").builtins.diagnostics.selene.with {
          runtime_condition = function(params)
            return #vim.fs.find("selene.toml", { path = params.bufname, upward = true, type = "file" }) > 0
          end,
        }
      )
    end,
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = function(_, opts)
      if toolchain.nix then
        opts.ensure_installed = {}
        opts.run_on_start = false
        opts.auto_update = false
        return
      end

      local wanted = {
        "lua-language-server",
        "csharp-language-server",
        "stylua",
        "csharpier",
        "netcoredbg",
        "tree-sitter-cli",
      }
      local merged = require("astrocore").list_insert_unique(opts.ensure_installed or {}, wanted)
      opts.ensure_installed = vim.tbl_filter(function(entry)
        local package = type(entry) == "table" and entry[1] or entry
        local command = commands[package]
        if command and vim.fn.executable(command) == 1 then return false end
        if package == "debugpy" and (toolchain.debugpy_adapter() or toolchain.debugpy_python()) then return false end
        if package == "csharp-language-server" or package == "csharpier" then
          return toolchain.have_dotnet_sdk()
        end
        return true
      end, merged)
    end,
  },
  {
    "AstroNvim/astrolsp",
    opts = function(_, opts)
      local servers = {}
      for server, command in pairs {
        lua_ls = "lua-language-server",
        basedpyright = "basedpyright-langserver",
        ruff = "ruff",
        csharp_ls = "csharp-ls",
      } do
        if vim.fn.executable(command) == 1 and (server ~= "csharp_ls" or toolchain.have_dotnet_sdk()) then
          table.insert(servers, server)
        end
      end
      opts.servers = require("astrocore").list_insert_unique(opts.servers or {}, servers)
      if not toolchain.have_dotnet_sdk() then
        opts.handlers = opts.handlers or {}
        opts.handlers.csharp_ls = false
      end
    end,
  },
}
