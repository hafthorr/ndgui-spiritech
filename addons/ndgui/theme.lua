-- Original theme tokens. Roles follow the public ndGUI families.
-- Hex values are not samples of classic texture packs.

local M = {}

M.V1_IDS = { "dovvetech", "darktech", "darktech_mini", "adaptive" }

local THEMES = {
  dovvetech = {
    id = "dovvetech",
    name = "Classic Dovvetech",
    color = {
      panel = "#24384a",
      panel_alt = "#2e4a60",
      border = "#8fb4cc",
      text = "#e7f2f8",
      text_dim = "#a9c6d6",
      accent = "#e07a2f",
      health = "#d24b4b",
      nano = "#4c92d4",
      xp = "#e0b341",
      bar_track = "#152430",
      menu = "#1b2c3b",
      focus = "#f2c14e",
    },
    frame = {
      style = "beveled",
      border_px = 2,
      radius_px = 0,
      header_px = 18,
    },
    density = {
      id = "standard",
      row_px = 22,
      bar_px = 16,
      menu_row_px = 22,
      font_px = 12,
      gap_px = 4,
      padding_px = 4,
      raid_row_px = 22,
      raid_row_compact_px = 15,
    },
  },
  darktech = {
    id = "darktech",
    name = "DarkTech",
    color = {
      panel = "#0e141b",
      panel_alt = "#16202a",
      border = "#3d6f9a",
      text = "#c5d7e6",
      text_dim = "#7f9bb0",
      accent = "#3d8fd4",
      health = "#c44747",
      nano = "#2f7ec4",
      xp = "#c6a24e",
      bar_track = "#080c10",
      menu = "#0a1016",
      focus = "#6cb6ff",
    },
    frame = {
      style = "pronounced",
      border_px = 3,
      radius_px = 0,
      header_px = 20,
    },
    density = {
      id = "regular",
      row_px = 26,
      bar_px = 18,
      menu_row_px = 24,
      font_px = 13,
      gap_px = 5,
      padding_px = 6,
      raid_row_px = 24,
      raid_row_compact_px = 16,
    },
  },
  darktech_mini = {
    id = "darktech_mini",
    name = "DarkTech Mini",
    color = {
      panel = "#141a20",
      panel_alt = "#1b242c",
      border = "#5c7c90",
      text = "#d0dde6",
      text_dim = "#8aa0b0",
      accent = "#67c3d4",
      health = "#d05a5a",
      nano = "#3d92c8",
      xp = "#d1b15e",
      bar_track = "#0c1014",
      menu = "#10161c",
      focus = "#9ad7e4",
    },
    frame = {
      style = "hairline",
      border_px = 1,
      radius_px = 0,
      header_px = 14,
    },
    density = {
      id = "mini",
      row_px = 16,
      bar_px = 8,
      menu_row_px = 16,
      font_px = 11,
      gap_px = 2,
      padding_px = 2,
      raid_row_px = 16,
      raid_row_compact_px = 11,
    },
  },
  adaptive = {
    id = "adaptive",
    name = "Adaptive",
    color = {
      panel = "#121418",
      panel_alt = "#1c2026",
      border = "#d7dde4",
      text = "#f4f7fa",
      text_dim = "#b7c0c8",
      accent = "#ffb020",
      health = "#ff5d5d",
      nano = "#59a6ff",
      xp = "#ffe08a",
      bar_track = "#08090b",
      menu = "#181c22",
      focus = "#ffd56a",
    },
    frame = {
      style = "flat",
      border_px = 1,
      radius_px = 3,
      header_px = 18,
    },
    density = {
      id = "adaptive",
      row_px = 24,
      bar_px = 12,
      menu_row_px = 20,
      font_px = 15,
      gap_px = 6,
      padding_px = 6,
      raid_row_px = 20,
      raid_row_compact_px = 13,
    },
  },
}

local function copy_map(src)
  local out = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      out[k] = copy_map(v)
    else
      out[k] = v
    end
  end
  return out
end

function M.ids()
  local out = {}
  for i = 1, #M.V1_IDS do
    out[i] = M.V1_IDS[i]
  end
  return out
end

function M.get(id)
  local theme = THEMES[id]
  if not theme then return nil end
  return copy_map(theme)
end

if ui and ui.define then
  ui.define("ndgui.theme", function() return M end)
end
return M
