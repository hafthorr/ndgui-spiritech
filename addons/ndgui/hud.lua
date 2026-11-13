-- Bars, compass, target, and shortcut bars.
-- Hotkey labels depend only on the slot index. Slot 10 is "0", matching
-- the native hotbar note that row ten is labelled zero. Hide and reorder
-- do not change another bar's labels.

local function import(name)
  if ui and ui.require then return ui.require(name) end
  return require(name)
end

local layout = import("ndgui.layout")

local M = {}

local LABELS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }
local CELL = 40

function M.fraction(current, max)
  current = tonumber(current) or 0
  max = tonumber(max) or 0
  if max <= 0 then return 0 end
  local value = current / max
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

-- CharacterBar: use current/max when either number is present so an
-- over-max snapshot still clamps. Native fraction is the fallback.
function M.bar_fraction(bar)
  if type(bar) ~= "table" then return 0 end
  if bar.current ~= nil or bar.maximum ~= nil or bar.max ~= nil then
    local max = bar.maximum
    if max == nil then max = bar.max end
    return M.fraction(bar.current, max)
  end
  if type(bar.fraction) == "number" then
    return M.fraction(bar.fraction, 1)
  end
  return 0
end

function M.hotkey_label(slot_index)
  local n = tonumber(slot_index) or 1
  if n < 1 then n = 1 end
  n = math.floor(n)
  return LABELS[((n - 1) % 10) + 1]
end

function M.bars(snapshot)
  snapshot = type(snapshot) == "table" and snapshot or {}
  return {
    health = M.bar_fraction(snapshot.health),
    nano = M.bar_fraction(snapshot.nano),
    xp = M.bar_fraction(snapshot.xp),
  }
end

local function slot_list(bar)
  local slots = {}
  local raw = bar.slots or {}
  local count = #raw
  if count < 1 then count = 10 end
  for i = 1, count do
    slots[i] = {
      index = i,
      hotkey = M.hotkey_label(i),
      item = type(raw[i]) == "table" and raw[i].item or nil,
    }
  end
  return slots
end

function M.shortcuts(cfg, snapshot, theme, scale)
  snapshot = type(snapshot) == "table" and snapshot or {}
  scale = scale or 1
  local bar_px = theme and theme.density.bar_px or 16
  local orientation = "horizontal"
  if cfg.shortcutbar and cfg.shortcutbar.orientation == "vertical" then
    orientation = "vertical"
  end
  local hidden = (cfg.shortcutbar and cfg.shortcutbar.hidden) or {}
  local by_id = {}
  local source = snapshot.shortcuts or {}
  for i = 1, #source do
    local bar = source[i]
    if type(bar) == "table" and type(bar.id) == "string" then
      by_id[bar.id] = bar
    end
  end
  local seen = {}
  local ordered = {}
  local function push(id)
    if seen[id] or hidden[id] or not by_id[id] then return end
    seen[id] = true
    ordered[#ordered + 1] = by_id[id]
  end
  local order = (cfg.shortcutbar and cfg.shortcutbar.order) or {}
  for i = 1, #order do push(order[i]) end
  for i = 1, #source do
    if type(source[i]) == "table" then push(source[i].id) end
  end

  local bars = {}
  local groups = {}
  for i = 1, #ordered do
    local slots = slot_list(ordered[i])
    local n = #slots
    local long = layout.scale_px(CELL * n, scale)
    local short = layout.scale_px(bar_px, scale)
    if short < 1 then short = 1 end
    local rect
    if orientation == "vertical" then
      rect = { x = 0, y = 0, w = short, h = long }
    else
      rect = { x = 0, y = 0, w = long, h = short }
    end
    local labels = {}
    for s = 1, #slots do labels[s] = slots[s].hotkey end
    bars[i] = {
      id = ordered[i].id,
      slots = slots,
      rect = rect,
      axis = orientation,
    }
    groups[i] = ordered[i].id .. ":" .. table.concat(labels, ",")
  end

  return {
    orientation = orientation,
    axis = orientation,
    bars = bars,
    hotkey_text = table.concat(groups, ";"),
  }
end

function M.compass(snapshot)
  snapshot = type(snapshot) == "table" and snapshot or {}
  local compass = snapshot.compass or {}
  local heading = tonumber(compass.heading) or 0
  heading = heading % 360
  return { id = "compass", heading = heading }
end

function M.target(snapshot)
  snapshot = type(snapshot) == "table" and snapshot or {}
  local target = snapshot.target or {}
  local health = M.bar_fraction(target.health)
  return {
    id = "target",
    name = target.name or "",
    health_fraction = health,
  }
end

if ui and ui.define then
  ui.define("ndgui.hud", function() return M end)
end
return M
