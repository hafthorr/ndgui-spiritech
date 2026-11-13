-- Config document. Encode/decode uses a Lua literal in an empty environment.
-- core.storage values are capped at 4096 UTF-8 bytes; storage_ok checks that.

local function import(name)
  if ui and ui.require then return ui.require(name) end
  return require(name)
end

local catalog = import("ndgui.catalog")
local theme = import("ndgui.theme")

local M = {}

M.STORAGE_MAX = 4096

M.ELEMENT_IDS = {
  "menubar", "health", "nano", "xp", "compass", "target", "shortcutbar",
  "inventory", "chat", "raid", "options",
}

M.QUICK_OPTION_IDS = {
  "lock_wear", "lock_shortcutbar", "lock_raidbar", "inspect",
  "auto_afk", "social", "show_all_names",
}

M.QUICK_OPTION_LABELS = {
  lock_wear = "Lock Wear",
  lock_shortcutbar = "Lock Shortcutbar",
  lock_raidbar = "Lock RaidBar",
  inspect = "Inspect",
  auto_afk = "Auto-AFK",
  social = "Social",
  show_all_names = "Show All Names",
}

local ELEMENT_SET = {}
for i = 1, #M.ELEMENT_IDS do ELEMENT_SET[M.ELEMENT_IDS[i]] = true end

local QUICK_SET = {}
for i = 1, #M.QUICK_OPTION_IDS do QUICK_SET[M.QUICK_OPTION_IDS[i]] = true end

local ANCHORS = { top = true, bottom = true, left = true, right = true }
local PRESETS = { classic = true, efficient = true, wide = true }
local RAID = { standard = true, compact = true }
local ORIENT = { horizontal = true, vertical = true }

local function clamp01(n, fallback)
  n = tonumber(n)
  if not n then return fallback end
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
end

local function is_array(t)
  local n = 0
  local max = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
    if k > max then max = k end
  end
  return n == max
end

local function serialize(value)
  local kind = type(value)
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "0"
    end
    if value % 1 == 0 and math.abs(value) < 1e15 then
      return string.format("%.0f", value)
    end
    return string.format("%.17g", value)
  elseif kind == "string" then
    return string.format("%q", value)
  elseif kind == "boolean" then
    return value and "true" or "false"
  elseif kind == "table" then
    if is_array(value) then
      local parts = {}
      for i = 1, #value do
        parts[i] = serialize(value[i])
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
    local keys = {}
    for k in pairs(value) do
      if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
      parts[i] = keys[i] .. "=" .. serialize(value[keys[i]])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end

