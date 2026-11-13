-- Inventory, chat, raid/group, and options. Chrome is copied from the
-- active theme at build time so a theme switch does not edit each window.

local function import(name)
  if ui and ui.require then return ui.require(name) end
  return require(name)
end

local layout = import("ndgui.layout")
local config = import("ndgui.config")

local M = {}

function M.chrome(theme, scale)
  scale = scale or 1
  return {
    style = theme.frame.style,
    border_px = layout.scale_px(theme.frame.border_px, scale),
    radius_px = layout.scale_px(theme.frame.radius_px, scale),
    header_px = layout.scale_px(theme.frame.header_px, scale),
    text = theme.color.text,
    panel = theme.color.panel,
    border = theme.color.border,
    font_px = layout.font_px(theme.density.font_px, scale),
    padding_px = layout.scale_px(theme.density.padding_px, scale),
  }
end

function M.raid_row_px(preset, theme, scale)
  local base = theme.density.raid_row_px
  if preset == "compact" then
    base = theme.density.raid_row_compact_px
  end
  local n = layout.scale_px(base, scale or 1)
  if n < 1 then n = 1 end
  return n
end

local function quick_copy(cfg)
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

function M.build(cfg, theme, scale, snapshot)
  scale = scale or 1
  snapshot = type(snapshot) == "table" and snapshot or {}
  local raid_preset = cfg.raid.preset
  local members = snapshot.group or {}
  return {
    inventory = {
      id = "inventory",
      title = "Inventory",
      chrome = M.chrome(theme, scale),
    },
    chat = {
      id = "chat",
      title = "Chat",
      chrome = M.chrome(theme, scale),
    },
    raid = {
      id = "raid",
      title = "Raid/Group",
      preset = raid_preset,
      row_px = M.raid_row_px(raid_preset, theme, scale),
      members = #members,
      chrome = M.chrome(theme, scale),
    },
    options = {
      id = "options",
      title = "Options",
      theme = theme.id,
      opacity = cfg.opacity,
      ui_scale = cfg.ui_scale,
      layout_preset = cfg.layout_preset,
      quick_options = quick_copy(cfg),
      chrome = M.chrome(theme, scale),
    },
  }
end

if ui and ui.define then
  ui.define("ndgui.windows", function() return M end)
end
return M
