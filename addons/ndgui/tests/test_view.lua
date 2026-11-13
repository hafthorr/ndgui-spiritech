-- Overlay (notum.ndgui) under the mock host: menubar-only, bottom edge, no bar widgets.
-- Run: lua tests/test_view.lua
local here = ((arg[0] or ""):gsub("\\", "/"):match("^(.*)/tests/[^/]+$") or ".")
package.path = here .. "/tests/?.lua;" .. package.path
local Mock = require("mock_host")
local addons = here .. "/.."
local core = here .. "/../../Packages/Core"
local fail = 0
local function check(cond, msg) print((cond and "PASS " or "FAIL ") .. msg); if not cond then fail = fail + 1 end end

local H = Mock.new(addons, core, { width = 2000, height = 1334 })
local ok, err = pcall(H.load_package, "ndgui")
check(ok, "overlay loads: " .. tostring(err))
H.tick()
local root = H.root
check(root ~= nil, "overlay mounted a root")
check(H.find(root, "menubar") == nil, "overlay menubar is off (control-center provider owns the strip)")
check(H.find(root, "xp_caption") == nil and H.find(root, "health_bar") == nil, "overlay draws no status bars")
check((root.h or 0) == 0, "overlay takes no screen space (h=" .. tostring(root.h) .. ")")
check(#H.subs == 0, "overlay does not subscribe to vitals")

print(fail == 0 and "ALL PASS" or ("FAILURES " .. fail)); os.exit(fail == 0 and 0 or 1)
