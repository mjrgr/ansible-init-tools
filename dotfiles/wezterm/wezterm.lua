local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

config.default_workspace = 'main'

-- ============================================================
-- Input (Linux/Wayland)
-- ============================================================
-- This build's native Wayland input path drops keystrokes (dead keys,
-- accented characters) and swallows some Ctrl+key bindings (e.g. Ctrl+R).
-- XWayland doesn't have these bugs, so force it rather than native Wayland.
config.enable_wayland = false

-- ============================================================
-- Rendering / perf
-- ============================================================
config.front_end = 'OpenGL'
config.max_fps = 120
config.animation_fps = 30
config.status_update_interval = 1000

-- ============================================================
-- Font
-- ============================================================
config.font = wezterm.font_with_fallback {
  'JetBrainsMono Nerd Font',
  'Noto Color Emoji',
}
config.font_size = 12.0
-- Grayscale AA is forced by window_background_opacity < 1: LCD subpixel
-- rendering produces color fringing over a translucent background.
config.freetype_load_target = 'Light'
config.freetype_render_target = 'Normal'
config.warn_about_missing_glyphs = false
config.adjust_window_size_when_changing_font_size = false

-- ============================================================
-- Theme: follows the desktop light/dark preference
-- ============================================================
local DARK, LIGHT = 'Catppuccin Mocha', 'Catppuccin Latte'

local function current_scheme()
  -- wezterm.gui is absent in the mux server
  if wezterm.gui and wezterm.gui.get_appearance():find 'Dark' then return DARK end
  if wezterm.gui then return LIGHT end
  return DARK
end

config.color_scheme = current_scheme()

local palette = wezterm.color.get_builtin_schemes()[config.color_scheme]
config.window_frame = {
  font = wezterm.font { family = 'JetBrainsMono Nerd Font', weight = 'Bold' },
  font_size = 11.0,
  active_titlebar_bg = palette.background,
  inactive_titlebar_bg = palette.background,
}
config.colors = {
  tab_bar = {
    inactive_tab_edge = palette.background,
  },
}

-- ============================================================
-- Window
-- ============================================================
config.window_background_opacity = 0.98
config.window_decorations = 'RESIZE'
config.window_padding = { left = 8, right = 8, top = 6, bottom = 4 }
config.window_close_confirmation = 'AlwaysPrompt'
config.skip_close_confirmation_for_processes_named = {
  'bash', 'zsh', 'fish', 'sh',
}
config.audible_bell = 'Disabled'
config.scrollback_lines = 50000

-- ============================================================
-- Tab bar
-- ============================================================
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 40

wezterm.on('format-tab-title', function(tab, tabs, panes, cfg, hover, max_width)
  local pane = tab.active_pane
  local title = pane.title
  if pane.current_working_dir then
    title = string.match(pane.current_working_dir.file_path, '([^/]+)/?$') or title
  end
  -- kube_ctx comes from the zsh precmd hook: visible even on an inactive tab
  local ctx = pane.user_vars.kube_ctx
  local suffix = ''
  if ctx and ctx ~= '' then
    suffix = ' 󱃾 ' .. (ctx:len() > 16 and ctx:sub(1, 16) .. '…' or ctx)
  end
  if pane.is_zoomed then suffix = suffix .. ' ' end
  return { { Text = string.format(' %d:%s%s ', tab.tab_index + 1, title, suffix) } }
end)

wezterm.on('update-right-status', function(window, pane)
  local cells = {}
  local ws = window:active_workspace()
  if ws ~= config.default_workspace then table.insert(cells, ' ' .. ws) end
  table.insert(cells, ' ' .. (pane:get_user_vars().distro or pane:get_domain_name()))
  table.insert(cells, wezterm.strftime '%H:%M')
  window:set_right_status(wezterm.format {
    { Foreground = { Color = palette.ansi[5] } },
    { Text = ' ' .. table.concat(cells, '  ') .. ' ' },
  })
end)

-- ============================================================
-- Quick select (CTRL+SHIFT+Space): common infra targets
-- ============================================================
config.quick_select_patterns = {
  '[0-9a-f]{7,64}',                                  -- git sha / image digest
  '[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}',
  '(?:\\d{1,3}\\.){3}\\d{1,3}(?:/\\d{1,2})?',        -- IPv4 + CIDR
  '[a-z0-9][a-z0-9.-]*-[0-9a-z]{5,10}',              -- k8s pod names
  '(?:/|~/)[^\\s\'"]{3,}',                           -- absolute paths
}

config.hyperlink_rules = wezterm.default_hyperlink_rules()
table.insert(config.hyperlink_rules, {
  regex = '\\b(?:\\d{1,3}\\.){3}\\d{1,3}:(\\d{2,5})\\b',
  format = 'http://$0',
})

