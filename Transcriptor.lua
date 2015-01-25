
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

-- GLOBALS: ENABLE GameTooltip InterfaceOptionsFrame_OpenToCategory SLASH_BWTRANSCRIPTOR1 Transcriptor TranscriptDB
-------------------------------------------------------------------------------
-- Locale
--

local PL
local L = LibStub("AceLocale-3.0"):NewLocale("Big Wigs: Transcriptor", "enUS", true)
L["Transcriptor"] = true
L["Automatically start Transcriptor logging when you pull a boss and stop when you win or wipe."] = true

L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your UI."] = true
L["Transcriptor is currently using %.01f MB of memory. You should clear some logs or risk losing them."] = true

L["Start with pull timer"] = true
L["Start Transcriptor logging from a pull timer at two seconds remaining."] = true
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
	ignoredEvents = {}
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
					LibStub("AceConfigRegistry-3.0"):NotifyChange("BigWigs") -- update again, damit!
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
					plugin.db.profile.ignoredEvents[key] = value
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
				if log.BigWigs_Message and log.BigWigs_Message[#log.BigWigs_Message]:find("bosskill", nil, true) then
					desc = ("%s %s"):format(L["|cff20ff20Win!|r"], desc)
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

function plugin:OnPluginEnable()
	PL = LibStub("AceLocale-3.0"):GetLocale("Big Wigs: Plugins")
	if Transcriptor and TranscriptDB == nil then -- try to fix memory overflow error
		print("\n|cffff2020" .. L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your UI."])
		TranscriptDB = { ignoredEvents = {} }
		for k, v in next, self.db.profile.ignoredEvents do
			TranscriptDB.ignoredEvents[k] = v
		end
	elseif not TranscriptDB.ignoredEvents then
		TranscriptDB.ignoredEvents = {}
	end

	if self.db.profile.enabled then
		if self.db.profile.onpull then
			self:RegisterMessage("BigWigs_StartPull")
			self:RegisterMessage("BigWigs_StopBar")
		end
		self:RegisterMessage("BigWigs_OnBossEngage", "Start")
		self:RegisterMessage("BigWigs_OnBossWin", "Stop")
		self:RegisterMessage("BigWigs_OnBossWipe", "Stop")
	end
end

function plugin:OnPluginDisable()
	if Transcriptor:IsLogging() and logging then
		Transcriptor:StopLog()
	end
	logging = nil
	timer = nil
end

-- only available after the plugin is loaded. oh well.
SLASH_BWTRANSCRIPTOR1 = "/bwts"
SlashCmdList["BWTRANSCRIPTOR"] = function()
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

function plugin:BigWigs_StopBar(_, _, text)
	if text == PL.pull and timer then
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

