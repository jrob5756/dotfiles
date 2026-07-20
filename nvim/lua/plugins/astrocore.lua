-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

-- On Windows, Neovim's default shell is `cmd.exe`. We switch it to PowerShell 7 (falling back
-- to Windows PowerShell) for UTF-8 output and consistency with the interactive shell.
--
-- CRITICAL: `-NoProfile` is mandatory here. `vim.o.shell` is used for every string-based
-- `vim.fn.system("...")` / `:!` call (e.g. Neo-tree cancels search jobs via
-- `system("taskkill ...")`). Without `-NoProfile`, each of those spawns a pwsh that loads the
-- full user profile (oh-my-posh, module imports, starship) and, run non-interactively/
-- redirected, effectively hangs for 60s+ — freezing the whole editor on routine actions like
-- filtering Neo-tree. With `-NoProfile` the same call is ~0.6s. Interactive terminals that
-- WANT the profile are launched explicitly (see lua/plugins/toggleterm.lua `<Leader>t5/t7/tc`).
-- No-op on macOS/Linux, since this config is shared across all three platforms.
local windows_shell_opts = {}
if vim.fn.has "win32" == 1 then
  local shell = vim.fn.executable "pwsh" == 1 and "pwsh" or "powershell"
  windows_shell_opts = {
    shell = shell,
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
    -- Configure core features of AstroNvim
    features = {
      large_buf = { size = 1024 * 256, lines = 10000 }, -- set global limits for large files for disabling features like treesitter
      autopairs = true, -- enable autopairs at start
      cmp = true, -- enable completion at start
      diagnostics = { virtual_text = true, virtual_lines = false }, -- diagnostic settings on startup
      highlighturl = true, -- highlight URLs at start
      notifications = true, -- enable notifications at start
    },
    -- Diagnostics configuration (for vim.diagnostics.config({...})) when diagnostics are on
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    -- passed to `vim.filetype.add`
    filetypes = {
      -- see `:h vim.filetype.add` for usage
      extension = {
        foo = "fooscript",
      },
      filename = {
        [".foorc"] = "fooscript",
      },
      pattern = {
        [".*/etc/foo/.*"] = "fooscript",
      },
    },
    -- vim options can be configured here
    options = {
      opt = vim.tbl_extend("force", {
        relativenumber = true, -- sets vim.opt.relativenumber
        number = true, -- sets vim.opt.number
        spell = false, -- sets vim.opt.spell
        signcolumn = "yes", -- sets vim.opt.signcolumn to yes
        wrap = false, -- sets vim.opt.wrap
        -- route all yanks/deletes/changes through the system clipboard (`+` register).
        -- NOTE: this means `d`/`c`/`x` also overwrite the OS clipboard, not just `y`.
        clipboard = "unnamedplus", -- sets vim.opt.clipboard
      }, windows_shell_opts),
      g = { -- vim.g.<key>
        -- configure global vim variables (vim.g)
        -- NOTE: `mapleader` and `maplocalleader` must be set in the AstroNvim opts or before `lazy.setup`
        -- This can be found in the `lua/lazy_setup.lua` file
      },
    },
    -- Mappings can be configured through AstroCore as well.
    -- NOTE: keycodes follow the casing in the vimdocs. For example, `<Leader>` must be capitalized
    mappings = {
      -- first key is the mode
      n = {
        -- second key is the lefthand side of the map

        -- navigate buffer tabs
        ["]b"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["[b"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },
        ["<S-Right>"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["<S-Left>"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },

        -- yank the whole buffer to the system clipboard. Capital `A` avoids shadowing the
        -- `ya` "around" text objects (`yaw`, `yap`, `ya(`, ...) and does not move the cursor.
        ["yA"] = { "<Cmd>%y+<CR>", desc = "Yank whole file to system clipboard" },

        -- mappings seen under group name "Buffer"
        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },

        -- tables with just a `desc` key will be registered with which-key if it's installed
        -- this is useful for naming menus
        -- ["<Leader>b"] = { desc = "Buffers" },

        -- setting a mapping to false will disable it
        -- ["<C-S>"] = false,
      },
    },
    autocmds = {
      -- open the file explorer automatically every time Neovim starts
      -- (AstroNvim only auto-opens it when you launch `nvim` on a directory by default)
      neotree_auto_open = {
        {
          event = "VimEnter",
          desc = "Open Neo-Tree explorer on startup",
          callback = function() require("neo-tree.command").execute { action = "show" } end,
        },
      },
    },
  },
}