-- ============================================================
-- Custom actions
-- ============================================================
-- Requires OSC 133 on the shell side (~/.config/zsh/wezterm.zsh)
wezterm.on('copy-last-output', function(window, pane)
  local zones = pane:get_semantic_zones 'Output'
  local zone = zones[#zones]
  if not zone then
    window:toast_notification('WezTerm', 'No output detected', nil, 2000)
    return
  end
  local text = pane:get_text_from_semantic_zone(zone)
  window:copy_to_clipboard(text)
  window:toast_notification('WezTerm', #text .. ' bytes copied', nil, 2000)
end)

wezterm.on('toggle-opacity', function(window)
  local o = window:get_config_overrides() or {}
  o.window_background_opacity = (o.window_background_opacity == 1.0) and 0.98 or 1.0
  window:set_config_overrides(o)
end)

-- ============================================================
-- Key bindings
-- ============================================================
config.keys = {
  -- Panes
  { key = 'h', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'v', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  -- CTRL+SHIFT+V is taken by the split: clipboard paste is rebound explicitly
  { key = 'Insert', mods = 'SHIFT', action = act.PasteFrom 'Clipboard' },
  { key = 'v', mods = 'CTRL|ALT', action = act.PasteFrom 'Clipboard' },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = true } },
  { key = 'z', mods = 'CTRL|SHIFT', action = act.TogglePaneZoomState },

  { key = 'LeftArrow',  mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow',    mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow',  mods = 'ALT', action = act.ActivatePaneDirection 'Down' },

  { key = 'LeftArrow',  mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Left', 3 } },
  { key = 'RightArrow', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Right', 3 } },
  { key = 'UpArrow',    mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Up', 2 } },
  { key = 'DownArrow',  mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Down', 2 } },

  -- Prompt navigation (OSC 133 semantic zones)
  { key = 'UpArrow',   mods = 'CTRL|SHIFT', action = act.ScrollToPrompt(-1) },
  { key = 'DownArrow', mods = 'CTRL|SHIFT', action = act.ScrollToPrompt(1) },
  { key = 'y', mods = 'CTRL|SHIFT', action = act.EmitEvent 'copy-last-output' },

  -- Tabs
  { key = 't', mods = 'CTRL|SHIFT', action = act.SpawnTab 'DefaultDomain' },
  { key = 'T', mods = 'CTRL|ALT',   action = act.ShowLauncherArgs { flags = 'LAUNCH_MENU_ITEMS|DOMAINS|FUZZY' } },
  { key = 'LeftArrow',  mods = 'CTRL|SHIFT', action = act.MoveTabRelative(-1) },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = act.MoveTabRelative(1) },
  { key = 'R', mods = 'CTRL|ALT', action = act.ReloadConfiguration },
  -- WezTerm's own default binds plain Ctrl+R to ReloadConfiguration, silently
  -- eating the shell's fzf history search. Free it up for the terminal app.
  -- Case matters here: the built-in default is registered as key='R', and an
  -- override only cancels it if declared with the exact same case.
  { key = 'R', mods = 'CTRL', action = act.DisableDefaultAssignment },
  -- Off the r key on purpose: Ctrl+R is the shell's fzf history search.
  { key = 'e', mods = 'CTRL|SHIFT', action = act.PromptInputLine {
      description = 'Tab title:',
      action = wezterm.action_callback(function(window, pane, line)
        if line and line ~= '' then window:active_tab():set_title(line) end
      end),
  } },

  -- Workspaces
  { key = 's', mods = 'CTRL|SHIFT', action = act.ShowLauncherArgs { flags = 'WORKSPACES|FUZZY' } },
  { key = 'n', mods = 'CTRL|ALT', action = act.PromptInputLine {
      description = 'New workspace:',
      action = wezterm.action_callback(function(window, pane, line)
        if line and line ~= '' then
          window:perform_action(act.SwitchToWorkspace { name = line }, pane)
        end
      end),
  } },

  -- Misc
  { key = 'k', mods = 'CTRL|SHIFT', action = act.Multiple {
      act.ClearScrollback 'ScrollbackAndViewport',
      act.SendKey { key = 'L', mods = 'CTRL' },
  } },
  { key = 'o', mods = 'CTRL|SHIFT', action = act.EmitEvent 'toggle-opacity' },
  { key = 'p', mods = 'CTRL|SHIFT', action = act.ActivateCommandPalette },
  { key = 'u', mods = 'CTRL|SHIFT', action = act.CharSelect },
}

for i = 1, 9 do
  table.insert(config.keys, { key = tostring(i), mods = 'ALT', action = act.ActivateTab(i - 1) })
end

return config
