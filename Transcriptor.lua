-------------------------------------------------------------------------------
-- Module Declaration
--

local plugin = BigWigs:NewPlugin("Transcriptor")
if not plugin then return end

-------------------------------------------------------------------------------
-- Locals
--

local logging = nil

-------------------------------------------------------------------------------
-- Locale
--

local L = LibStub("AceLocale-3.0"):NewLocale("Big Wigs: Transcriptor", "enUS", true)
if L then
	L.title = "Transcriptor"
	L.description = "Automatically start Transcriptor logging when you pull a boss and stop when you win or wipe."

	L.logs = "Stored logs - Click to delete"
	L.events = "%d stored events over %s seconds."
	L.win = "|cff20ff20Win!|r "
end
L = LibStub("AceLocale-3.0"):GetLocale("Big Wigs: Transcriptor")

-------------------------------------------------------------------------------
-- Options
--

plugin.defaultDB = {
	enabled = false,
}

local function GetOptions()
	local logs = Transcriptor:GetAll()

	local options = {
		name = L.title,
		type = "group",
		get = function(info) return plugin.db.profile[info[#info]] end,
		set = function(info, value) plugin.db.profile[info[#info]] = value end,
		args = {
			heading = {
				type = "description",
				name = L.description.."\n",
				fontSize = "medium",
				width = "full",
				order = 1,
			},
			enabled = {
				type = "toggle",
				name = ENABLE,
				set = function(info, value)
					plugin.db.profile[info[#info]] = value
					plugin:Disable()
					plugin:Enable()
				end,
				order = 2,
			},
			logs = {
				type = "group",
				inline = true,
				name = L.logs,
				func = function(info) logs[info[#info]] = nil end,
				order = 10,
				width = "full",
				args = {},
			},
		},
	}

	for key, log in next, logs do
		if key ~= "ignoredEvents" then
			local desc = nil
			local count = log.total and #log.total or 0
			if count > 0 then
				desc = L.events:format(count, log.total[count]:match("^<(.-)%s"))
				if log.BigWigs_Message and log.BigWigs_Message[#log.BigWigs_Message]:find("bosskill", nil, true) then
					desc = L.win..desc
				end
			end
			options.args.logs.args[key] = {
				type = "execute",
				name = key,
				desc = desc,
				width = "full",
			}
		end
	end

	return options
end

plugin.subPanelOptions = {
	key = "Big Wigs: Transcriptor",
	name = L.title,
	options = GetOptions,
}

-------------------------------------------------------------------------------
-- Initialization
--

function plugin:OnPluginEnable()
	if self.db.profile.enabled then
		if BigWigs then
			self:RegisterMessage("BigWigs_OnBossEngage", "Start")
			self:RegisterMessage("BigWigs_OnBossWin", "Stop")
			self:RegisterMessage("BigWigs_OnBossWipe", "Stop")
		end
	end
end

function plugin:OnPluginDisable()
	if logging and Transcriptor:IsLogging() then
		Transcriptor:StopLog()
	end
	logging = nil
end

-------------------------------------------------------------------------------
-- Event Handlers
--

function plugin:Start()
	local diff = select(3, GetInstanceInfo()) or 0
	if diff > 2 and diff < 7 then
		-- should the plugin stop your current log and take over? (current behavior)
		-- or leave Transcriptor alone and not do anything (starting or stopping) until you stop the current log yourself?
		if Transcriptor:IsLogging() then
			Transcriptor:StopLog(true)
		end
		Transcriptor:StartLog()
		logging = true
	end
end

function plugin:Stop()
	if logging then
		if Transcriptor:IsLogging() then
			Transcriptor:StopLog()
		end
		logging = nil
	end
end

