-- The tmux-side pane bindings must match these keys; see tmux/README.md.
-- Under herdr (modules/herdr.nix) there is no tmux, so hand edges to herdr instead.

local function navigate(wincmd, direction)
  local tmux_command = "TmuxNavigate" .. (direction:gsub("^%l", string.upper))
  return function()
    local pane = vim.env.HERDR_PANE_ID
    if vim.env.TMUX or not pane then return vim.cmd(tmux_command) end
    local win = vim.api.nvim_get_current_win()
    vim.cmd.wincmd(wincmd)
    if vim.api.nvim_get_current_win() == win then
      vim.system { "herdr", "pane", "focus", "--pane", pane, "--direction", direction }
    end
  end
end

---@type LazySpec
return {
  "christoomey/vim-tmux-navigator",
  lazy = false,
  -- The plugin's own <C-hjkl> maps load after astrocore's and would shadow these.
  init = function() vim.g.tmux_navigator_no_mappings = 1 end,
  specs = {
    {
      "AstroNvim/astrocore",
      opts = function(_, opts)
        local maps = opts.mappings
        -- Hand navigation to tmux or herdr when the current split touches the editor's edge.
        maps.n["<C-h>"] = { navigate("h", "left"), desc = "Move to left split (or tmux/herdr pane)" }
        maps.n["<C-j>"] = { navigate("j", "down"), desc = "Move to below split (or tmux/herdr pane)" }
        maps.n["<C-k>"] = { navigate("k", "up"), desc = "Move to above split (or tmux/herdr pane)" }
        maps.n["<C-l>"] = { navigate("l", "right"), desc = "Move to right split (or tmux/herdr pane)" }
      end,
    },
  },
}
