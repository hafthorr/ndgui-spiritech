-- The zone notice role (prk.zone-notice): the stock "entering <zone>" lines and the suppression gas
-- countdown, in ndGUI colours. It also tells the HUD where you are (bus topic "zone"), which no
-- other API names: game.character only has a playfield number.
ui.define("intel.zone", function()
	local Bus = ui.require("notum.ndgui-lib/bus")
	local Z = {}

	local HOLD_MS, FADE_MS, LINE_GAP = 4000, 1000, 10
	local FACE, SUB, SHADOW = "#E6EEF5", "#7F9BB0", "#000000"
	local SHADOW_OFFSET = 1
	local COUNTDOWN_TOP = 0.7
	local OPEN, GAS = "#6CE07A", "#E0C040"
	local root, showing, countdown

	local function text(value, color, size)
		local view = ui.load("zone_text.xml")
		ui.text(view, value)
		ui.text_color(view, color)
		if size then
			ui.font_size(view, size)
		end
		ui.add(root, view)
		return view
	end

	local function hide()
		if not showing then
			return
		end
		for _, line in ipairs(showing.lines) do
			ui.destroy(line.shadow)
			ui.destroy(line.face)
		end
		showing = nil
	end

	local function show(reading)
		hide()
		if #reading.lines == 0 then
			return
		end
		local lines = {}
		for index, value in ipairs(reading.lines) do
			local size = index == 1 and 22 or 15
			lines[index] = { shadow = text(value, SHADOW, size), face = text(value, index == 1 and FACE or SUB, size) }
		end
		showing = { born = reading.now_ms, lines = lines }
		Bus.publish("zone", { name = reading.lines[1] or "", sub = reading.lines[2] or "" })
	end

	local function hide_countdown()
		if countdown then
			ui.destroy(countdown.shadow)
			ui.destroy(countdown.face)
			countdown = nil
		end
	end

	local function apply_countdown(reading)
		if reading.countdown == "" then
			hide_countdown()
			return
		end
		local color = reading.opens_to_attack and OPEN or GAS
		if not countdown then
			countdown = { shadow = text(reading.countdown, SHADOW), face = text(reading.countdown, color) }
		else
			ui.text(countdown.shadow, reading.countdown)
			ui.text(countdown.face, reading.countdown)
			ui.text_color(countdown.face, color)
		end
		local phase = reading.countdown_ms % 1000
		local into_second = phase == 0 and 0 or 1 - phase / 1000
		local dimmest = reading.countdown_ms > 1000 and 0.1 or 0
		local opacity = dimmest + (1 - dimmest) * (1 - into_second * into_second)
		local x = math.floor(math.max(0, (reading.width - ui.desired_width(countdown.face)) / 2))
		local y = math.floor(reading.height * COUNTDOWN_TOP)
		ui.place(countdown.face, x, y)
		ui.place(countdown.shadow, x + SHADOW_OFFSET, y + SHADOW_OFFSET)
		ui.opacity(countdown.face, opacity)
		ui.opacity(countdown.shadow, opacity)
	end

	function Z.mount(layer)
		root = layer
	end

	function Z.apply(reading)
		apply_countdown(reading)
		if reading.arrived then
			show(reading)
		end
		if not showing then
			return
		end
		local elapsed = reading.now_ms - showing.born
		if elapsed >= HOLD_MS + FADE_MS then
			hide()
			return
		end
		local opacity = elapsed > HOLD_MS and math.max(0, 1 - (elapsed - HOLD_MS) / FADE_MS) or 1
		local block = 0
		for index, line in ipairs(showing.lines) do
			block = block + ui.desired_height(line.face) + (index > 1 and LINE_GAP or 0)
		end
		local y = math.floor(math.max(0, (reading.height - block) / 2))
		for _, line in ipairs(showing.lines) do
			local x = math.floor(math.max(0, (reading.width - ui.desired_width(line.face)) / 2))
			ui.place(line.face, x, y)
			ui.place(line.shadow, x + SHADOW_OFFSET, y + SHADOW_OFFSET)
			ui.opacity(line.face, opacity)
			ui.opacity(line.shadow, opacity)
			y = y + ui.desired_height(line.face) + LINE_GAP
		end
	end

	return Z
end)
