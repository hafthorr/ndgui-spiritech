-- Spiritech package entry. Script src values must be local file names.
-- Modules register with ui.define from the Script list in package.xml.

local ndgui
if ui and ui.require then
  ndgui = ui.require("ndgui")
else
  ndgui = require("ndgui")
end

local globals = {}
if type(ui) == "table" then globals.ui = ui end
if type(game) == "table" then globals.game = game end

local flat = ndgui.host.from_environment(globals)
local adapter = ndgui.host.attach(flat)

local read_ok, stored = adapter.call("ui.storage.read", "config")
local config_text = nil
if read_ok and type(stored) == "string" and stored ~= "" then
  config_text = stored
end

local session = ndgui.load({
  host = flat,
  config = config_text,
})

local decode_failed = false
if config_text then
  for i = 1, #session.warnings do
    if session.warnings[i]:find("config decode failed", 1, true) then
      decode_failed = true
      break
    end
  end
end

local encoded = ndgui.config.encode(session.config)
if read_ok and ndgui.config.storage_ok(encoded) and not decode_failed then
  adapter.call("ui.storage.write", "config", encoded)
end

if not (ui and ui.load) then
  return
end

local View = ui.require("ndgui.view")
View.mount(session)
