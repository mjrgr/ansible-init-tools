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

-- wsl.exe addresses a distribution, not a WezTerm domain name; the herd lives in
-- WSL while this config runs in the Windows GUI. Set in the branch below.
local WSL_DISTRO = nil

if IS_WINDOWS then
  -- Derived from `wsl -l -v` at config load, so renaming or adding a distro
  -- costs a Ctrl+Shift+R instead of an edit here.
  local wsl_domains = wezterm.default_wsl_domains()
  for _, dom in ipairs(wsl_domains) do
    dom.default_cwd = '~'
  end
  config.wsl_domains = wsl_domains

  local PREFERRED_DISTRO = 'Ubuntu'
  for _, dom in ipairs(wsl_domains) do
    if dom.distribution == PREFERRED_DISTRO then
      config.default_domain = dom.name
    end
  end
  -- A default_domain naming a distro that no longer exists is a hard config
  -- error, so fall back rather than lose the terminal over a rename.
  if not config.default_domain and wsl_domains[1] then
    config.default_domain = wsl_domains[1].name
  end

  for _, dom in ipairs(wsl_domains) do
    if dom.name == config.default_domain then WSL_DISTRO = dom.distribution end
  end

  -- Shell for the 'local' domain: avoids falling back to cmd.exe.
  config.default_prog = { 'pwsh.exe', '-NoLogo' }

  config.launch_menu = {}
  for _, dom in ipairs(wsl_domains) do
    table.insert(config.launch_menu, {
      label = dom.distribution,
      domain = { DomainName = dom.name },
    })
  end
  table.insert(config.launch_menu, {
    label = 'PowerShell',
    args = { 'pwsh.exe', '-NoLogo' },
    domain = { DomainName = 'local' },
  })
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

-- The scheme actually in force. format-tab-title needs it to choose a readable
-- monochrome, and its own `config` argument is the load-time one — it does not
-- carry the overrides that window-config-reloaded applies on an appearance flip.
local active_scheme = current_scheme()

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

-- Tab bar colours derive from the scheme so one rule set holds on Mocha and
-- Latte: accent for the active tab, a surface one step off the background for
-- the rest. Only semantic markers (prod red, claude orange) stay literal.
local tab_palettes = {}
local function tab_colors(scheme)
  if tab_palettes[scheme] then return tab_palettes[scheme] end
  local p = palette_for(scheme)
  local light = scheme == LIGHT
  local bg, fg = wezterm.color.parse(p.background), wezterm.color.parse(p.foreground)
  local function off_bg(f) return tostring(light and bg:darken(f) or bg:lighten(f)) end
  -- Shifting Mocha's blue-tinted foreground in HSL saturates it into a plain
  -- blue; desaturating is what makes the inactive text read as grey. Latte's
  -- foreground is already mid-grey, so it needs half the shift.
  local function off_fg(f)
    local c = light and fg:lighten(f) or fg:darken(f)
    return tostring(c:desaturate(0.7))
  end
  tab_palettes[scheme] = {
    bar = p.background,
    surface = off_bg(0.12),
    hover = off_bg(0.20),
    accent = p.ansi[5],
    on_accent = p.background,
    fg = p.foreground,
    dim = off_fg(light and 0.15 or 0.25),
    faint = off_fg(light and 0.30 or 0.45),
    red = p.ansi[2],
    yellow = p.ansi[4],
    green = p.ansi[3],
  }
  return tab_palettes[scheme]
end

