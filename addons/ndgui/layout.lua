-- Reference layout is 1920x1080 logical pixels (1080p).
-- ui.pixel_scale_* is the client framebuffer scale and must not multiply
-- these rectangles. A 4K panel that already reports a 1080p logical
-- viewport stays at factor 1. A logical 3840x2160 viewport uses factor 2.
-- The supported band is 1080p through 5K (5120x2880). Outside that band
-- the factor clamps; the user ui_scale still multiplies after the clamp.

local M = {}

M.REF_W = 1920
M.REF_H = 1080
M.MIN_W = 1920
M.MIN_H = 1080
M.MAX_W = 5120
M.MAX_H = 2880
M.FONT_MIN = 1
M.FONT_MAX = 256

local PRESETS = {
  classic = {
    { id = "menubar", x = 640, y = 0, w = 640, h = 22 },
    { id = "health", x = 8, y = 28, w = 180, h = 16 },
    { id = "nano", x = 8, y = 48, w = 180, h = 16 },
    { id = "xp", x = 8, y = 68, w = 180, h = 12 },
    { id = "compass", x = 200, y = 28, w = 72, h = 72 },
    { id = "target", x = 284, y = 28, w = 240, h = 48 },
    { id = "shortcutbar", x = 560, y = 1020, w = 400, h = 36 },
    { id = "chat", x = 8, y = 760, w = 420, h = 220 },
    { id = "inventory", x = 1500, y = 180, w = 360, h = 480 },
    { id = "raid", x = 8, y = 100, w = 240, h = 320 },
    { id = "options", x = 620, y = 180, w = 480, h = 360 },
  },
  efficient = {
    { id = "menubar", x = 760, y = 0, w = 400, h = 22 },
    { id = "health", x = 4, y = 4, w = 140, h = 12 },
    { id = "nano", x = 4, y = 18, w = 140, h = 12 },
    { id = "xp", x = 4, y = 32, w = 140, h = 8 },
    { id = "compass", x = 148, y = 4, w = 48, h = 48 },
    { id = "target", x = 760, y = 28, w = 200, h = 36 },
    { id = "shortcutbar", x = 700, y = 1040, w = 360, h = 28 },
    { id = "chat", x = 4, y = 860, w = 320, h = 160 },
    { id = "inventory", x = 1580, y = 80, w = 300, h = 400 },
    { id = "raid", x = 4, y = 60, w = 200, h = 240 },
    { id = "options", x = 700, y = 200, w = 400, h = 300 },
  },
  wide = {
    { id = "menubar", x = 480, y = 0, w = 960, h = 22 },
    { id = "health", x = 8, y = 28, w = 280, h = 18 },
    { id = "nano", x = 8, y = 50, w = 280, h = 18 },
    { id = "xp", x = 8, y = 72, w = 280, h = 14 },
    { id = "compass", x = 300, y = 28, w = 96, h = 96 },
    { id = "target", x = 410, y = 28, w = 360, h = 56 },
    { id = "shortcutbar", x = 360, y = 1000, w = 640, h = 40 },
    { id = "chat", x = 8, y = 700, w = 560, h = 260 },
    { id = "inventory", x = 1400, y = 140, w = 480, h = 560 },
    { id = "raid", x = 8, y = 110, w = 300, h = 400 },
    { id = "options", x = 520, y = 160, w = 640, h = 420 },
  },
}

function M.scale_px(value, scale)
  if scale == nil then scale = 1 end
  return math.floor(value * scale + 0.5)
end

-- ui.font_size accepts a logical size from 1 through 256.
function M.font_px(base, scale)
  local n = M.scale_px(base, scale)
  if n < M.FONT_MIN then return M.FONT_MIN end
  if n > M.FONT_MAX then return M.FONT_MAX end
  return n
end

function M.resolution(viewport, pixel_scale, user_scale)
  local w = viewport and tonumber(viewport.w) or M.REF_W
  local h = viewport and tonumber(viewport.h) or M.REF_H
  if not w or w <= 0 then w = M.REF_W end
  if not h or h <= 0 then h = M.REF_H end
  local px = tonumber(pixel_scale) or 1
  if px <= 0 then px = 1 end
  local user = tonumber(user_scale) or 1
  if user <= 0 then user = 1 end
  local factor = math.min(w / M.REF_W, h / M.REF_H)
  local min_factor = math.min(M.MIN_W / M.REF_W, M.MIN_H / M.REF_H)
  local max_factor = math.min(M.MAX_W / M.REF_W, M.MAX_H / M.REF_H)
  if factor < min_factor then factor = min_factor end
  if factor > max_factor then factor = max_factor end
  return {
    viewport_w = w,
    viewport_h = h,
    pixel_scale = px,
    factor = factor,
    user_scale = user,
    scale = user * factor,
    band = "1080p-5k",
  }
end

-- Framebuffer pixels for a reference logical size. pixel_scale is applied
-- once, after the layout scale, so client scaling is not applied twice.
function M.physical_px(logical_base, display)
  return M.scale_px(logical_base, display.scale) * display.pixel_scale
end

function M.presets()
  return { "classic", "efficient", "wide" }
end

function M.place(preset, scale)
  local bases = PRESETS[preset] or PRESETS.classic
  if scale == nil then scale = 1 end
  local out = {}
  for i = 1, #bases do
    local base = bases[i]
    out[i] = {
      id = base.id,
      x = M.scale_px(base.x, scale),
      y = M.scale_px(base.y, scale),
      w = M.scale_px(base.w, scale),
      h = M.scale_px(base.h, scale),
    }
  end
  return out
end

if ui and ui.define then
  ui.define("ndgui.layout", function() return M end)
end
return M
