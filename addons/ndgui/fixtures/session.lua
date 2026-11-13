-- Shared fixture for the offline consumer. 3840x2160 is a 4K logical
-- viewport at pixel scale 1, so layout scale is 2. A client that already
-- folded 4K into a 1080p logical viewport is covered by the unit tests.

local function bar(id)
  local slots = {}
  for i = 1, 10 do
    slots[i] = { item = "" }
  end
  return { id = id, slots = slots }
end

return {
  config = {
    theme = "dovvetech",
    opacity = 0.85,
    ui_scale = 1,
    layout_preset = "classic",
    menubar = {
      anchor = "top",
      floating = true,
      fading = true,
      auto_hide = true,
      enabled = true,
    },
    elements = {
      menubar = true,
      health = true,
      nano = true,
      xp = true,
      compass = false,
      target = true,
      shortcutbar = true,
      inventory = false,
      chat = true,
      raid = true,
      options = true,
    },
    softmenu = {
      { slot = 1, action = "chat" },
      { slot = 2, action = "options" },
    },
    quick_options = {
      lock_wear = false,
      lock_shortcutbar = true,
      lock_raidbar = false,
      inspect = true,
      auto_afk = false,
      social = false,
      show_all_names = true,
    },
    shortcutbar = {
      orientation = "horizontal",
      order = { "main", "alt" },
      hidden = {},
    },
    raid = { preset = "standard" },
  },
  snapshot = {
    health = { current = 150, max = 100 },
    nano = { current = -5, max = 200 },
    xp = { current = 50, max = 200 },
    target = { name = "Reet", health = { current = 10, max = 40 } },
    compass = { heading = 45 },
    shortcuts = { bar("main"), bar("alt") },
  },
  input = {
    screen = { w = 3840, h = 2160 },
    pixel_scale = 1,
    hovered = false,
  },
  host = {
    ["ui.pixel_scale_x"] = function() return 1 end,
    ["ui.pixel_scale_y"] = function() return 1 end,
    ["ui.parent_width"] = function() return 3840 end,
    ["ui.parent_height"] = function() return 2160 end,
    ["ui.fill_color"] = function() end,
    ["ui.text_color"] = function() end,
    ["ui.font_size"] = function() end,
    ["ui.opacity"] = function() end,
  },
}
