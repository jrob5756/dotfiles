-- Customize Mason
--
-- This machine can't build two whole classes of Mason package:
--   * Python packages  — no python3-venv, so every pip-based installer fails
--   * dotnet tools     — ~/.dotnet has the host but no SDK, so `dotnet tool` fails
-- Those are filtered out below so startup isn't spammed with install errors.
-- Python tooling is provided instead by:  uv tool install basedpyright ruff debugpy

local function have_dotnet_sdk()
  if vim.fn.executable "dotnet" ~= 1 then return false end
  local out = vim.fn.system { "dotnet", "--list-sdks" }
  return vim.v.shell_error == 0 and out:match "%S" ~= nil
end

-- Installed via `uv tool install`; already on PATH, so Mason must not retry them.
local uv_managed = { "basedpyright", "ruff", "debugpy", "black", "isort", "pyrefly", "ty" }

local dotnet_packages = { "csharp-language-server", "csharpier" }

---@type LazySpec
return {
  -- use mason-tool-installer for automatically installing Mason packages
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- overrides `require("mason-tool-installer").setup(...)`
    opts = function(_, opts)
      local skip = {}
      for _, pkg in ipairs(uv_managed) do
        skip[pkg] = true
      end
      if not have_dotnet_sdk() then
        for _, pkg in ipairs(dotnet_packages) do
          skip[pkg] = true
        end
      end

      local wanted = {
        -- install language servers
        "lua-language-server",
        "csharp-language-server",

        -- install formatters
        "stylua",
        "csharpier",

        -- install debuggers
        "netcoredbg",

        -- install any other package
        "tree-sitter-cli",
      }

      -- keep anything the community packs added, then drop what can't build here
      local merged = require("astrocore").list_insert_unique(opts.ensure_installed or {}, wanted)
      opts.ensure_installed = vim.tbl_filter(function(pkg) return not skip[pkg] end, merged)
    end,
  },
}
