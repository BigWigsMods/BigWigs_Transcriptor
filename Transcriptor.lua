
-------------------------------------------------------------------------------
-- Module Declaration
--

local plugin = BigWigs:NewPlugin("Transcriptor")
if not plugin then return end

-------------------------------------------------------------------------------
-- Locals
--

local events = nil
local logging = nil
local timer = nil

local temp = {}
local function quartiles(t)
	wipe(temp)
	for i = 1, #t do
		temp[i] = tonumber(t[i])
	end
	table.sort(temp)
	local count = #temp

	-- stupid small data sets
	if count == 0 then
		return 0, 0
	elseif count == 1 then
		return temp[1], temp[1]
	elseif count == 2 then
		return temp[1], temp[2]
	end

	local q1, q3
	if count % 2 == 0 then
		q1 = (temp[math.ceil(count/4)] + temp[math.ceil(count / 4) + 1]) / 2
		q3 = (temp[math.floor(count * .75)] + temp[math.floor(count * .75) + 1]) / 2
	else
		q1 = temp[math.ceil(count / 4)]
		q3 = temp[math.ceil(count * .75)]
	end
	return q1, q3
end

-- GLOBALS: ENABLE GameTooltip InterfaceOptionsFrame_OpenToCategory LibStub SLASH_BWTRANSCRIPTOR1 Transcriptor TranscriptDB
-------------------------------------------------------------------------------
-- Locale
--

local L = LibStub("AceLocale-3.0"):NewLocale("Big Wigs: Transcriptor", "enUS", true)
L["Transcriptor"] = true
L["Automatically start Transcriptor logging when you pull a boss and stop when you win or wipe."] = true

L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your UI."] = true
L["Transcriptor is currently using %.01f MB of memory. You should clear some logs or risk losing them."] = true

L["Start with pull timer"] = true
L["Start Transcriptor logging from a pull timer at two seconds remaining."] = true
L["Show spell cast details"] = true
L["Include some spell stats and the time between casts in the log tooltip when available."] = true
L["Stored logs (%s) - Click to delete"] = true
L["No logs recorded"] = true
L["%d stored events over %.01f seconds."] = true
L["|cff20ff20Win!|r"] = true
L["Ignored Events"] = true

L = LibStub("AceLocale-3.0"):GetLocale("Big Wigs: Transcriptor")

-------------------------------------------------------------------------------
-- Options
--

plugin.defaultDB = {
	enabled = false,
	onpull = false,
	details = false,
}

