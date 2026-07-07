-- ~/.wezterm.lua
-- See wezterm/README.md for setup instructions.
--
-- WezTerm is fully cross-platform (macOS, Linux, and native Windows), unlike
-- Ghostty which currently has no native Windows support. This config is meant
-- to be the single terminal config that works identically everywhere.

local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Appearance -----------------------------------------------------------

config.color_scheme = "Catppuccin Mocha"
config.font = wezterm.font_with_fallback({
	"JetBrains Mono",
	"Symbols Nerd Font Mono",
})
config.font_size = 13.0
config.window_decorations = "RESIZE" -- hide title bar, keep resize handles
config.window_background_opacity = 1.0
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true

-- RDP sessions into VMs often lack a real GPU (no OpenGL 3.x), which makes
-- WezTerm's default GPU-accelerated renderer fail to create a window. Fall
-- back to the software renderer only when running over RDP so hardware
-- acceleration is still used on machines with a real GPU.
if os.getenv("SESSIONNAME") and os.getenv("SESSIONNAME"):match("^RDP%-") then
	config.front_end = "Software"
end

-- Cursor -----------------------------------------------------------------

config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 500

-- Behavior -------------------------------------------------------------

config.scrollback_lines = 10000
config.audible_bell = "Disabled"

-- Since tmux handles multiplexing (panes/windows/sessions), WezTerm's own
-- leader key is left at its default and unused day-to-day — tmux's `Ctrl-a`
-- prefix (see tmux/tmux.conf) is what actually drives pane/window management.
-- WezTerm tabs are still available for keeping separate tmux sessions (e.g.
-- work vs. personal) visually distinct without nesting prefixes.

return config
