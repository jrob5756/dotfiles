local windows_shell_opts = {}
if vim.fn.has "win32" == 1 then
  local shell = vim.fn.executable "pwsh" == 1 and "pwsh" or "powershell"
  windows_shell_opts = {
    shell = shell,
    -- Background shell calls must not load interactive profiles, which can block the editor.
    shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding="
      .. "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;",
    shellredir = "-RedirectStandardOutput %s -NoNewWindow -Wait",
    shellpipe = "2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode",
    shellquote = "",
    shellxquote = "",
  }
end

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    features = {
      large_buf = { size = 1024 * 256, lines = 10000 },
      autopairs = true,
      cmp = true,
      diagnostics = { virtual_text = true, virtual_lines = false },
      highlighturl = true,
      notifications = true,
    },
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    options = {
      opt = vim.tbl_extend("force", {
        relativenumber = true,
        number = true,
        spell = false,
        signcolumn = "yes",
        wrap = false,
        -- Deletes and changes also overwrite the system clipboard.
        clipboard = "unnamedplus",
      }, windows_shell_opts),
    },
    mappings = {
      n = {
        ["]b"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["[b"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },
        ["<S-Right>"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["<S-Left>"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },

        -- Capital A preserves the "around" text objects; the cursor stays put.
        ["yA"] = { "<Cmd>%y+<CR>", desc = "Yank whole file to system clipboard" },

        -- Normal mode only: recenter and open folds without breaking dn/cn.
        ["n"] = { "nzzzv", desc = "Next search result (centred)" },
        ["N"] = { "Nzzzv", desc = "Previous search result (centred)" },

        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },
      },
    },
    autocmds = {
      neotree_auto_open = {
        {
          event = "StdinReadPre",
          desc = "Remember that Neovim is reading stdin",
          callback = function() vim.g.dotfiles_started_with_stdin = true end,
        },
        {
          event = "VimEnter",
          desc = "Open Neo-Tree explorer on a bare startup",
          -- Skip file arguments so $EDITOR uses (git commit, kubectl edit) stay uncluttered;
          -- Neo-tree already takes over directory arguments itself.
          callback = function()
            if vim.fn.argc() == 0 and not vim.g.dotfiles_started_with_stdin then
              require("neo-tree.command").execute { action = "show" }
            end
          end,
        },
      },
    },
  },
}