local function GetOptions()
	local logs = Transcriptor:GetAll()

	if not events then
		events = {}
		for i,v in ipairs(Transcriptor.events) do
			events[v] = v
		end
	end

	UpdateAddOnMemoryUsage()
	local mem = GetAddOnMemoryUsage("Transcriptor") / 1000
	mem = ("|cff%s%.01f MB|r"):format(mem > 60 and "ff2020" or "ffffff", mem)

	local options = {
		name = L["Transcriptor"],
		type = "group",
		args = {
			heading = {
				type = "description",
				name = L["Automatically start Transcriptor logging when you pull a boss and stop when you win or wipe."].."\n",
				fontSize = "medium",
				width = "full",
				order = 1,
			},
			enabled = {
				type = "toggle",
				name = ENABLE,
				get = function(info) return plugin.db.profile.enabled end,
				set = function(info, value)
					plugin.db.profile.enabled = value
					plugin:Disable()
					plugin:Enable()
				end,
				order = 2,
			},
			onpull = {
				type = "toggle",
				name = L["Start with pull timer"],
				desc = L["Start Transcriptor logging from a pull timer at two seconds remaining."],
				get = function(info) return plugin.db.profile.onpull end,
				set = function(info, value)
					plugin.db.profile.onpull = value
					plugin:Disable()
					plugin:Enable()
				end,
				order = 3,
			},
			details = {
				type = "toggle",
				name = L["Show spell cast details"],
				desc = L["Include some spell stats and the time between casts in the log tooltip when available."],
				get = function(info) return plugin.db.profile.details end,
				set = function(info, value) plugin.db.profile.details = value end,
				order = 4,
			},
			logs = {
				type = "group",
				inline = true,
				name = L["Stored logs (%s) - Click to delete"]:format(mem),
				func = function(info)
					local key = info.arg
					if key then
						logs[key] = nil
					end
					GameTooltip:Hide()
					collectgarbage()
				end,
				order = 10,
				width = "full",
				args = {},
			},
			ignoredEvents = {
				type = "multiselect",
				name = L["Ignored Events"],
				get = function(info, key) return TranscriptDB.ignoredEvents[key] end,
				set = function(info, key, value)
					local value = value or nil
					TranscriptDB.ignoredEvents[key] = value
					plugin.db.global.ignoredEvents[key] = value
				end,
				values = events,
				order = 20,
				width = "double",
			},
		},
	}

	for key, log in next, logs do
		if key ~= "ignoredEvents" then
			local desc = nil
			local count = log.total and #log.total or 0
			if count > 0 then
				desc = L["%d stored events over %.01f seconds."]:format(count, log.total[count]:match("^<(.-)%s"))
				if log.BOSS_KILL or (log.BigWigs_Message and log.BigWigs_Message[#log.BigWigs_Message]:find("Victory", nil, true)) then
					desc = ("%s %s"):format(L["|cff20ff20Win!|r"], desc)
				end
				if plugin.db.profile.details and log.TIMERS then
					desc = desc .. "\n"
					for event, spells in next, log.TIMERS do
						desc = desc .. "\n" .. event .. "\n"
						for spell, times in next, spells do
							-- if a spell exists in SPELL_CAST_START, don't show it's SPELL_CAST_SUCCESS data
							if event == "SPELL_CAST_START" or not log.TIMERS.SPELL_CAST_START or not log.TIMERS.SPELL_CAST_START[spell] then
								local values = {string.split(",", times)}
								local _, pull = string.split(":", tremove(values, 1))
								-- use the lower and upper quartiles to find outliers
								local q1, q3 = quartiles(values)
								if q3 > 5 then -- ignore spells with a cd of less than 6s
									local iqr = q3 - q1
									local lower = q1 - (1.5 * iqr)
									local upper = q3 + (1.5 * iqr)
									local count, total, low, high = 0, 0, tonumber(values[1]), tonumber(values[1])
									for i = 1, #values do
										values[i] = tonumber(values[i])
										local v = values[i]
										if lower <= v and v <= upper then
											count = count + 1
											total = total + v
											if v < low then low = v end
											if v > high then high = v end
										else
											values[i] = ("|cffff7f3f%s|r"):format(v) -- outlier
										end
									end
									local spellId, spellName = string.split("-", spell, 2)
									local line = ("|cfffed000%s (%d)|r | Count: |cff20ff20%d|r | Avg: |cff20ff20%.01f|r | Min: |cff20ff20%.01f|r | Max: |cff20ff20%.01f|r | From pull: |cff20ff20%.01f|r|r\n    %s\n"):format(spellName, spellId, #values + 1, total / count, low, high, pull, table.concat(values, ", "))
									desc = desc .. line
								end
							end
						end
					end
				end
			end
			options.args.logs.args[key] = {
				type = "execute",
				name = key,
				desc = desc,
				width = "full",
				arg = key,
			}
		end
	end
	if not next(options.args.logs.args) then
		options.args.logs.args["no_logs"] = {
			type = "description",
			name = "\n"..L["No logs recorded"].."\n",
			fontSize = "medium",
			width = "full",
		}
	end

	return options
end

plugin.subPanelOptions = {
	key = "Big Wigs: Transcriptor",
	name = L["Transcriptor"],
	options = GetOptions,
}

-------------------------------------------------------------------------------
-- Initialization
--

function plugin:BigWigs_ProfileUpdate()
	self:Disable()
	self:Enable()
end

function plugin:OnPluginEnable()
	-- can't set a default global table as a plugin :(
	if not self.db.global.ignoredEvents then
		self.db.global.ignoredEvents = {}
	end
	-- cleanup old savedvars
	if self.db.profile.ignoredEvents then
		for k, v in next, self.db.profile.ignoredEvents do
			self.db.global.ignoredEvents[k] = v
		end
		self.db.profile.ignoredEvents = nil
	end

	-- try to fix memory overflow error
	if Transcriptor and TranscriptDB == nil then
		print("\n|cffff2020" .. L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your UI."])
		TranscriptDB = { ignoredEvents = {} }
		for k, v in next, self.db.global.ignoredEvents do
			TranscriptDB.ignoredEvents[k] = v
		end
	elseif not TranscriptDB.ignoredEvents then
		TranscriptDB.ignoredEvents = {}
	end

	self:RegisterMessage("BigWigs_ProfileUpdate")
	if self.db.profile.enabled then
		if self.db.profile.onpull then
			self:RegisterMessage("BigWigs_StartPull")
			self:RegisterMessage("BigWigs_StopPull")
		end
		self:RegisterMessage("BigWigs_OnBossEngage", "Start")
		self:RegisterMessage("BigWigs_OnBossWin")
		self:RegisterMessage("BigWigs_OnBossWipe", "BigWigs_OnBossWin")
	end
end

function plugin:OnPluginDisable()
	if logging and Transcriptor:IsLogging() then
		Transcriptor:StopLog()
	end
	logging = nil
	timer = nil
end

SLASH_BigWigs_Transcriptor1 = "/bwts"
SlashCmdList.BigWigs_Transcriptor = function()
	LibStub("AceConfigDialog-3.0"):Open("BigWigs", "Big Wigs: Transcriptor")
end

-------------------------------------------------------------------------------
-- Event Handlers
--

function plugin:BigWigs_StartPull(_, _, seconds)
	if seconds > 2 then
		self:CancelTimer(timer)
		timer = self:ScheduleTimer("Start", seconds-2)
	else
		self:Start()
	end
end

function plugin:BigWigs_StopPull()
	if timer then
		self:CancelTimer(timer)
		timer = nil
	end
end

function plugin:Start()
	if timer then
		self:CancelTimer(timer)
		timer = nil
	end
	-- stop your current log and start a new one
	if Transcriptor:IsLogging() and not logging then
		Transcriptor:StopLog(true)
	end
	if not Transcriptor:IsLogging() then
		Transcriptor:StartLog()
		logging = true
	end
end

function plugin:BigWigs_OnBossWin()
	-- catch the end event
	self:ScheduleTimer("Stop", 3)
end

function plugin:Stop()
	logging = nil
	if Transcriptor:IsLogging() then
		Transcriptor:StopLog()

		-- check memory
		UpdateAddOnMemoryUsage()
		local mem = GetAddOnMemoryUsage("Transcriptor") / 1000
		if mem > 60 then
			print("\n|cffff2020" .. L["Transcriptor is currently using %.01f MB of memory. You should clear some logs or risk losing them."]:format(mem))
		end
	end
end

