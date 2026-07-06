-- vim-tmux-navigator: lets Ctrl-h/j/k/l move seamlessly between Neovim splits
-- and tmux panes with the same keys, matching tmux/tmux.conf's pane navigation
-- bindings (see that file's `is_vim` bindings). Requires TPM + this plugin
-- installed on the tmux side too — see ~/dotfiles/tmux/README.md.

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
        -- override AstroNvim's default <C-w>h/j/k/l window-nav mappings so
        -- they fall through to tmux when there's no more Neovim split to move
        -- into in that direction, instead of doing nothing at the edge
        maps.n["<C-h>"] = { "<Cmd>TmuxNavigateLeft<CR>", desc = "Move to left split (or tmux pane)" }
        maps.n["<C-j>"] = { "<Cmd>TmuxNavigateDown<CR>", desc = "Move to below split (or tmux pane)" }
        maps.n["<C-k>"] = { "<Cmd>TmuxNavigateUp<CR>", desc = "Move to above split (or tmux pane)" }
        maps.n["<C-l>"] = { "<Cmd>TmuxNavigateRight<CR>", desc = "Move to right split (or tmux pane)" }
      end,
    },
  },
}
