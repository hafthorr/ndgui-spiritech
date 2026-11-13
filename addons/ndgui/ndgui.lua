-- Package entry. load does not require a running Spiritech client.
-- format_observable is stable: no clock, sorted names, fixed numeric text.

local function import(name)
  if ui and ui.require then return ui.require(name) end
  return require(name)
end

local config = import("ndgui.config")
local theme = import("ndgui.theme")
local layout = import("ndgui.layout")
local host = import("ndgui.host")
local menubar = import("ndgui.menubar")
local hud = import("ndgui.hud")
local windows = import("ndgui.windows")

local M = {}

M.VERSION = "0.1.0"
M.config = config
M.theme = theme
M.layout = layout
M.host = host
M.menubar = menubar
M.hud = hud
M.windows = windows

local function fmt_num(n)
  local text = string.format("%.6f", n)
  text = text:gsub("0+$", ""):gsub("%.$", "")
  if text == "" or text == "-" then return "0" end
  return text
end

local function present_elements(cfg, menu, bars, compass, target, shortcuts, built)
  local elements = {}
  if cfg.elements.menubar then elements.menubar = menu end
  if cfg.elements.health then
    elements.health = { id = "health", fraction = bars.health }
  end
  if cfg.elements.nano then
    elements.nano = { id = "nano", fraction = bars.nano }
  end
  if cfg.elements.xp then
    elements.xp = { id = "xp", fraction = bars.xp }
  end
  if cfg.elements.compass then elements.compass = compass end
  if cfg.elements.target then elements.target = target end
  if cfg.elements.shortcutbar then elements.shortcutbar = shortcuts end
  if cfg.elements.inventory then elements.inventory = built.inventory end
  if cfg.elements.chat then elements.chat = built.chat end
  if cfg.elements.raid then elements.raid = built.raid end
  if cfg.elements.options then elements.options = built.options end
  return elements
end

function M.load(opts)
  opts = opts or {}
  local warnings = {}
  local cfg
  if type(opts.config) == "string" then
    local decoded, err = config.decode(opts.config)
    if not decoded then
      warnings[#warnings + 1] = "config decode failed: " .. tostring(err)
      cfg = config.default()
    else
      cfg = decoded
    end
  else
    local normalized, theme_warnings = config.normalize(opts.config or {})
    cfg = normalized
    for i = 1, #theme_warnings do
      warnings[#warnings + 1] = theme_warnings[i]
    end
  end

  local adapter = host.attach(opts.host)
  local input = opts.input or {}
  local fallback = {
    w = input.screen and input.screen.w or layout.REF_W,
    h = input.screen and input.screen.h or layout.REF_H,
    pixel_scale = input.pixel_scale or 1,
  }
  local screen = host.read_display(adapter, fallback)
  local display = layout.resolution(
    { w = screen.w, h = screen.h },
    screen.pixel_scale,
    cfg.ui_scale
  )
  display.pixel_scale_y = screen.pixel_scale_y

  local active = theme.get(cfg.theme) or theme.get("dovvetech")
  local snapshot = opts.snapshot or {}
  local bars = hud.bars(snapshot)
  local menu = menubar.build(cfg, active, {
    scale = display.scale,
    screen = { w = display.viewport_w, h = display.viewport_h },
    hovered = input.hovered,
  })
  local shortcuts = hud.shortcuts(cfg, snapshot, active, display.scale)
  local compass = hud.compass(snapshot)
  local target = hud.target(snapshot)
  local built = windows.build(cfg, active, display.scale, snapshot)
  local elements = present_elements(cfg, menu, bars, compass, target, shortcuts, built)

  local published_windows = {}
  if elements.inventory then published_windows.inventory = built.inventory end
  if elements.chat then published_windows.chat = built.chat end
  if elements.raid then published_windows.raid = built.raid end
  if elements.options then published_windows.options = built.options end

  return {
    ok = true,
    version = M.VERSION,
    warnings = warnings,
    config = cfg,
    theme = active,
    display = display,
    unavailable = adapter.unavailable,
    host = adapter,
    layout = layout.place(cfg.layout_preset, display.scale),
    menubar = menu,
    hud = {
      health = bars.health,
      nano = bars.nano,
      xp = bars.xp,
      shortcut_axis = shortcuts.axis,
      hotkey_text = shortcuts.hotkey_text,
      shortcuts = shortcuts,
      compass = compass,
      target = target,
    },
    windows = published_windows,
    raid_row_px = built.raid.row_px,
    elements = elements,
  }
end

function M.format_observable(session)
  local names = {}
  for id, node in pairs(session.elements) do
    if node ~= nil then names[#names + 1] = id end
  end
  table.sort(names)
  local lines = {
    "ok=1",
    "theme=" .. session.theme.id,
    "frame=" .. session.theme.frame.style,
    "frame_border=" .. tostring(session.theme.frame.border_px),
    "text=" .. session.theme.color.text,
    "density=" .. session.theme.density.id,
    "anchor=" .. session.menubar.anchor,
    "floating=" .. (session.menubar.floating and "1" or "0"),
    "fading=" .. (session.menubar.fading and "1" or "0"),
    "auto_hide=" .. (session.menubar.auto_hide and "1" or "0"),
    "rows=" .. tostring(session.menubar.rows),
    "thickness=" .. tostring(session.menubar.thickness),
    "softmenu=" .. table.concat(session.menubar.softmenu_actions, ","),
    "health=" .. fmt_num(session.hud.health),
    "nano=" .. fmt_num(session.hud.nano),
    "xp=" .. fmt_num(session.hud.xp),
    "hotkeys=" .. session.hud.hotkey_text,
    "shortcut_axis=" .. session.hud.shortcut_axis,
    "elements=" .. table.concat(names, ","),
    "unavailable=" .. table.concat(session.unavailable, ","),
    "viewport=" .. tostring(session.display.viewport_w) .. "x" .. tostring(session.display.viewport_h),
    "pixel_scale=" .. fmt_num(session.display.pixel_scale),
    "ui_scale=" .. fmt_num(session.display.scale),
    "preset=" .. session.config.layout_preset,
    "opacity=" .. fmt_num(session.config.opacity),
    "raid_row=" .. tostring(session.raid_row_px),
  }
  return table.concat(lines, "\n") .. "\n"
end

if ui and ui.define then
  ui.define("ndgui", function() return M end)
end
return M
