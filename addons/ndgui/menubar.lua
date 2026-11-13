-- One control row. Thickness is the theme menu row times layout scale.
-- Top and bottom are horizontal; left and right are vertical. The short
-- side is always that single row.

local function import(name)
  if ui and ui.require then return ui.require(name) end
  return require(name)
end

local catalog = import("ndgui.catalog")
local config = import("ndgui.config")
local layout = import("ndgui.layout")

local M = {}

-- ASSUMPTION: idle fade is 0.35. ui.fade itself is a boolean.
M.IDLE_FADE = 0.35
M.FLOAT_MARGIN = 12
M.BUTTON_PITCH = 28
M.BUTTON_PAD = 8

function M.catalog()
  return catalog.list()
end

function M.assign(cfg, slot, action_id)
  if not catalog.get(action_id) then
    return false, "unknown softmenu action"
  end
  slot = tonumber(slot)
  if not slot then return false, "slot required" end
  cfg.softmenu = cfg.softmenu or {}
  for i = 1, #cfg.softmenu do
    if cfg.softmenu[i].slot == slot then
      cfg.softmenu[i].action = action_id
      return true
    end
  end
  cfg.softmenu[#cfg.softmenu + 1] = { slot = slot, action = action_id }
  table.sort(cfg.softmenu, function(a, b) return a.slot < b.slot end)
  return true
end

function M.action_ids(cfg)
  local ids = {}
  local slots = cfg.softmenu or {}
  for i = 1, #slots do
    local item = catalog.get(slots[i].action)
    if item then ids[#ids + 1] = item.id end
  end
  return ids
end

local function quick_view(cfg)
  local out = {}
  for i = 1, #config.QUICK_OPTION_IDS do
    local id = config.QUICK_OPTION_IDS[i]
    out[i] = {
      id = id,
      label = config.QUICK_OPTION_LABELS[id],
      value = cfg.quick_options[id] and true or false,
    }
  end
  return out
end

function M.build(cfg, theme, ctx)
  ctx = ctx or {}
  local scale = ctx.scale or 1
  local screen = ctx.screen or { w = layout.REF_W, h = layout.REF_H }
  local hovered = ctx.hovered and true or false
  local thickness = layout.scale_px(theme.density.menu_row_px, scale)
  if thickness < 1 then thickness = 1 end
  local anchor = cfg.menubar.anchor
  local horizontal = anchor == "top" or anchor == "bottom"
  local floating = cfg.menubar.floating and true or false
  local margin = 0
  if floating then
    margin = layout.scale_px(M.FLOAT_MARGIN, scale)
  end
  local fading = cfg.menubar.fading and true or false
  local auto_hide = cfg.menubar.auto_hide and true or false
  local main_visible = not (auto_hide and not hovered)
  local fade_opacity = 1
  if fading and not hovered then fade_opacity = M.IDLE_FADE end

  local buttons = {}
  local function add(id, kind, label, action)
    buttons[#buttons + 1] = {
      id = id,
      kind = kind,
      label = label,
      action = action,
      row = 1,
    }
  end
  if main_visible then
    add("char", "main", "Char", nil)
    add("info", "main", "Info", nil)
    add("misc", "main", "Misc", nil)
  end
  local actions = M.action_ids(cfg)
  for i = 1, #actions do
    local item = catalog.get(actions[i])
    add("soft:" .. item.id, "softmenu", item.label, item.id)
  end
  add("quick_options", "quick_options", "Quick Options", nil)

  local length = layout.scale_px(#buttons * M.BUTTON_PITCH + M.BUTTON_PAD, scale)
  if length < thickness then length = thickness end

  local x, y, w, h
  if anchor == "bottom" then
    w, h = length, thickness
    x = math.floor((screen.w - w) / 2)
    y = screen.h - h - margin
  elseif anchor == "left" then
    w, h = thickness, length
    x = margin
    y = math.floor((screen.h - h) / 2)
  elseif anchor == "right" then
    w, h = thickness, length
    x = screen.w - w - margin
    y = math.floor((screen.h - h) / 2)
  else
    w, h = length, thickness
    x = math.floor((screen.w - w) / 2)
    y = margin
  end

  local opacity = cfg.opacity or 1
  local drawn = fade_opacity * opacity
  if drawn < 0 then drawn = 0 end
  if drawn > 1 then drawn = 1 end

  return {
    enabled = cfg.elements.menubar and true or false,
    anchor = anchor,
    floating = floating,
    fading = fading,
    auto_hide = auto_hide,
    thickness = thickness,
    rows = 1,
    axis = horizontal and "horizontal" or "vertical",
    rect = { x = x, y = y, w = w, h = h },
    fade_opacity = fade_opacity,
    drawn_opacity = drawn,
    main_menu_visible = main_visible,
    softmenu_actions = actions,
    buttons = buttons,
    quick_options = quick_view(cfg),
    color = {
      menu = theme.color.menu,
      text = theme.color.text,
      accent = theme.color.accent,
    },
  }
end

if ui and ui.define then
  ui.define("ndgui.menubar", function() return M end)
end
return M
