local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

config.default_workspace = 'main'

-- ============================================================
-- Platform branch
-- ============================================================
-- Same file drives the native Linux box (Zorin) and the Windows+WSL laptop —
-- wezterm-gui.exe on Windows reads this file too. One source of truth is what
-- stops the two setups drifting apart the way they did before.
local IS_WINDOWS = wezterm.target_triple:find('windows') ~= nil

if IS_WINDOWS then
  -- One domain per distro: does not depend on wsl.exe's default distro.
  config.wsl_domains = {
    { name = 'WSL:22.04', distribution = 'Ubuntu-22.04', default_cwd = '~' },
    { name = 'WSL:24.04', distribution = 'Ubuntu-24.04', default_cwd = '~' },
  }
  config.default_domain = 'WSL:22.04'
  -- Shell for the 'local' domain: avoids falling back to cmd.exe.
  config.default_prog = { 'pwsh.exe', '-NoLogo' }
  config.launch_menu = {
    { label = 'Ubuntu 22.04', domain = { DomainName = 'WSL:22.04' } },
    { label = 'Ubuntu 24.04', domain = { DomainName = 'WSL:24.04' } },
    { label = 'PowerShell',   args = { 'pwsh.exe', '-NoLogo' }, domain = { DomainName = 'local' } },
  }
else
  -- ============================================================
  -- Input (Linux/Wayland)
  -- ============================================================
  -- This build's native Wayland input path drops keystrokes (dead keys,
  -- accented characters) and swallows some Ctrl+key bindings (e.g. Ctrl+R).
  -- XWayland doesn't have these bugs, so force it rather than native Wayland.
  config.enable_wayland = false
end

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
  IS_WINDOWS and 'Segoe UI Emoji' or 'Noto Color Emoji',
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
  -- wezterm.gui is absent in the mux server, which has no appearance to read
  if wezterm.gui and wezterm.gui.get_appearance():find 'Dark' then return DARK end
  if wezterm.gui then return LIGHT end
  return DARK
end

-- get_builtin_schemes() walks every bundled scheme. update-right-status runs once
-- a second and format-tab-title far more often than that, so the two in use are
-- resolved once and kept.
local palettes = {}
local function palette_for(scheme)
  if not palettes[scheme] then
    palettes[scheme] = wezterm.color.get_builtin_schemes()[scheme]
  end
  return palettes[scheme]
end

-- Everything the scheme drives, in one place: applied to `config` at load time,
-- re-applied as overrides when the desktop preference flips.
local function theme(scheme)
  local p = palette_for(scheme)
  return {
    color_scheme = scheme,
    window_frame = {
      font = wezterm.font { family = 'JetBrainsMono Nerd Font', weight = 'Bold' },
      font_size = 11.0,
      active_titlebar_bg = p.background,
      inactive_titlebar_bg = p.background,
    },
    colors = { tab_bar = { inactive_tab_edge = p.background } },
  }
end

local initial = theme(current_scheme())
config.color_scheme = initial.color_scheme
config.window_frame = initial.window_frame
config.colors = initial.colors

-- Evaluated at load time, the scheme only ever tracked the desktop at startup:
-- switching Zorin to light left the terminal dark until an explicit reload.
-- wezterm raises window-config-reloaded when the system appearance changes, so
-- re-deriving here is what makes it actually follow — titlebar and tab bar
-- included, which a bare color_scheme override would leave on the old palette.
wezterm.on('window-config-reloaded', function(window)
  local want = current_scheme()
  local overrides = window:get_config_overrides() or {}
  -- set_config_overrides re-fires this event; comparing against the scheme in
  -- force (override first, load-time value before any flip) ends the loop and
  -- keeps startup from applying an override it does not need.
  if (overrides.color_scheme or config.color_scheme) == want then return end
  local t = theme(want)
  overrides.color_scheme = t.color_scheme
  overrides.window_frame = t.window_frame
  overrides.colors = t.colors
  window:set_config_overrides(overrides)
end)

local function window_palette(window)
  local overrides = window:get_config_overrides() or {}
  return palette_for(overrides.color_scheme or config.color_scheme)
end