-- Everything the scheme drives, in one place: applied to `config` at load time,
-- re-applied as overrides when the desktop preference flips.
local function theme(scheme)
  local p = palette_for(scheme)
  local c = tab_colors(scheme)
  return {
    color_scheme = scheme,
    window_frame = {
      -- No Bold anywhere: a synthesised bold pixelates, colour tells the active
      -- tab apart. FiraCode is a per-user install on the Windows side (HKCU
      -- fonts key), JetBrainsMono is the fallback wherever it is missing.
      font = wezterm.font_with_fallback {
        { family = 'FiraCode Nerd Font', weight = 'Medium' },
        { family = 'JetBrainsMono Nerd Font', weight = 'Medium' },
      },
      -- Sets the tab bar height, not just the label size
      font_size = 12.0,
      active_titlebar_bg = p.background,
      inactive_titlebar_bg = p.background,
    },
    colors = {
      tab_bar = {
        background = c.bar,
        -- The visible seam between two inactive tabs of the same colour
        inactive_tab_edge = c.dim,
        active_tab = { bg_color = c.accent, fg_color = c.on_accent },
        inactive_tab = { bg_color = c.surface, fg_color = c.dim },
        inactive_tab_hover = { bg_color = c.hover, fg_color = c.fg },
        new_tab = { bg_color = c.bar, fg_color = c.dim },
        new_tab_hover = { bg_color = c.hover, fg_color = c.fg },
      },
    },
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
  active_scheme = want
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
-- Min/max/close drawn inside the fancy tab bar: no native title bar, but a way
-- to quit with the mouse. Style follows the desktop so the buttons look native.
config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'
config.integrated_title_button_style = IS_WINDOWS and 'Windows' or 'Gnome'
config.integrated_title_button_alignment = 'Right'
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
-- Fancy: the only bar whose height follows window_frame.font_size (retro is one
-- text row, full stop), and it draws inactive_tab_edge between tabs. Retro keeps
-- the pill edges below but cannot be made taller.
local TAB_BAR_RETRO = false
local TAB_BAR_BOTTOM = false

config.use_fancy_tab_bar = not TAB_BAR_RETRO
config.tab_bar_at_bottom = TAB_BAR_BOTTOM
config.hide_tab_bar_if_only_one_tab = false
config.show_new_tab_button_in_tab_bar = true
config.tab_max_width = 36

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

-- herdr multiplexes the agents behind a single pane, so its cwd is wherever it
-- was launched and never where the work is: the title it writes (ui.window_title)
-- is the only part of it that moves.
--
-- Matched on the title, not on the process: a WSL pane exposes no usable process
-- name to the Windows GUI, which reads the Windows process tree and never the
-- distro's /proc. The "herdr: " prefix is set in herdr's own config.toml, so the
-- match is on a string this repo owns at both ends rather than on a shape any
-- other program could produce.
local function herdr_label(p)
  return p.title and p.title:match('^herdr: (.+)$') or nil
end

-- format-tab-title's `panes` argument lists the panes of the *active* tab, for
-- every tab it formats — using it for the others paints the active tab's
-- claude icon on all of them. Inactive tabs are read through the mux instead,
-- shaped like PaneInformation so the detectors below need only one form. A
-- claude left running in a split, on a tab you are not looking at, is the
-- case the indicators exist for.
local function tab_panes(tab, active_panes)
  if tab.is_active then return active_panes end
  local ok, infos = pcall(function()
    local out = {}
    for _, info in ipairs(wezterm.mux.get_tab(tab.tab_id):panes_with_info()) do
      local pane = info.pane
      table.insert(out, {
        pane_id = pane:pane_id(),
        foreground_process_name = pane:get_foreground_process_name(),
        user_vars = pane:get_user_vars(),
        title = pane:get_title(),
      })
    end
    return out
  end)
  if ok and #infos > 0 then return infos end
  return { tab.active_pane }
end

local function any_pane(panes, pred)
  for _, p in ipairs(panes) do
    if pred(p) then return true end
  end
  return false
end

local function user_var(p, name)
  return p.user_vars and p.user_vars[name] or nil
end

-- Process detection alone misses a WSL setup where the GUI is the Windows-side
-- wezterm-gui.exe: it cannot read /proc inside the WSL PID namespace, so
-- foreground_process_name is never populated there. The *_active user vars are
-- set via OSC 1337 by the zsh wrappers (~/.zshrc) — they ride the terminal byte
-- stream instead, so they survive that boundary.
local function runs_claude(panes)
  return any_pane(panes, function(p)
    return is_claude(p.foreground_process_name) or user_var(p, 'claude_active') == '1'
  end)
end

-- Codex is a static musl binary at /usr/local/bin/codex, so the leaf name is the
-- command name — where the process is visible at all. No title fallback: codex
-- overwrites the title with the cwd basename a few seconds in.
local function runs_codex(panes)
  return any_pane(panes, function(p)
    local proc = p.foreground_process_name
    return (proc and proc:match('/codex$') ~= nil) or user_var(p, 'codex_active') == '1'
  end)
end

-- Third track needing nothing at all: k9s sets the pane title to `k9s`, and a
-- title rides the byte stream, so it crosses the WSL boundary from any shell.
local function runs_k9s(panes)
  return any_pane(panes, function(p)
    local proc = p.foreground_process_name
    return (proc and proc:match('/k9s$') ~= nil)
        or user_var(p, 'k9s_active') == '1'
        or (p.title and p.title:match('^k9s') ~= nil)
  end)
end

-- sofka writes `sofka: <context>/<namespace>` and clears it on exit. The colon
-- is load-bearing — a bare `^sofka` also matches a shell sitting in a directory
-- named sofka, which is where this config is edited.
local function runs_sofka(panes)
  return any_pane(panes, function(p)
    local proc = p.foreground_process_name
    return (proc and proc:match('/sofka$') ~= nil)
        or (p.title and p.title:match('^sofka: ') ~= nil)
  end)
end

-- Same contract as sofka, colon included, and title-only for the reason spelled
-- out at herdr_label: on this laptop the pane is a WSL pane and the Windows GUI
-- has no process name to match against.
local function runs_herdr(panes)
  return any_pane(panes, function(p) return herdr_label(p) ~= nil end)
end

-- ---- Per-pane state kept on the GUI side ----
-- Keyed by pane_id; a config reload empties them, which only resets a timer or
-- re-shows a marker once.
local busy_since = {}   -- pane_id -> os.time() when busy first seen
local acked_fail = {}   -- pane_id -> last_fail value already shown on a focused tab
local bells = {}        -- pane_id -> true until the tab is focused

wezterm.on('bell', function(window, pane)
  bells[pane:pane_id()] = true
end)

-- Not has_unseen_output: that flag means "bytes arrived since you last focused
-- this pane" and an invisible OSC 133 or a background redraw sets it, so it
-- stays lit on idle tabs. busy is set by the zsh preexec/precmd pair, so it
-- answers the question actually worth an indicator: is a command running there.
-- No timestamp from the shell (that would cost a base64 fork per command): the
-- start is stamped when the user var arrives. The first-sight fallback below only
-- covers a config reload mid-command.
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'busy' then return end
  busy_since[pane:pane_id()] = value == '1' and os.time() or nil
end)

