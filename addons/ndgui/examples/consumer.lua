-- Offline stand-in for the client. Prints the shipped observable twice-stable.
-- This file is not the test suite. It only calls ndgui.load.

local function dirname(path)
  return path:match("^(.*)/[^/]+$") or "."
end

local root = dirname(dirname(arg[0] or ""))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local ndgui = require("ndgui")
local fixture = dofile(root .. "/fixtures/session.lua")
local session = ndgui.load({
  config = fixture.config,
  snapshot = fixture.snapshot,
  input = fixture.input,
  host = fixture.host,
})
io.write(ndgui.format_observable(session))
if not session.ok then
  os.exit(1)
end