function M.normalize(raw)
  raw = type(raw) == "table" and raw or {}
  local warnings = {}

  local theme_id = raw.theme
  if not theme.get(theme_id) then
    if theme_id ~= nil then
      warnings[#warnings + 1] = "theme '" .. tostring(theme_id) .. "' is not in v1; using dovvetech"
    end
    theme_id = "dovvetech"
  end

  local anchor = "top"
  local floating = false
  local fading = false
  local auto_hide = false
  local menu_enabled = nil
  if type(raw.menubar) == "table" then
    if ANCHORS[raw.menubar.anchor] then anchor = raw.menubar.anchor end
    floating = raw.menubar.floating and true or false
    fading = raw.menubar.fading and true or false
    auto_hide = raw.menubar.auto_hide and true or false
    if raw.menubar.enabled ~= nil then
      menu_enabled = raw.menubar.enabled and true or false
    end
  end

  local elements = {}
  for i = 1, #M.ELEMENT_IDS do
    local id = M.ELEMENT_IDS[i]
    local value = true
    if type(raw.elements) == "table" and raw.elements[id] ~= nil then
      value = raw.elements[id] and true or false
    elseif id == "menubar" and menu_enabled ~= nil then
      value = menu_enabled
    end
    elements[id] = value
  end

  local quick = {}
  for i = 1, #M.QUICK_OPTION_IDS do
    local id = M.QUICK_OPTION_IDS[i]
    local value = false
    if type(raw.quick_options) == "table" and raw.quick_options[id] ~= nil then
      value = raw.quick_options[id] and true or false
    end
    quick[id] = value
  end

  local softmenu = {}
  if type(raw.softmenu) == "table" then
    for i = 1, #raw.softmenu do
      local slot = raw.softmenu[i]
      if type(slot) == "table" and catalog.get(slot.action) and tonumber(slot.slot) then
        softmenu[#softmenu + 1] = {
          slot = tonumber(slot.slot),
          action = slot.action,
        }
      end
    end
    table.sort(softmenu, function(a, b) return a.slot < b.slot end)
  end

  local order = { "main", "alt" }
  local hidden = {}
  local orientation = "horizontal"
  if type(raw.shortcutbar) == "table" then
    if ORIENT[raw.shortcutbar.orientation] then
      orientation = raw.shortcutbar.orientation
    end
    if type(raw.shortcutbar.order) == "table" and #raw.shortcutbar.order > 0 then
      order = {}
      for i = 1, #raw.shortcutbar.order do
        if type(raw.shortcutbar.order[i]) == "string" then
          order[#order + 1] = raw.shortcutbar.order[i]
        end
      end
      if #order == 0 then order = { "main", "alt" } end
    end
    if type(raw.shortcutbar.hidden) == "table" then
      for k, v in pairs(raw.shortcutbar.hidden) do
        if type(k) == "string" and v then hidden[k] = true end
      end
    end
  end

  local layout_preset = raw.layout_preset
  if not PRESETS[layout_preset] then layout_preset = "classic" end
  local raid_preset = "standard"
  if type(raw.raid) == "table" and RAID[raw.raid.preset] then
    raid_preset = raw.raid.preset
  end

  local user_scale = tonumber(raw.ui_scale) or 1
  if user_scale <= 0 then user_scale = 1 end

  local cfg = {
    version = 1,
    theme = theme_id,
    opacity = clamp01(raw.opacity, 1),
    ui_scale = user_scale,
    layout_preset = layout_preset,
    menubar = {
      anchor = anchor,
      floating = floating,
      fading = fading,
      auto_hide = auto_hide,
      enabled = elements.menubar,
    },
    elements = elements,
    quick_options = quick,
    softmenu = softmenu,
    shortcutbar = {
      orientation = orientation,
      order = order,
      hidden = hidden,
    },
    raid = { preset = raid_preset },
  }
  return cfg, warnings
end

function M.default()
  return (M.normalize({}))
end

function M.encode(cfg)
  return "return " .. serialize(M.normalize(cfg)) .. "\n"
end

-- The client sandbox has no load(). Parse the subset serialize() writes.
local parse_value

local function skip_ws(s, i)
  while i <= #s and s:sub(i, i):match("%s") do
    i = i + 1
  end
  return i
end

local function parse_string(s, i)
  i = i + 1
  local out = {}
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then
      return table.concat(out), i + 1
    end
    if c ~= "\\" then
      out[#out + 1] = c
      i = i + 1
    else
      local n = s:sub(i + 1, i + 1)
      local escaped = ({
        a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v",
        ['"'] = '"', ["\\"] = "\\",
      })[n]
      if escaped then
        out[#out + 1] = escaped
        i = i + 2
      elseif n:match("%d") then
        local digits = s:sub(i + 1):match("^%d%d?%d?")
        out[#out + 1] = string.char(tonumber(digits) % 256)
        i = i + 1 + #digits
      else
        error("bad string escape", 0)
      end
    end
  end
  error("unterminated string", 0)
end

local function parse_table(s, i)
  i = skip_ws(s, i + 1)
  local t = {}
  local index = 1
  if s:sub(i, i) == "}" then
    return t, i + 1
  end
  while i <= #s do
    i = skip_ws(s, i)
    local rest = s:sub(i)
    local ident, eq = rest:match("^([A-Za-z_][A-Za-z0-9_]*)(%s*=)")
    local key
    if ident and eq then
      key = ident
      i = skip_ws(s, i + #ident + #eq)
    end
    local value
    value, i = parse_value(s, i)
    if key then
      t[key] = value
    else
      t[index] = value
      index = index + 1
    end
    i = skip_ws(s, i)
    local sep = s:sub(i, i)
    if sep == "}" then
      return t, i + 1
    end
    if sep ~= "," then
      error("expected comma in table", 0)
    end
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "}" then
      return t, i + 1
    end
  end
  error("unterminated table", 0)
end

parse_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '"' then
    return parse_string(s, i)
  end
  if c == "{" then
    return parse_table(s, i)
  end
  local rest = s:sub(i)
  if rest:sub(1, 4) == "true" then return true, i + 4 end
  if rest:sub(1, 5) == "false" then return false, i + 5 end
  if rest:sub(1, 3) == "nil" then return nil, i + 3 end
  local num = rest:match("^%-?%d+%.%d+[eE][%+%-]?%d+")
    or rest:match("^%-?%d+[eE][%+%-]?%d+")
    or rest:match("^%-?%d+%.%d+")
    or rest:match("^%-?%d+")
  if num then return tonumber(num), i + #num end
  error("expected value", 0)
end

local function parse_literal(text)
  local body = text:match("^%s*return%s+(.+)$") or text
  local value, nxt = parse_value(body, 1)
  nxt = skip_ws(body, nxt)
  if nxt <= #body then error("trailing config text", 0) end
  return value
end

function M.decode(text)
  if type(text) ~= "string" then return nil, "config must be text" end
  local ok, value
  if type(load) == "function" then
    local chunk, err = load(text, "ndgui-config", "t", {})
    if not chunk then return nil, err end
    ok, value = pcall(chunk)
    if not ok then return nil, value end
  else
    ok, value = pcall(parse_literal, text)
    if not ok then return nil, value end
  end
  if type(value) ~= "table" then return nil, "config must be a table" end
  return M.normalize(value)
end

function M.storage_ok(text)
  return type(text) == "string" and #text <= M.STORAGE_MAX
end

function M.set_quick_option(cfg, id, value)
  if not QUICK_SET[id] then return false, "unknown quick option" end
  if type(cfg.quick_options) ~= "table" then cfg.quick_options = {} end
  cfg.quick_options[id] = value and true or false
  return true
end

function M.set_element(cfg, id, enabled)
  if not ELEMENT_SET[id] then return false, "unknown element" end
  if type(cfg.elements) ~= "table" then cfg.elements = {} end
  cfg.elements[id] = enabled and true or false
  if id == "menubar" then
    if type(cfg.menubar) ~= "table" then cfg.menubar = {} end
    cfg.menubar.enabled = cfg.elements[id]
  end
  return true
end

if ui and ui.define then
  ui.define("ndgui.config", function() return M end)
end
return M