local function busy_seconds(panes)
  local now, longest = os.time(), nil
  for _, p in ipairs(panes) do
    local id = p.pane_id
    if user_var(p, 'busy') == '1' then
      busy_since[id] = busy_since[id] or now
      local e = now - busy_since[id]
      if not longest or e > longest then longest = e end
    else
      busy_since[id] = nil
    end
  end
  return longest
end

-- Minutes, not seconds: the bar only repaints when something changes (pane
-- output, the clock in the right status once a minute), so a seconds counter
-- advanced in jerks. Under a minute the dot alone says it.
local function fmt_duration(sec)
  if sec < 60 then return '' end
  if sec < 3600 then return math.floor(sec / 60) .. 'm' end
  return string.format('%dh%02d', math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end

-- last_fail is `epoch:rc` from the zsh precmd, '' after a success. A failure is
-- shown on an inactive tab until that tab has been focused once with it.
local function unseen_failure(tab, panes)
  local rc
  for _, p in ipairs(panes) do
    local lf = user_var(p, 'last_fail')
    if lf and lf ~= '' then
      if tab.is_active then
        acked_fail[p.pane_id] = lf
      elseif acked_fail[p.pane_id] ~= lf then
        rc = lf:match(':(%d+)$') or '?'
      end
    end
  end
  return rc
end

-- Focusing the tab is the acknowledgement; anything that rings (make, a script,
-- Claude Code with terminal_bell) gets the marker without wiring a hook.
local function unseen_bell(tab, panes)
  local hit = false
  for _, p in ipairs(panes) do
    if bells[p.pane_id] then
      if tab.is_active then bells[p.pane_id] = nil else hit = true end
    end
  end
  return hit
end

-- Set by the Claude Code hooks (claude-state-hook.sh): working after a prompt,
-- waiting after a Stop or a permission/idle notification, '' otherwise. waiting
-- is shown until the tab has been focused once, like the bell: on the focused
-- tab you are already looking at the answer. Any other state resets the ack.
local acked_wait = {}   -- pane_id -> true once its 'waiting' was seen focused
local function claude_state(tab, panes)
  local state = ''
  for _, p in ipairs(panes) do
    local st = user_var(p, 'claude_state')
    if st == 'waiting' then
      if tab.is_active then
        acked_wait[p.pane_id] = true
      elseif not acked_wait[p.pane_id] then
        return 'waiting'
      end
    else
      acked_wait[p.pane_id] = nil
      if st == 'working' then state = 'working' end
    end
  end
  return state
end

local function ssh_host(panes)
  for _, p in ipairs(panes) do
    local h = user_var(p, 'ssh_host')
    if h and h ~= '' then return h end
  end
  return nil
end

-- is_root covers the local shell; a `root@` title covers remote or sudo -i
-- shells, which run without these dotfiles.
local function is_root(panes)
  return any_pane(panes, function(p)
    return user_var(p, 'is_root') == '1' or (p.title and p.title:match('^root@') ~= nil)
  end)
end

-- ---- Title ----
-- Matched on the path rather than $HOME: the Windows-side GUI's HOME is the
-- Windows profile, never the WSL one.
local HOME_PATTERNS = { '^/home/[^/]+/?$', '^/root/?$', '^/Users/[^/]+/?$', '^/[A-Za-z]:/Users/[^/]+/?$' }
-- Leaves that say nothing on their own: shown as parent/leaf instead.
local GENERIC_LEAF = {
  src = true, lib = true, bin = true, docs = true, test = true, tests = true, scripts = true,
  config = true, ['.config'] = true, dotfiles = true, playbooks = true, roles = true,
  tasks = true, templates = true, files = true, defaults = true, vars = true,
}
local TITLE_MAX = 22

local function is_home(path)
  for _, pat in ipairs(HOME_PATTERNS) do
    if path:match(pat) then return true end
  end
  return false
end

-- Middle truncation: the two ends of a repo name carry the meaning
-- (`ansible-…-tools`), the tail alone rarely does.
local function shorten(s, max)
  local len = utf8.len(s)
  if not len then return s end
  if len <= max then return s end
  local keep = math.floor((max - 1) / 2)
  local head = s:sub(1, utf8.offset(s, keep + 1) - 1)
  local tail = s:sub(utf8.offset(s, -keep))
  return head .. '…' .. tail
end

local function tab_title(tab)
  -- Ctrl+Shift+E sets tab_title; it has to win over the cwd or the binding is dead
  if tab.tab_title and tab.tab_title ~= '' then return tab.tab_title end
  local pane = tab.active_pane
  local herd = herdr_label(pane)
  if herd then return shorten(herd, TITLE_MAX) end
  local cwd = pane.current_working_dir
  if not cwd then return shorten(pane.title, TITLE_MAX) end
  local path = cwd.file_path
  if is_home(path) then return '~' end
  local parent, leaf = path:match('([^/]+)/([^/]+)/?$')
  leaf = leaf or path:match('([^/]+)/?$') or pane.title
  if parent and GENERIC_LEAF[leaf] then return shorten(parent .. '/' .. leaf, TITLE_MAX) end
  return shorten(leaf, TITLE_MAX)
end

-- ---- Kube context criticality ----
-- Non-prod names are tested first: `nonprod` and `preprod` both contain `prod`.
local NONPROD_PATTERNS = {
  'preprod', 'pprod', 'pprd', 'nonprod', 'non%-prod', 'hprod', 'hors%-prod',
  'staging', 'stg', 'uat', 'recette',
}
-- Shared by the kube context and the ssh host: the name says the environment.
local function env_color(name, c)
  local l = name:lower()
  for _, pat in ipairs(NONPROD_PATTERNS) do
    if l:find(pat) then return c.yellow end
  end
  if l:find('prod', 1, true) then return c.red end
  return nil
end

wezterm.on('format-tab-title', function(tab, tabs, active_panes, cfg, hover, max_width)
  local c = tab_colors(active_scheme)
  local panes = tab_panes(tab, active_panes)
  local pane = tab.active_pane
  local bg = tab.is_active and c.accent or (hover and c.hover or c.surface)
  local fg = tab.is_active and c.on_accent or (hover and c.fg or c.dim)
  local faint = tab.is_active and c.on_accent or c.faint
  local in_claude, in_codex = runs_claude(panes), runs_codex(panes)
  local in_k9s, in_sofka = runs_k9s(panes), runs_sofka(panes)
  local in_herdr = runs_herdr(panes)
  local cl_state = in_claude and claude_state(tab, panes) or ''
  -- Tracked on every tab so the timer starts while the tab is still focused
  local busy = busy_seconds(panes)
  local fail_rc = unseen_failure(tab, panes)
  local rang = unseen_bell(tab, panes)

  local items = {}
  local function push(t) table.insert(items, t) end
  local function colored(color, text)
    push { Foreground = { Color = color } }
    push { Text = text }
    push { Foreground = { Color = fg } }
  end

  -- Every icon literal below is tuned against the bar, which is near-black on
  -- Mocha and near-white on Latte. The active tab is neither: it paints itself
  -- ansi[5], and measured against that no literal clears 2.4:1 — k9s lands at
  -- 1.03, invisible. fg is on_accent there (7.8 and 4.3), so the active tab
  -- drops the hue and keeps the shape, which is what identifies the icon anyway.
  local function icon(col) return tab.is_active and fg or col end

  -- Each tab is a pill on the bar background — rounded edges plus a one-cell
  -- gap after it — so the boundary between two tabs never depends on a colour
  -- difference alone. The fancy bar draws its own tab shape; an explicit
  -- background there renders as a box inside it.
  if TAB_BAR_RETRO then
    push { Background = { Color = c.bar } }
    push { Foreground = { Color = bg } }
    push { Text = '' }
    push { Background = { Color = bg } }
  end
  push { Foreground = { Color = fg } }
  push { Text = ' ' }

  -- Icons first: the fancy bar's hover close button covers the right edge.
  -- Claude's brand colour is a literal on purpose: it must read identically on
  -- Mocha and Latte.
  if in_claude then
    -- Green = it is waiting on you; brand orange = it is working; dim = idle
    local col = cl_state == 'waiting' and c.green or (cl_state == 'working' and '#DE7356' or fg)
    colored(icon(col), '󰚩 ')
  end
  -- Codex is branded monochrome, so it flips with the scheme rather than being
  -- one literal; the glyph, not the colour, is what separates it from claude.
  if in_codex then colored(icon(active_scheme == LIGHT and '#4c4f69' or '#ffffff'), '󰧑 ') end
  if in_k9s then colored(icon('#326ce5'), '󱃾 ') end
  -- Upstream's cat, not a second kube glyph: two icons differing only by colour
  -- are indistinguishable at tab-bar size.
  if in_sofka then colored(icon('#5a7d99'), '󰄛 ') end
  -- Teal scores 2.77 against both inactive backgrounds, above every other
  -- literal here; on the active tab icon() takes over.
  if in_herdr then colored(icon('#3c898b'), '󰳆 ') end
  -- The agent and cluster-TUI icons already say a long-running command owns this tab
  local owned = in_claude or in_codex or in_k9s or in_sofka or in_herdr
  if not tab.is_active and busy and not owned then
    local d = fmt_duration(busy)
    colored('#ff9e64', '●' .. (d ~= '' and d or '') .. ' ')
  elseif fail_rc and not owned then
    colored(c.red, '✗' .. fail_rc .. ' ')
  end
  -- Claude's own waiting state already carries the bell it rings
  if rang and cl_state ~= 'waiting' then colored(c.yellow, '󰂚 ') end
  if is_root(panes) then colored(c.red, ' ') end

  colored(faint, (tab.tab_index + 1) .. ' ')
  push { Text = tab_title(tab) }

  -- Only a non-default branch is a signal worth the width
  local branch = pane.user_vars.git_branch
  if branch and branch ~= '' and branch ~= 'main' and branch ~= 'master' then
    colored(faint, '  ' .. shorten(branch, 14))
  end

  -- kube_ctx comes from the zsh precmd hook: visible even on an inactive tab.
  -- Colour means risk (prod red, non-prod yellow), not "a TUI is up".
  local ctx = pane.user_vars.kube_ctx
  if ctx and ctx ~= '' then
    local col = env_color(ctx, c) or fg
    colored(col, (in_k9s and ' ' or ' 󱃾 ') .. shorten(ctx, 16))
  end

  local host = ssh_host(panes)
  if host then colored(env_color(host, c) or fg, '  ' .. shorten(host, 16)) end

  if #panes > 1 then colored(faint, ' ⊞' .. #panes) end
  if pane.is_zoomed then push { Text = ' ' } end
  push { Text = ' ' }

  if TAB_BAR_RETRO then
    push { Background = { Color = c.bar } }
    push { Foreground = { Color = bg } }
    push { Text = ' ' }
  end
  return items
end)

-- Nerd Font, not the Unicode symbols: U+23F8 PAUSE is absent from JetBrainsMono
-- and falls back to the emoji font, which renders it coloured and out of step
-- with every other glyph on the line.
local HERD_MARK = { working = '󰉁', blocked = '󰏤', done = '󰄬' }

-- Written every couple of seconds by herd-publish.sh. A file read, not a process
-- spawn: update-right-status runs on the GUI thread once a second, and asking
-- herdr directly would mean wsl.exe on that thread — ~100 ms of frozen UI per
-- tick. The publisher pays the crossing instead, off the GUI thread.
local HERD_STATUS = IS_WINDOWS
  and ((os.getenv 'LOCALAPPDATA' or '') .. '\\herd-status')
  or ((os.getenv 'HOME' or '') .. '/.cache/herd-status')

-- A stale file is a dead publisher, not a quiet herd, and reporting it as "all
-- idle" would be the silent failure this indicator exists to rule out. The window
-- is wide because the two clocks being compared are not the same one: the stamp
-- is written by WSL and read by Windows, and WSL's clock drifts from the host's
-- across a suspend. Wide enough to absorb that, still far short of a publisher
-- that stopped writing two seconds at a time.
local HERD_STALE_AFTER = 120

local function herd_counts()
  local f = io.open(HERD_STATUS, 'r')
  if not f then return nil end
  local line = f:read 'l'
  f:close()
  local w, b, d, at = (line or ''):match('^(%d+) (%d+) (%d+) (%d+)$')
  if not w or os.time() - tonumber(at) > HERD_STALE_AFTER then return nil end
  return tonumber(w), tonumber(b), tonumber(d)
end

wezterm.on('update-right-status', function(window, pane)
  local cells = {}
  local working, blocked, done = herd_counts()
  if working then
    local herd = {}
    if working > 0 then table.insert(herd, working .. HERD_MARK.working) end
    if blocked > 0 then table.insert(herd, blocked .. HERD_MARK.blocked) end
    if done > 0 then table.insert(herd, done .. HERD_MARK.done) end
    -- Idle agents carry no count: the glyph on its own is the herd at rest, and
    -- it has to stay on screen — an indicator that vanishes when nothing happens
    -- cannot be told apart from one that vanished because it broke.
    table.insert(cells, '󰳆' .. (#herd > 0 and ' ' .. table.concat(herd, ' ') or ''))
  end
  local ws = window:active_workspace()
  if ws ~= config.default_workspace then table.insert(cells, ' ' .. ws) end
  -- Same rule as the workspace: only shown when it is not the default
  local domain = pane:get_domain_name()
  if domain ~= (config.default_domain or 'local') then
    table.insert(cells, ' ' .. (pane:get_user_vars().distro or domain))
  end
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

-- ---- herdr: the herd, seen from outside it -------------------------------
--
-- herdr multiplexes the agents, so a WezTerm pane running it shows `herdr` as
-- its foreground process and carries no user vars from the agents inside: every
-- per-pane detector above goes blind the moment you work through it. Its socket
-- API is the way back in, and it reports a richer state than the OSC hook does
-- (blocked and done have no equivalent in claude_state).
--
-- run_child_process blocks the GUI thread, so this is only ever called from a
-- key press — never from update-right-status, which fires once a second.
local function herdr_cli(args)
  local argv = IS_WINDOWS
    and { 'wsl.exe', '-d', WSL_DISTRO or 'Ubuntu', '--', 'herdr' }
    or { 'herdr' }
  for _, a in ipairs(args) do table.insert(argv, a) end
  local ok, stdout = wezterm.run_child_process(argv)
  if not ok then return nil end
  local parsed, decoded = pcall(wezterm.json_parse, stdout)
  return parsed and decoded or nil
end


wezterm.on('herd-jump', function(window, pane)
  local data = herdr_cli { 'agent', 'list' }
  local choices = {}
  for _, a in ipairs(data and data.result and data.result.agents or {}) do
    -- match, not gsub: gsub returns two values and would shift the format args.
    local repo = (a.cwd or ''):match '([^/]+)/?$' or '?'
    table.insert(choices, {
      id = a.pane_id,
      label = ('%s  %-7s %-22s %s'):format(HERD_MARK[a.agent_status] or '·',
        a.agent or '?', repo, a.terminal_title_stripped or ''),
    })
  end
  -- InputSelector with no choices opens an overlay that only Escape closes.
  if #choices == 0 then
    window:toast_notification('herdr',
      data and 'No agents in the herd' or 'herdr is not reachable', nil, 2000)
    return
  end
  window:perform_action(act.InputSelector {
    title = 'the herd',
    choices = choices,
    fuzzy = true,
    action = wezterm.action_callback(function(_, _, id)
      if id then herdr_cli { 'agent', 'focus', id } end
    end),
  }, pane)
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
  -- Both, because on a Windows FR layout Ctrl+Alt is AltGr: the combo arrives as
  -- text input and the CTRL|ALT binding never fires there.
  { key = 'R', mods = 'CTRL|ALT', action = act.ReloadConfiguration },
  { key = 'r', mods = 'CTRL|SHIFT', action = act.ReloadConfiguration },
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

  -- Agents
  { key = 'a', mods = 'CTRL|SHIFT', action = act.EmitEvent 'herd-jump' },

  -- Misc
  { key = 'k', mods = 'CTRL|SHIFT', action = act.Multiple {
      act.ClearScrollback 'ScrollbackAndViewport',
      act.SendKey { key = 'L', mods = 'CTRL' },
  } },
  { key = 'o', mods = 'CTRL|SHIFT', action = act.EmitEvent 'toggle-opacity' },
  -- Window and app close both honour window_close_confirmation
  { key = 'q', mods = 'CTRL|SHIFT', action = act.QuitApplication },
  { key = 'p', mods = 'CTRL|SHIFT', action = act.ActivateCommandPalette },
  { key = 'u', mods = 'CTRL|SHIFT', action = act.CharSelect },
}

for i = 1, 9 do
  table.insert(config.keys, { key = tostring(i), mods = 'ALT', action = act.ActivateTab(i - 1) })
end

return config
