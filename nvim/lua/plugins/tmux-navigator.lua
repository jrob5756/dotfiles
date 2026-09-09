-- The tmux-side pane bindings must match these keys; see tmux/README.md.

---@type LazySpec
return {
  "christoomey/vim-tmux-navigator",
  lazy = false,
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  specs = {
    {
      "AstroNvim/astrocore",
      opts = function(_, opts)
        local maps = opts.mappings
        -- Hand navigation to tmux when the current split touches the editor's edge.
        maps.n["<C-h>"] = { "<Cmd>TmuxNavigateLeft<CR>", desc = "Move to left split (or tmux pane)" }
        maps.n["<C-j>"] = { "<Cmd>TmuxNavigateDown<CR>", desc = "Move to below split (or tmux pane)" }
        maps.n["<C-k>"] = { "<Cmd>TmuxNavigateUp<CR>", desc = "Move to above split (or tmux pane)" }
        maps.n["<C-l>"] = { "<Cmd>TmuxNavigateRight<CR>", desc = "Move to right split (or tmux pane)" }
      end,
    },
  },
}
