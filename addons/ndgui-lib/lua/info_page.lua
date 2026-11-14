-- The Info window's page (content + lines/scroll views) and its native selection surface. The client
-- requires an Info package to declare that surface while its script loads, so ndgui-mission-hub
-- requires this at load in every VM (only the Info VM needs it) and win_info.lua uses the same views
-- when the Info role shows up.
local content = ui.load("library://notum.ndgui-lib/info_content.xml")
local page = {
	content = content,
	lines = ui.find(content, "info_lines"),
	scroll = ui.find(content, "info_scroll"),
}
page.declared = pcall(game.info.surface, page.lines, page.scroll)
return page
