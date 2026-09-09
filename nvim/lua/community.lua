---@type LazySpec
return {
  "AstroNvim/astrocommunity",
  { import = "astrocommunity.pack.lua" },
  -- Import only the chosen Python servers; recursive pack imports also load pyrefly and ty.
  { import = "astrocommunity.pack.python.base" },
  { import = "astrocommunity.pack.python.basedpyright" },
  { import = "astrocommunity.pack.python.ruff" },
  { import = "astrocommunity.completion.blink-copilot" },
  { import = "astrocommunity.editing-support.conform-nvim" },
  { import = "astrocommunity.editing-support.auto-save-nvim" },
  { import = "astrocommunity.search.grug-far-nvim" },
}
