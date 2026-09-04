-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
  "AstroNvim/astrocommunity",
  { import = "astrocommunity.pack.lua" },
  -- NOTE: import specific python subpacks, not `astrocommunity.pack.python` —
  -- lazy.nvim recursively imports every submodule, which pulls in pyrefly + ty.
  { import = "astrocommunity.pack.python.base" },
  { import = "astrocommunity.pack.python.basedpyright" },
  { import = "astrocommunity.pack.python.ruff" },
  { import = "astrocommunity.completion.blink-copilot" },
  { import = "astrocommunity.editing-support.auto-save-nvim" },
  { import = "astrocommunity.search.grug-far-nvim" },
  -- import/override with your plugins folder
}
