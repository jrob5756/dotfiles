-- Python LSP servers live on PATH via `uv tool install`, not Mason, because
-- Mason's pip-based installers require python3-venv which isn't present here.
--   uv tool install basedpyright ruff debugpy

---@type LazySpec
return {
  {
    "AstroNvim/astrolsp",
    ---@type AstroLSPOpts
    opts = {
      -- enable servers that are on PATH but not managed by Mason
      servers = { "basedpyright", "ruff" },
    },
  },
}
