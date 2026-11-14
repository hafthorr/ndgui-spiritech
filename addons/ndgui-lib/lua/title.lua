-- Window titles that also reach the docked page. Since the Nov 2026 client a dockable window has two
-- titles: window_title on the floating frame and rollup_title on the compact page Core shows when it
-- docks in the right-side column. Core writes rollup_title once, at creation; titles that change
-- (NCU (2/10), Inventory, Missions (2) - 1:20...) go through set() so both stay the same.
local M = {}

function M.set(root, text)
	ui.text(ui.find(root, "window_title"), text)
	local ok, docked = pcall(ui.find, root, "rollup_title")
	if ok and docked then
		ui.text(docked, text)
	end
end

return M
