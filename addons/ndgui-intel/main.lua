-- ndGUI Intel: chat, floating combat text and zone notice from ONE package, so they can talk.
--
-- The client runs each role of a package in its own Lua VM and all of them load this same script.
-- A VM only learns its role from the first callback it gets (chat_*, floating_text_*,
-- zone_notice_apply), but every role must mount its root while loading. So every VM mounts the same
-- root: the chat content (invisible and click-through until chat callbacks arrive) on a full-screen
-- stacked layer, which the floating texts and the zone notice draw on.
--
-- The VMs share this package's ui.storage, which ndgui-lib/bus.lua turns into a message bus:
--   chat VM  -> alerts (tells, your name, watch words), loot, raid locks, "ndgui" commands
--   zone VM  -> the zone you entered
--   HUD      the Intel strip, alert banner and the Alts / Log windows (intel.hud), drawn by ONE
--            non-chat VM: whichever holds the bus lease "hud" (renewed while it runs)
local Bus = ui.require("notum.ndgui-lib/bus")

local root = ui.load("root.xml")
ui.root(root)
local chat_content = ui.find(root, "chat_content")
pcall(ui.opacity, chat_content, 0)
pcall(ui.click_through, chat_content, true)

local ELECT_AFTER_MS = 3000 -- a VM with no chat callback by then may host the HUD
local LEASE_MS, RENEW_MS, TICK_MS = 4000, 1000, 250

local function now_ms()
	local ok, value = pcall(ui.time)
	return ok and type(value) == "number" and value or 0
end

local loaded = now_ms()
local vm = string.format("%x.%s", math.floor(loaded) % 16777216, (tostring({}):match("(%x+)$") or tostring(math.random(1, 16777215))))
local role
local modules = {}
local hud_on, next_renew, next_tick = false, 0, 0

local function module(name, mount)
	if not modules[name] then
		modules[name] = ui.require("intel." .. name)
		if mount and modules[name].mount then
			modules[name].mount(root)
		end
	end
	return modules[name]
end

local function hud_off()
	if hud_on then
		hud_on = false
		modules.hud.set_active(false)
		Bus.release("hud", vm)
	end
end

local function become(name)
	if role == name then
		return
	end
	role = name
	if name == "chat" then
		hud_off()
		ui.visible(chat_content, true)
		pcall(ui.opacity, chat_content, 1)
		pcall(ui.click_through, chat_content, false)
	else
		ui.visible(chat_content, false)
	end
	Bus.set("diag:" .. name, string.format("vm %s, role after %d ms", vm, now_ms() - loaded))
end

local function drive(now)
	now = now or now_ms()
	if role == "chat" or (role == nil and now - loaded < ELECT_AFTER_MS) then
		return
	end
	if now >= next_renew then
		next_renew = now + RENEW_MS
		local mine = Bus.lease("hud", vm, now, LEASE_MS)
		if mine and not hud_on then
			if role == nil then
				ui.visible(chat_content, false)
			end
			local ok, err = pcall(function()
				local hud = module("hud")
				hud.build(root)
				hud.set_active(true)
			end)
			if ok then
				hud_on = true
				Bus.set("diag:hud", string.format("vm %s (%s) since %d", vm, role or "?", math.floor(now)))
			else
				Bus.set("diag:hud_error", tostring(err))
				Bus.release("hud", vm)
				next_renew = now + 60000 -- don't retry every second
			end
		elseif not mine and hud_on then
			hud_off()
		end
	end
	if hud_on and now >= next_tick then
		next_tick = now + TICK_MS
		modules.hud.tick(now)
	end
end

-- ---- chat (prk.chat) ---------------------------------------------------------------------
function chat_present(messages)
	become("chat")
	module("chat", true).chat_present(messages)
end

function chat_output(name, color)
	become("chat")
	module("chat", true).chat_output(name, color)
end

function chat_visual(borderless)
	become("chat")
	module("chat", true).chat_visual(borderless)
end

function chat_state(show_entry, show_target)
	become("chat")
	module("chat", true).chat_state(show_entry, show_target)
end

-- ---- floating combat text (prk.floating-combat-text) -------------------------------------
function floating_text_spawn(events, now)
	become("fct")
	module("fct", true).spawn(events, now)
	drive()
end

function floating_text_tick(anchors, now)
	become("fct")
	module("fct", true).tick(anchors, now)
	drive()
end

-- ---- zone notice (prk.zone-notice) ---------------------------------------------------------
function zone_notice_apply(reading)
	become("zone")
	module("zone", true).apply(reading)
	drive()
end

ui.on_update(function(now)
	if role == "chat" then
		ui.stop_updates()
		return
	end
	drive(now)
end)