-- ============================================================
-- Window
-- ============================================================
local OPACITY = 0.98
config.window_background_opacity = OPACITY
config.window_decorations = 'RESIZE'
config.window_padding = { left = 8, right = 8, top = 6, bottom = 4 }
config.window_close_confirmation = 'AlwaysPrompt'
config.skip_close_confirmation_for_processes_named = {
  'bash', 'zsh', 'fish', 'sh', 'cmd.exe', 'pwsh.exe', 'powershell.exe',
}
-- Disabling the audible bell without a replacement made a bell in a background
-- tab completely silent. The flash is on the cursor rather than the whole
-- window: at 0.98 opacity a full-window flash reads as the desktop showing
-- through, not as a bell.
config.audible_bell = 'Disabled'
config.visual_bell = {
  fade_in_duration_ms = 75,
  fade_in_function = 'EaseIn',
  fade_out_duration_ms = 150,
  fade_out_function = 'EaseOut',
  target = 'CursorColor',
}
config.scrollback_lines = 50000

-- ============================================================
-- Tab bar
-- ============================================================
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 40

-- Claude Code installs as a native ELF at ~/.local/share/claude/versions/<semver>,
-- and what wezterm reports is /proc/<pid>/exe — so the basename is a version
-- number, not a command name. Matching the install path is what makes this fire;
-- matching the leaf never would. An npm-installed Claude Code runs under `node`
-- and is invisible here, which is the accepted limit of a process-based check:
-- nothing has to be wired into the shell, so it works in any pane, any shell.
local function is_claude(proc)
  if not proc or proc == '' then return false end
  return proc:find('/claude/versions/', 1, true) ~= nil
      or proc:match('/claude$') ~= nil
end

-- Every pane of the tab, not just the active one: a claude left running in a
-- split, on a tab you are not looking at, is the case the indicator exists for.
-- Process detection alone misses a WSL setup where the GUI is the Windows-side
-- wezterm-gui.exe: it cannot read /proc inside the WSL PID namespace, so
-- foreground_process_name is never populated there. claude_active is a user
-- var set via OSC 1337 by the `claude` zsh wrapper (~/.zshrc) — it rides the
-- terminal byte stream instead, so it survives that boundary.
local function tab_runs_claude(tab)
  for _, p in ipairs(tab.panes or { tab.active_pane }) do
    if is_claude(p.foreground_process_name) then return true end
    if p.user_vars and p.user_vars.claude_active == '1' then return true end
  end
  return false
end

-- Only for tabs you are not looking at: wezterm clears the flag on the focused
-- pane, so on the active tab this is always false and the marker would just
-- flicker. This is what a long build or a `terraform apply` finishing in a
-- background tab now looks like.
local function tab_has_unseen_output(tab)
  if tab.is_active then return false end
  for _, p in ipairs(tab.panes or {}) do
    if p.has_unseen_output then return true end
  end
  return false
end

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

  -- Icons go first, right after the leading space: the fancy tab bar draws its
  -- hover close button over the tab's right edge, which is exactly where a
  -- trailing icon would sit — leading them keeps both always visible.
  local items = { { Text = ' ' } }
  if tab_runs_claude(tab) then
    -- Same matrix green as the directory module in starship.toml, and a literal
    -- rather than a palette index on purpose: it must read identically whether
    -- the desktop is on Catppuccin Mocha or Latte.
    table.insert(items, { Foreground = { Color = '#00ff41' } })
    table.insert(items, { Text = '󰚩 ' })
    table.insert(items, 'ResetAttributes')
  end
  if tab_has_unseen_output(tab) then
    table.insert(items, { Foreground = { Color = '#ff9e64' } })
    table.insert(items, { Text = '● ' })
    table.insert(items, 'ResetAttributes')
  end
  table.insert(items, { Text = string.format('%d:%s%s ', tab.tab_index + 1, title, suffix) })
  return items
end)

wezterm.on('update-right-status', function(window, pane)
  local cells = {}
  local ws = window:active_workspace()
  if ws ~= config.default_workspace then table.insert(cells, ' ' .. ws) end
  table.insert(cells, ' ' .. (pane:get_user_vars().distro or pane:get_domain_name()))
  table.insert(cells, wezterm.strftime '%H:%M')
  window:set_right_status(wezterm.format {
    { Foreground = { Color = window_palette(window).ansi[5] } },
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
  o.window_background_opacity = (o.window_background_opacity == 1.0) and OPACITY or 1.0
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
