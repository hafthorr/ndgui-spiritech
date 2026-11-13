-- Host adapter.
-- Probe names are the Spiritech exports (client/docs/lua-api). A missing
-- function is reported unavailable and never aborts package load.
-- A bound function that throws is caught so one bad call cannot unwind load.

local M = {}

M.PROBES = {
  "game.character.subscribe",
  "game.targeting.subscribe",
  "game.team.subscribe",
  "ui.fade",
  "ui.fill_color",
  "ui.font_size",
  "ui.opacity",
  "ui.parent_height",
  "ui.parent_width",
  "ui.pixel_scale_x",
  "ui.pixel_scale_y",
  "ui.place",
  "ui.progress",
  "ui.storage.read",
  "ui.storage.write",
  "ui.text_color",
}

local function lookup(env, path)
  local cur = env
  for part in string.gmatch(path, "[^%.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[part]
  end
  if type(cur) ~= "function" then return nil end
  return cur
end

function M.from_environment(env)
  local flat = {}
  if type(env) ~= "table" then return flat end
  for i = 1, #M.PROBES do
    local name = M.PROBES[i]
    local fn = lookup(env, name)
    if fn then flat[name] = fn end
  end
  return flat
end

function M.attach(host)
  host = type(host) == "table" and host or {}
  local bound = {}
  local unavailable = {}
  for i = 1, #M.PROBES do
    local name = M.PROBES[i]
    if type(host[name]) == "function" then
      bound[name] = host[name]
    else
      unavailable[#unavailable + 1] = name
    end
  end
  table.sort(unavailable)
  local adapter = { unavailable = unavailable }
  function adapter.call(name, ...)
    local fn = bound[name]
    if type(fn) ~= "function" then
      return false, "unavailable"
    end
    local packed = { pcall(fn, ...) }
    if not packed[1] then
      return false, "error"
    end
    return true, packed[2]
  end
  return adapter
end

-- Prefer a successful host read. parent_width/height require a view in the
-- export; ASSUMPTION: nil means "unattached, use the viewport". A throw
-- keeps the fallback instead of aborting.
function M.read_display(adapter, fallback)
  fallback = fallback or {}
  local w = tonumber(fallback.w) or 1920
  local h = tonumber(fallback.h) or 1080
  local px = tonumber(fallback.pixel_scale) or 1
  local py = px
  if adapter then
    local okx, vx = adapter.call("ui.pixel_scale_x")
    local oky, vy = adapter.call("ui.pixel_scale_y")
    local okw, vw = adapter.call("ui.parent_width")
    local okh, vh = adapter.call("ui.parent_height")
    if okx and tonumber(vx) and tonumber(vx) > 0 then px = tonumber(vx) end
    if oky and tonumber(vy) and tonumber(vy) > 0 then py = tonumber(vy) end
    if not (okx and tonumber(vx) and tonumber(vx) > 0) and oky and tonumber(vy) and tonumber(vy) > 0 then
      px = tonumber(vy)
    end
    if okw and tonumber(vw) and tonumber(vw) > 0 then w = tonumber(vw) end
    if okh and tonumber(vh) and tonumber(vh) > 0 then h = tonumber(vh) end
  end
  if px <= 0 then px = 1 end
  if py <= 0 then py = px end
  return { w = w, h = h, pixel_scale = px, pixel_scale_y = py }
end

if ui and ui.define then
  ui.define("ndgui.host", function() return M end)
end
return M
