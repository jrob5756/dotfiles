local toolchain = require "toolchain"

---@type LazySpec
return {
  {
    "AstroNvim/astrolsp",
    opts = {
      config = {
        basedpyright = {
          before_init = function(_, config)
            config.settings = config.settings or {}
            config.settings.python = config.settings.python or {}
            -- Preserve project/venv overrides and let the server discover Python when PATH has none.
            if not config.settings.python.pythonPath then config.settings.python.pythonPath = toolchain.python() end
          end,
        },
      },
    },
  },
  {
    "mfussenegger/nvim-dap-python",
    config = function(_, opts)
      local adapter = toolchain.debugpy_adapter()
      local python = not adapter and toolchain.debugpy_python() or nil
      if not adapter and not python and not toolchain.nix then
        local root = require("mason.settings").current.install_root_dir
        local suffix = vim.fn.has "win32" == 1 and "/Scripts/python.exe" or "/bin/python"
        local mason_python = root .. "/packages/debugpy/venv" .. suffix
        if vim.fn.executable(mason_python) == 1 then python = mason_python end
      end
      if not adapter and not python then
        vim.notify(
          "Python debugging requires debugpy-adapter on PATH or Python with debugpy. "
            .. (toolchain.nix and "Rebuild the Nix environment." or "Install debugpy with :Mason."),
          vim.log.levels.WARN
        )
        return
      end

      require("dap-python").setup(python or adapter, opts)
      if adapter then
        local dap = require "dap"
        local configure = dap.adapters.python
        -- nvim-dap-python recognizes Unix adapter names, but not the Windows .exe suffix.
        dap.adapters.python = function(callback, config)
          configure(function(result)
            if result.type == "executable" then
              result.command = adapter
              result.args = {}
            end
            callback(result)
          end, config)
        end
      end
    end,
  },
}
