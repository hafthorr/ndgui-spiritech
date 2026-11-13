ui.define("ndgui.view", function()
  local hud = ui.require("ndgui.hud")

  local DESTINATIONS = {
    char = "prk.stats",
    info = "prk.info",
    inventory = "prk.inventory",
    chat = "prk.chat.default",
    raid = "prk.raid",
    options = "prk.skills",
  }

  -- HP/NP/XP are drawn by the notum.ndgui-status-bars provider (prk.status-bars role),
  -- which replaces the stock bars. Set true to also draw overlay bars (no provider selected).
  local OVERLAY_BARS = false
  -- The bottom strip is drawn by notum.ndgui-control-center (prk.control-center role).
  -- Set true to bring back the overlay's own Char/Info/Misc/Quick Options buttons.
  local OVERLAY_MENUBAR = false
  local BAR_IDS = OVERLAY_BARS and { "health", "nano", "xp" } or {}
  local BAR_LABEL = { health = "HP", nano = "NP", xp = "XP" }
  local BAR_TEMPLATE = { health = "health.xml", nano = "nano.xml", xp = "xp.xml" }

  local function bar_reading(bars, key)
    if type(bars) ~= "table" then
      return nil
    end
    local named = bars[key]
    if type(named) == "table" then
      return named
    end
    for _, item in pairs(bars) do
      if type(item) == "table" and (item.key == key or item.id == key) then
        return item
      end
    end
    return nil
  end

  local function from_character(character, key)
    if type(character) ~= "table" then
      return nil
    end
    if key == "health" then
      return { current = character.health, maximum = character.max_health }
    end
    if key == "nano" then
      return { current = character.nano, maximum = character.max_nano }
    end
    return nil
  end

  local function caption_for(id, reading)
    local name = BAR_LABEL[id] or id
    if type(reading) ~= "table" then
      return name .. "  -- / --"
    end
    local current = reading.current
    local maximum = reading.maximum or reading.max
    if current ~= nil and maximum ~= nil then
      return name .. "  " .. tostring(current) .. " / " .. tostring(maximum)
    end
    return name .. "  -- / --"
  end

  local function paint_bar(entry, theme, reading)
    if entry.width then
      ui.size(entry.inner, entry.width, 23)
    end
    ui.progress(entry.inner, hud.bar_fraction(reading))
    ui.text(entry.caption, caption_for(entry.id, reading))
    ui.font_size(entry.caption, math.max(12, theme.density.font_px))
    ui.text_color(entry.caption, "#FFFFFF")
  end

  local function toggle_destination(key)
    if not key then
      return
    end
    local ok, dest = pcall(ui.destinations.require, key)
    if ok and dest then
      ui.destinations.toggle(dest)
    end
  end

  local function host_size(root, session)
    local w = ui.parent_width(root)
    local h = ui.parent_height(root)
    if not w or w < 1 then
      w = session.display.viewport_w
    end
    if not h or h < 1 then
      h = session.display.viewport_h
    end
    if not w or w < 1 then w = 1920 end
    if not h or h < 1 then h = 1080 end
    return w, h
  end

  local View = {}

  -- Layout is XML flow: root (vertical) = menu slot row + bar column.
  -- ui.place only works on the root; children of a stacked View all land at 0,0.
  function View.mount(session)
    local theme = session.theme
    local root = ui.load("root.xml")
    ui.root(root)
    ui.align(root, "start", "start")
    ui.place(root, 0, 0)
    ui.click_through(root, true)
    local menu_slot = ui.find(root, "ndgui_menu_slot")
    local bar_column = ui.find(root, "ndgui_bars")

    local chrome = { bars = {}, readings = {}, buttons = {} }

    if OVERLAY_MENUBAR and session.elements.menubar then
      local frag = ui.load("menubar.xml")
      local menu = ui.find(frag, "menubar")
      ui.add(menu_slot, frag)
      ui.click_through(frag, false)
      for i = 1, #session.menubar.buttons do
        local spec = session.menubar.buttons[i]
        local item = ui.load("button.xml")
        local button = ui.find(item, "button")
        ui.add(menu, item)
        ui.text(button, spec.label)
        ui.font_size(button, math.max(12, theme.density.font_px))
        ui.text_color(button, theme.color.text)
        local dest = DESTINATIONS[spec.id] or DESTINATIONS[spec.action]
        ui.on_click(button, function()
          toggle_destination(dest)
        end)
        spec._item = item
        spec._button = button
      end
      chrome.menu_frag = frag
      chrome.menu = menu
      chrome.buttons = session.menubar.buttons
    end

    for i = 1, #BAR_IDS do
      local id = BAR_IDS[i]
      if session.elements[id] then
        local node = ui.load(BAR_TEMPLATE[id])
        ui.add(bar_column, node)
        ui.click_through(node, false)
        chrome.bars[id] = {
          id = id,
          node = node,
          inner = ui.find(node, id .. "_bar"),
          caption = ui.find(node, id .. "_caption"),
        }
      end
    end

    local last_w, last_h = 0, 0

    local function layout(force)
      local w, h = host_size(root, session)
      if not force and w == last_w and h == last_h then
        return
      end
      last_w, last_h = w, h

      local menu_h = 0
      if chrome.menu then
        menu_h = math.max(26, theme.density.menu_row_px + 4)
        ui.size(menu_slot, w, menu_h)
        ui.size(chrome.menu_frag, w, menu_h)
        local count = math.max(1, #chrome.buttons)
        local pitch = math.max(72, math.min(120, math.floor(w / (count * 4))))
        ui.size(chrome.menu, pitch * count, menu_h)
        for i = 1, #chrome.buttons do
          local spec = chrome.buttons[i]
          ui.size(spec._button, pitch, menu_h)
        end
      else
        ui.visible(menu_slot, false)
      end

      local bar_w = math.max(320, math.min(480, math.floor(w * 0.25)))
      local shown = 0
      for i = 1, #BAR_IDS do
        local entry = chrome.bars[BAR_IDS[i]]
        if entry then
          entry.width = bar_w
          paint_bar(entry, theme, chrome.readings[entry.id])
          shown = shown + 1
        end
      end
      local column_h = shown > 0 and (6 + shown * 26) or 0
      ui.visible(bar_column, shown > 0)
      ui.size(bar_column, bar_w + 32, column_h)
      -- Root covers only the strip + bar column, never the whole screen.
      -- Classic ndGUI: the slim menubar rests on the bottom edge.
      ui.size(root, w, menu_h + column_h)
      ui.place(root, 0, math.max(0, h - menu_h - column_h))
    end

    local function apply(character, bars)
      for i = 1, #BAR_IDS do
        local id = BAR_IDS[i]
        chrome.readings[id] = bar_reading(bars, id) or from_character(character, id)
        local entry = chrome.bars[id]
        if entry then
          paint_bar(entry, theme, chrome.readings[id])
        end
      end
    end

    local function show_error(prefix, err)
      local entry = chrome.bars.xp or chrome.bars.health
      if entry and entry.caption then
        ui.text(entry.caption, prefix .. tostring(err))
      end
    end

    layout(true)
    ui.on_update(function()
      layout(false)
    end)

    if #BAR_IDS > 0 and game and game.character and game.character.subscribe then
      local ok, err = pcall(game.character.subscribe, "self", "level,health", function(_, character, _, bars)
        local applied, apply_err = pcall(apply, character, bars)
        if not applied then
          show_error("ERR ", apply_err)
        end
      end)
      if not ok then
        show_error("subscribe: ", err)
      end
    elseif #BAR_IDS > 0 then
      show_error("", "game.character.subscribe unavailable")
    end

    return { root = root, chrome = chrome }
  end

  return View
end)
