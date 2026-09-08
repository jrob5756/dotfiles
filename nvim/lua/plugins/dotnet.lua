local toolchain = require "toolchain"

---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    opts = {
      autocmds = {
        dotnet_sdk_check = {
          {
            event = "FileType",
            pattern = "cs",
            once = true,
            callback = function()
              if not toolchain.have_dotnet_sdk() then
                vim.notify(
                  "C# language support requires a .NET SDK on PATH (`dotnet --list-sdks`). "
                    .. "csharp_ls is disabled; Mason will not install csharp-language-server or csharpier.",
                  vim.log.levels.WARN
                )
              end
            end,
          },
        },
      },
    },
  },
  {
    "mfussenegger/nvim-dap",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.nvim-dap"(plugin, opts)
      local command = vim.fn.exepath "netcoredbg"
      if command == "" then return end
      local dap = require "dap"
      dap.adapters.coreclr = {
        type = "executable",
        command = command,
        args = { "--interpreter=vscode" },
      }
      dap.configurations.cs = dap.configurations.cs or {}
      table.insert(dap.configurations.cs, {
        type = "coreclr",
        name = "Launch .NET assembly",
        request = "launch",
        program = function()
          return vim.fn.input("Path to DLL: ", vim.fn.getcwd() .. "/", "file")
        end,
      })
    end,
  },
}
