-- Package-local DarkTech buttons: library:// slices instead of GFX_NDGUI_BTN* atlas ids.
-- Call ui.require("notum.ndgui-lib/button").skin_tree(root) after ui.load of a package root.
ui.define("notum.ndgui-lib/button", function()
	local M = {}
	local CAP = 4
	local HEIGHTS = { 19, 20, 22, 23, 24, 26, 28, 32 }

	local function nearest_height(h)
		h = tonumber(h) or 22
		local best = 22
		local best_d = 1000
		for i = 1, #HEIGHTS do
			local cand = HEIGHTS[i]
			local d = math.abs(cand - h)
			if d < best_d or (d == best_d and cand > best) then
				best, best_d = cand, d
			end
		end
		return best
	end

	local function slice_uri(h, state, part)
		return string.format("library://notum.ndgui-lib/buttons/btn%d_%s_%s.png", h, state, part)
	end

	local function set_slices(chrome, h, state)
		local left = ui.find(chrome, "ndgui_btn_l")
		local mid = ui.find(chrome, "ndgui_btn_m")
		local right = ui.find(chrome, "ndgui_btn_r")
		ui.image(left, slice_uri(h, state, "left"))
		ui.image(mid, slice_uri(h, state, "middle"))
		ui.image(right, slice_uri(h, state, "right"))
		ui.limits(left, CAP, h, CAP, h)
		ui.limits(mid, 0, h, -1, h)
		ui.limits(right, CAP, h, CAP, h)
	end

	local function button_height(btn)
		local h = ui.desired_height(btn)
		if not h or h <= 0 then
			h = ui.minimum_height(btn)
		end
		if not h or h <= 0 then
			h = 22
		end
		return nearest_height(h)
	end

	local function bind_wrap(wrap)
		if wrap._ndgui_btn_bound then
			return
		end
		local chrome = ui.find(wrap, "ndgui_chrome")
		local btn
		for i = 1, ui.child_count(wrap) do
			local kid = ui.child(wrap, i)
			if kid.tag == "Button" or (kid.name and kid.name ~= "ndgui_chrome" and kid.tag ~= "BitmapView") then
				if kid.tag == "Button" or kid.label or kid.font_size then
					btn = kid
					break
				end
			end
		end
		if not btn then
			for i = 1, ui.child_count(wrap) do
				local kid = ui.child(wrap, i)
				if kid.name ~= "ndgui_chrome" then
					btn = kid
					break
				end
			end
		end
		if not btn then
			return
		end
		local h = button_height(btn)
		local state = "raised"
		local function show(next_state)
			state = next_state
			set_slices(chrome, h, state)
		end
		show(ui.is_selected(btn) and "selected" or "raised")
		ui.on_pointer(btn, function(phase)
			if ui.is_selected(btn) then
				show("selected")
				return
			end
			if phase == "start" then
				show("pressed")
			elseif phase == "hover" or phase == "move" then
				if state ~= "pressed" then
					show("hover")
				end
			elseif phase == "end" or phase == "cancel" then
				show("raised")
			end
		end)
		wrap._ndgui_btn_bound = true
	end

	local function walk(view, fn)
		fn(view)
		local n = ui.child_count(view)
		for i = 1, n do
			walk(ui.child(view, i), fn)
		end
	end

	-- Skin every ndgui_btnwrap under root (wrappers from square_buttons.py).
	function M.skin_tree(root)
		if not root then
			return
		end
		walk(root, function(view)
			if view.name == "ndgui_btnwrap" then
				local ok = pcall(bind_wrap, view)
				if not ok then
					-- Missing chrome / unexpected XML: leave the flat Button usable.
					ui.tooltip(view, view.tooltip)
				end
			end
		end)
	end

	-- Lit pin art without GFX_NDGUI_PIN_ON.
	function M.bind_pin(pin_button, pin_on_view)
		if not pin_button then
			return
		end
		local function sync()
			local on = ui.is_selected(pin_button)
			if pin_on_view then
				ui.visible(pin_on_view, on)
			end
		end
		sync()
		ui.on_click(pin_button, sync)
		-- Docking / restore also flips selected; keep the overlay in sync.
		ui.on_update(sync)
	end

	M.nearest_height = nearest_height
	M.slice_uri = slice_uri
	return M
end)
