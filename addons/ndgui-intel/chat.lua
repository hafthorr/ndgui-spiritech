-- The chat content role (prk.chat): the stock chat lines, plus what Sniff picks out of them goes
-- on the bus for the HUD (ndgui-intel hud.lua). Lines that raised an alert get a marker in front;
-- the HUD answers "ndgui ..." commands with its banner (a chat role cannot add lines of its own).
ui.define("intel.chat", function()
	local Bus = ui.require("notum.ndgui-lib/bus")
	local Sniff = ui.require("intel.sniff")
	local C = {}

	local colors = {
		system = "#FFFF00",
		vicinity = "#FFFF45",
		emote = "#FF0099",
		channel = "#FFFFFF",
		team = "#63E689",
		tell = "#00FFFF",
		sent_tell = "#7FB8FF",
		["local"] = "#8A8F96",
	}
	local MARK = { tell = "#4FB3E8", name = "#E0C040", word = "#E08A3C" }
	local separators = { emote = " ", shout = " shouts: " }

	local content, entry, target
	local sniff = Sniff.new()
	local self_name
	local words, words_raw = {}, nil

	local function text(line, value, color)
		ui.chat.text(line, value, color or "", false)
	end

	local function color_of(message)
		if message.sent then
			return colors.sent_tell
		end
		return message.color ~= "" and message.color or colors[message.kind]
	end

	local function load_words()
		local raw = Bus.get("words")
		if raw ~= words_raw then
			words_raw, words = raw, {}
			for word in raw:gmatch("[^,]+") do
				word = word:gsub("^%s+", ""):gsub("%s+$", "")
				if word ~= "" then
					words[#words + 1] = string.lower(word)
				end
			end
		end
		return words
	end

	local function present(message, mark)
		local line = message.line
		ui.chat.style(line, color_of(message), message.font_size, false)
		ui.chat.font_family(line, message.font_family)
		if mark then
			text(line, "> ", MARK[mark])
		end
		if message.time ~= "" then
			text(line, "[" .. message.time .. "] ")
		end
		if not message.structured then
			ui.chat.part(line, "message")
		else
			if message.channel ~= "" then
				ui.chat.channel(line, "[" .. message.channel .. "]")
				text(line, " ")
			end
			if message.kind == "tell" then
				text(line, message.sent and "To [" or "[")
				ui.chat.part(line, "sender")
				text(line, "]: ")
			elseif message.sender ~= "" then
				ui.chat.part(line, "sender")
				text(line, separators[message.kind] or ": ")
			end
			ui.chat.part(line, "body")
		end
		ui.chat.commit(line)
	end

	function C.mount(root)
		content = ui.find(root, "chat_content")
		entry = ui.find(content, "chat_entry")
		target = ui.find(content, "chat_target")
		-- the chat role gets no game.character ("Character information is unavailable for this
		-- package"): the HUD VM publishes your name as bus state "self_name"
	end

	function C.chat_present(messages)
		local name = Bus.get("self_name")
		self_name = name ~= "" and name or nil
		local context = { self_name = self_name, words = load_words() }
		for _, message in ipairs(messages) do
			context.now = message.time_ms ~= 0 and message.time_ms or ui.time()
			local ok, found = pcall(sniff.read, message, context)
			local mark
			if ok then
				for _, event in ipairs(found) do
					Bus.publish(event[1], event[2])
					if event[1] == "alert" then
						mark = event[2].k
					end
				end
			end
			present(message, mark)
		end
	end

	function C.chat_output(name, color)
		local tint = color ~= "" and color or "#FFFF45"
		ui.text(target, name ~= "" and name or "Vicinity")
		ui.text_color(target, tint)
		ui.text_color(ui.find(content, "chat_input"), tint)
	end

	function C.chat_visual(borderless)
		ui.chat.borders(not borderless)
	end

	function C.chat_state(show_entry, show_target)
		ui.visible(entry, show_entry)
		ui.visible(target, show_target)
	end

	return C
end)
