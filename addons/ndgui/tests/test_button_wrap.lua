-- ui.find and ui.child are different values in the client. Hiding a Button must still hide
-- its ndgui_btnwrap, including a wrap that started hidden (Market confirm, Skills priorities).
-- Run: lua tests/test_button_wrap.lua
local here = ((arg[0] or ""):gsub("\\", "/"):match("^(.*)/tests/[^/]+$") or ".")
local fail = 0
local function check(cond, msg)
	print((cond and "PASS " or "FAIL ") .. msg)
	if not cond then fail = fail + 1 end
end

local ui = {}
local factory
function ui.define(_, fn) factory = fn end
function ui.child_count(view) return #view.kids end
function ui.child(view, index) return view.kids[index] end
function ui.visible(view, on) view.visible = on end
function ui.selected(view, on) if on ~= nil then view.selected = on end end
function ui.load() return nil end

local function real_find(view, name)
	if view.name == name then return view end
	for i = 1, #view.kids do
		local found = real_find(view.kids[i], name)
		if found then return found end
	end
end

-- A new table every time, never the node ui.child returns. Missing names raise, as the client does.
function ui.find(view, name)
	local real = real_find(view, name)
	if not real then error("Missing UI view: " .. tostring(name)) end
	return { name = name, real = real, proxy = true }
end

assert(loadfile(here .. "/../ndgui-lib/lua/button.lua", "t", { ui = ui, string = string, pcall = pcall, ipairs = ipairs, pairs = pairs, next = next, type = type, tonumber = tonumber, math = math }))()
local Button = factory()

local function node(name, kids)
	return { name = name, kids = kids or {}, visible = true }
end
local function chrome()
	return node("ndgui_chrome", { node("ndgui_btn_l"), node("ndgui_btn_m"), node("ndgui_btn_r") })
end
local function wrapped(name, shown)
	local wrap = node("ndgui_btnwrap", { chrome(), node(name) })
	wrap.visible = shown
	return wrap
end

local cancel = wrapped("cancel_order", true)
local confirm = wrapped("confirm_cancel", false)
local keep = wrapped("keep_order", false)
local page = node("orders_page", { node("buy_heading") })
local root = node("content", { page, cancel, confirm, keep })

local confirm_handle = ui.find(root, "confirm_cancel")
local cancel_handle = ui.find(root, "cancel_order")
local keep_handle = ui.find(root, "keep_order")
local page_handle = ui.find(root, "orders_page")
check(confirm_handle ~= real_find(root, "confirm_cancel"), "find handle is not the child handle")

ui.visible(cancel_handle, false)
ui.visible(confirm_handle, true)
ui.visible(keep_handle, true)
check(cancel.visible == false, "hiding Cancel hides its chrome")
check(confirm.visible == true, "showing Confirm shows a wrap that started hidden")
check(keep.visible == true, "showing Keep order shows its wrap")
check(confirm_handle.visible == true and cancel_handle.visible == false, "the button handle follows too")

ui.visible(page_handle, false)
check(confirm.visible == true and cancel.visible == false, "hiding a plain view does not touch button chrome")

ui.visible(confirm_handle, false)
ui.visible(cancel_handle, true)
check(confirm.visible == false and cancel.visible == true, "confirm hides and cancel comes back")

-- Market does not go through the find hook. The frames are the child handles recorded
-- under the order panel, and the button is shown with the original find.
local show_order = Button.sync_named(root, root, { "cancel_order", "confirm_cancel", "keep_order" })
show_order("cancel_order", false)
show_order("confirm_cancel", true)
show_order("keep_order", true)
check(cancel.visible == false, "sync_named hides Cancel's frame")
check(confirm.visible == true and keep.visible == true, "sync_named shows frames that started hidden")

if fail > 0 then
	print(fail .. " FAILURES")
	os.exit(1)
end
print("OK")
