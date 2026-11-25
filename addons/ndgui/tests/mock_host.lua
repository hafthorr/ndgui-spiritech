-- Offline mock of the Spiritech package host. Loads a package directory the way the
-- client does: package.xml <Script> order, <Requires> libraries with <Modules root>,
-- sandboxed env (no debug/load/require), real Core/vitals.lua, stubbed core.move.
local M = {}

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a"); f:close(); return s
end

function M.new(addons_dir, core_dir, opts)
  opts = opts or {}
  local H = { nodes = {}, updates = {}, subs = {}, calls = {} }
  local n = 0
  local function node(name, file, tag) n = n + 1; local v = { id = n, name = name, file = file, tag = tag, kids = {} }; return v end
  local function parse(dir, file)
    local s = assert(read(dir .. "/" .. file), "missing xml " .. dir .. "/" .. file)
    local top, stack = nil, {}
    for close, tag, attrs, selfc in s:gmatch("<(/?)([%w_]+)([^>]-)(/?)>") do
      if tag ~= "root" and tag ~= "xml" then
        if close == "/" then table.remove(stack)
        else
          local v = node(attrs:match('name="([^"]*)"'), file, tag)
          for k, val in attrs:gmatch('([%w_]+)="([^"]*)"') do v[k] = v[k] or val end
          if #stack > 0 then table.insert(stack[#stack].kids, v) else top = v end
          if selfc ~= "/" then stack[#stack + 1] = v end
        end
      end
    end
    return assert(top, "empty xml " .. file)
  end
  local function find(v, name)
    if v.name == name then return v end
    for _, k in ipairs(v.kids) do local r = find(k, name); if r then return r end end
  end
  H.find = find

  local defs, cache = {}, {}
  local ui = { compass = {}, storage = {}, destinations = {} }
  H.ui = ui
  local pkgdir
  function ui.define(name, fn) defs[name] = fn end
  function ui.require(name)
    if cache[name] == nil then
      assert(defs[name], "missing module " .. name)
      cache[name] = defs[name]()
    end
    return cache[name]
  end
  function ui.load(f)
    local id, rest = f:match("^library://([^/]+)/(.+)$")
    if id then
      -- like the client: a library asset is a plain file name at the library root (no folders)
      assert(not rest:find("/", 1, true), "A UI package asset must be a local file name of the expected type: " .. f)
      local dir = assert(H.lib_folder and H.lib_folder(id), "unknown library " .. id)
      return parse(dir, rest)
    end
    return parse(pkgdir, f)
  end
  -- like the client: a missing view is an error, not nil
  function ui.find(v, name) assert(v, "ui.find nil view"); return (assert(find(v, name), "Missing UI view: " .. tostring(name))) end
  function ui.add(p, c)
    assert(p and c, "ui.add nil")
    if c.parent then
      for i, k in ipairs(c.parent.kids) do if k == c then table.remove(c.parent.kids, i); break end end
    end
    c.parent = p
    table.insert(p.kids, c)
  end
  function ui.root(v) H.root = v end
  function ui.on_update(cb) assert(type(cb) == "function", "on_update arg 1 must be function"); H.updates[#H.updates + 1] = cb end
  function ui.text(v, t) assert(v, "ui.text nil view"); v.text = t end
  function ui.tooltip(v, t) assert(v, "ui.tooltip nil view"); v.tooltip = t end
  function ui.progress(v, f)
    assert(v, "progress nil")
    assert(type(f) == "number" and f >= 0 and f <= 1, "bad fraction " .. tostring(f))
    v.progress = f
  end
  function ui.size(v, w, h) assert(v, "size nil"); v.w, v.h = w, h end
  function ui.limits(v, a, b, c, d) assert(v, "limits nil"); v.min_w, v.min_h, v.max_w, v.max_h = a, b, c, d end
  -- size / placement queries Core's docking reads (numbers, like the client)
  for _, k in ipairs({ "desired_width", "desired_height", "minimum_width", "minimum_height", "maximum_width", "maximum_height",
    "offset_x", "offset_y" }) do
    ui[k] = ui[k] or function(v) assert(v, k .. " nil view"); return (k:find("height") and v.h) or (k:find("width") and v.w) or 0 end
  end
  ui.horizontal_alignment = ui.horizontal_alignment or function() return "start" end
  ui.vertical_alignment = ui.vertical_alignment or function() return "start" end
  function ui.place(v, x, y) assert(v, "place nil"); v.x, v.y = x, y end
  function ui.visible(v, b) assert(v, "visible nil"); v.visible = b end
  function ui.text_color(v, c) assert(v, "text_color nil"); v.color = c end
  H.now, H.clicks = 1000000, {}
  if not ui.time then ui.time = function() return H.now end end
  if not ui.destroy then function ui.destroy(v)
    assert(v, "destroy nil")
    if v.parent then for i, k in ipairs(v.parent.kids) do if k == v then table.remove(v.parent.kids, i); break end end end
    v.parent, v.destroyed = nil, true
  end end
  if not ui.selected then function ui.selected(v, b) assert(v, "selected nil"); v.selected = b end end
  function ui.graphic_tint(v, c) assert(v, "graphic_tint nil"); v.tint = c end
  ui.parent_width = function() return opts.width or 2000 end
  if opts.settings then -- client 0.3.5+: package Options (only keys the package.xml declares)
    local declared = {}
    ui.settings = {
      toggle = function(k) assert(declared[k], "undeclared setting " .. k); return opts.settings[k] == true end,
      number = function(k) assert(declared[k], "undeclared setting " .. k); return opts.settings[k] or 0 end,
      choice = function(k) assert(declared[k], "undeclared setting " .. k); return opts.settings[k] or "" end,
      on_change = function(cb) H.settings_changed = cb end,
      declare = function(manifest) for k in manifest:gmatch('key="([^"]+)"') do declared[k] = true end end,
    }
  end
  ui.parent_height = function() return opts.height or 1334 end
  ui.pixel_scale_x = function() return 1 end
  ui.pixel_scale_y = function() return 1 end
  for _, k in ipairs({ "align", "click_through", "fill_color", "font_size", "text_alignment", "on_click",
    "visual_selected", "bind", "action", "icon", "content", "badge", "fade", "image", "caption", "corner", "center" }) do
    ui[k] = function(v, binding) assert(v, k .. " nil view"); H.calls[k] = (H.calls[k] or 0) + 1; if k == "bind" then v.bound = binding elseif k == "corner" or k == "center" or k == "badge" then v[k] = binding end end
  end
  ui.borders = function(v, l, t, r, b) assert(v and l and t and r and b, "borders"); v.borders = { l, t, r, b } end
  ui.local_x = function(v) assert(v, "local_x nil"); return v.x or 0 end
  ui.local_y = function(v) assert(v, "local_y nil"); return v.y or 0 end
  H.state_handlers = {}
  ui.on_state = function(v, cb) assert(v and type(cb) == "function", "on_state"); H.state_handlers[v] = cb end
  -- remember presentation calls the target panels assert on
  ui.image = function(v, src) assert(v, "image nil view"); v.image = src end
  ui.fill_color = function(v, c) assert(v, "fill_color nil view"); v.fill = c end
  ui.font_size = function(v, n) assert(v and type(n) == "number" and n >= 1 and n <= 256, "font_size"); v.font = n end
  ui.opacity = function(v, a) assert(v and a >= 0 and a <= 1, "opacity"); v.opacity = a end
  H.stopped = 0
  ui.stop_updates = function() H.stopped = H.stopped + 1 end
  -- keep click handlers so tests can press buttons
  ui.on_click = function(v, cb) assert(v and type(cb) == "function", "on_click"); H.calls.on_click = (H.calls.on_click or 0) + 1; v.on_click = cb end
  ui.in_combat = function() return false end
  ui.storage.read = function() return nil end
  ui.storage.write = function() end
  if opts.grant_destinations then
    ui.destinations.require = function(key) return { key = key } end
  else
    ui.destinations.require = function() error("ungranted") end
  end
  ui.destinations.toggle = function() end
  ui.destinations.close = function() end
  ui.destinations.is_open = function() return false end
  ui.menu = setmetatable({}, { __index = function(_, k)
    return function(anchor, label, checked, cb) assert(anchor, "menu." .. k .. " nil anchor"); H.calls["menu." .. k] = (H.calls["menu." .. k] or 0) + 1
      if k == "add" and H.menu_items then H.menu_items[#H.menu_items + 1] = { label = label, checked = checked, cb = cb } end
      return H.calls["menu." .. k] end end })
  ui.on_value_changed = function(v, cb) assert(v and type(cb) == "function") end
  ui.on_lockdown = function(cb) assert(type(cb) == "function") end
  ui.compass.graphic_width = function() return 512 end
  for _, k in ipairs({ "offset", "begin", "sprite", "finish" }) do
    ui.compass[k] = function(v) assert(v, "compass." .. k .. " nil"); H.calls["compass." .. k] = (H.calls["compass." .. k] or 0) + 1 end
  end
  H.moves, H.state, H.releases = {}, {}, {}
  ui.define("core.move", function() return { attach = function(v, o) H.moves[#H.moves + 1] = { view = v, options = o or {} }; return v end,
    place = function(v, x, y) ui.place(v, x, y) end } end)
  -- ui.state: per-view scalar store (poses, ndGUI lock flags)
  ui.state = { read = function(v, k) assert(v and type(k) == "string"); return (H.state[v] or {})[k] or "" end,
    write = function(v, k, value) assert(v and type(k) == "string" and type(value) == "string"); H.state[v] = H.state[v] or {}; H.state[v][k] = value end }
  ui.child_count = function(v) assert(v, "child_count nil"); return #v.kids end
  ui.child = function(v, i) return assert(v.kids[i], "child out of range") end
  ui.on_pointer_release = function(v, button, cb) assert(v and type(cb) == "function")
    assert(button == "right", "Pointer release supports right; use on_click for left activation."); H.releases[#H.releases + 1] = { view = v, button = button, cb = cb } end
  -- ui.menu.add remembers its last callback so tests can invoke a menu entry
  -- core.hud_column (Nov 2026 patch): the real Core file, so the column size follows the client
  do
    local chunk = loadfile(core_dir .. "/hud_column.lua", "t", setmetatable({ ui = ui }, { __index = _G }))
    if chunk then chunk() end
  end
  -- ui.docking (Nov 2026 patch): Core's dockable registers every window with the right-side column
  H.docked_views = {}
  ui.docking = { available = function() return true end,
    register = function(view, floating_header, compact_header, preview, cb)
      assert(view and floating_header and compact_header and preview and type(cb) == "function", "docking.register args")
      assert(view.name == "window" or view.tag, "docking.register needs the window root")
      H.docked_views[#H.docked_views + 1] = view; H.dock_callbacks = H.dock_callbacks or {}; H.dock_callbacks[#H.docked_views] = cb end,
    restore = function(view, docked, order) assert(view and type(docked) == "boolean" and type(order) == "number") end }
  -- docking host calls (Nov 2026 patch), checked like the client documents them
  H.rollup_hosts = {}
  if not ui.attach then
    ui.attach = function(owner, panel, layout) assert(owner and panel and type(layout) == "function", "ui.attach args")
      ui.add(owner, panel); panel.attached_layout = layout end
  end
  ui.rollup_host = function(panel, body, width)
    assert(panel and body and type(width) == "number", "ui.rollup_host args")
    local function inside(v) if v == body then return true end for _, k in ipairs(v.kids or {}) do if inside(k) then return true end end return false end
    assert(inside(panel), "rollup_host body must be inside the panel")
    assert(#H.rollup_hosts == 0, "one rollup host per controller")
    H.rollup_hosts[#H.rollup_hosts + 1] = { panel = panel, body = body, width = width } end
  ui.requested_visible = ui.requested_visible or function(v) return v.visible ~= false end
  ui.minimum_height = ui.minimum_height or function(v) return v.h or 0 end
  ui.opacity = function(v, o) assert(v and type(o) == "number" and o >= 0 and o <= 1, "ui.opacity 0..1") v.opacity = o end
  H.menu_items = {}
  H.placements = {}
  ui.define("core.placement", function() return { attach = function(view, options)
    local p = { view = view, options = options or {}, field = options and options.field, moved = false, changed = function(self) self.moved = true end,
      defaults = function() end, restore = function(self) self.restored = (self.restored or 0) + 1 end, capture = function() end }
    H.placements[#H.placements + 1] = p; return p end } end)

  local game = { control_center = { bind_aggdef = function(v) assert(v, "bind_aggdef nil") end }, character = { subscribe = function(_, _, cb)
    assert(type(cb) == "function"); H.subs[#H.subs + 1] = cb; return {} end } }
  -- game.combat: tests feed events through H.combat(events)
  H.combat_subs = {}
  game.combat = { subscribe = function(kinds, cb) assert(type(kinds) == "string" and type(cb) == "function", "combat.subscribe")
    H.combat_subs[#H.combat_subs + 1] = cb; return #H.combat_subs end, unsubscribe = function() end }
  function H.combat(events) for _, cb in ipairs(H.combat_subs) do cb({ reset = false }, events) end end

  local env = { ui = ui, game = game, math = math, string = string, table = table, pairs = pairs, ipairs = ipairs,
    type = type, tostring = tostring, tonumber = tonumber, pcall = pcall, error = error, select = select,
    next = next, assert = assert, setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget,
    rawset = rawset, print = print, os = { time = os.time, clock = os.clock, date = os.date } }
  env._G = env
  H.env = env

  local function run(path)
    local chunk = assert(loadfile(path, "t", env))
    local ok, err = pcall(chunk)
    if not ok then error("PACKAGE FAILED in " .. path .. ": " .. tostring(err), 0) end
  end
  run(core_dir .. "/vitals.lua")

  -- opts.loose: smoke-load packages built on the wider Core (windows, rollups, NCU).
  -- Every Core module definition is registered; unknown ui.*/game.* calls are permissive no-ops.
  if opts.loose then
    local any
    any = setmetatable({}, { __index = function() return any end, __call = function() return any end,
      __concat = function() return "" end, __len = function() return 0 end })
    local function permissive(t)
      return setmetatable(t, { __index = function() return any end })
    end
    ui.shared_layout = function(name) return parse(core_dir, name) end
    ui.preference = permissive({ read = function() return "" end, write = function() end })
    for _, k in ipairs({ "chosen_width", "chosen_height", "width", "height", "x", "y", "local_x", "local_y" }) do
      ui[k] = function() return 300 end
    end
    if opts.map_surface then game.map_surface = opts.map_surface end
    permissive(ui)
    permissive(game)
    local skip = { ["modules.lua"] = true, ["ui.lua"] = true, ["vitals.lua"] = true, ["move.lua"] = true, ["placement.lua"] = true }
    local p = io.popen('ls "' .. core_dir .. '"')
    for fn in p:lines() do
      if fn:match("%.lua$") and not skip[fn] then
        local chunk = loadfile(core_dir .. "/" .. fn, "t", env)
        if chunk then pcall(chunk) end
      end
    end
    p:close()
  end

  -- Library ids -> folder: scan addon folders for package ids.
  local libs, folders = {}, {}
  function H.lib_folder(id) return folders[id] end
  function H.index_libraries()
    local p = io.popen('ls "' .. addons_dir .. '"')
    for folder in p:lines() do
      local manifest = read(addons_dir .. "/" .. folder .. "/package.xml")
      local id = manifest and manifest:match('<Package id="([^"]+)"')
      local root = manifest and manifest:match('<Modules root="([^"]+)"')
      if id and root then libs[id] = addons_dir .. "/" .. folder .. "/" .. root; folders[id] = addons_dir .. "/" .. folder end
    end
    p:close()
  end
  H.index_libraries()

  function H.load_package(folder)
    pkgdir = addons_dir .. "/" .. folder
    local pkg = assert(read(pkgdir .. "/package.xml"), "no package.xml in " .. folder)
    H.manifest = pkg
    assert(pkg:match('<Package id="[a-z0-9]+%.[a-z0-9.%-]+"'), "package id must be lowercase namespaced")
    assert(not (pkg:find("<Provides", 1, true) and (pkg:find("<View", 1, true) or pkg:find("<Window", 1, true))),
      "cannot mix provider roles and standalone windows")
    for lib in pkg:gmatch('<Requires package="([^"]+)"') do
      local root = assert(libs[lib], "missing library " .. lib)
      local p = io.popen('ls "' .. root .. '"')
      for file in p:lines() do
        local modname = file:match("^([a-z0-9_]+)%.lua$")
        if modname then
          local src = assert(read(root .. "/" .. file))
          local factory = assert(load(src, "=" .. lib .. "/" .. file, "t", env))
          ui.define(lib .. "/" .. modname, factory)
        end
      end
      p:close()
    end
    for src in pkg:gmatch('<Script src="([^"]+)"') do
      assert(not src:find("/", 1, true), "Script src must be a local file name: " .. src)
      run(pkgdir .. "/" .. src)
    end
    for src in pkg:gmatch('<InteractionScript src="([^"]+)"') do
      assert(read(pkgdir .. "/" .. src), "missing interaction script " .. src)
    end
    return env
  end

  function H.tick() for _, u in ipairs(H.updates) do u() end end
  return H
end

return M
