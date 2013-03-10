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

	L.silent = "Silent"
	L.silent_desc = "Don't print to chat when logging starts or stops."

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
	silent = false,
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
				width = "full",
				order = 2,
			},
			silent = {
				type = "toggle",
				name = L.silent,
				desc = L.silent_desc,
				disabled = function() return not plugin.db.profile.enabled end,
				width = "full",
				order = 3,
			},
			logs = {
				type = "group",
				inline = true,
				name = L.logs,
				order = 10,
				func = function(info) logs[info[#info]] = nil end,
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
		self:RegisterMessage("BigWigs_OnBossEngage")
		self:RegisterMessage("BigWigs_OnBossWin")
		self:RegisterMessage("BigWigs_OnBossWipe")
	end
end

function plugin:OnPluginDisable()
	if logging and Transcriptor:IsLogging() then
		Transcriptor:StopLog(self.db.profile.silent)
	end
	logging = nil
end

-------------------------------------------------------------------------------
-- Event Handlers
--

function plugin:BigWigs_OnBossEngage(event, module, diff)
	if diff and diff > 2 and diff < 7 then
		-- should the plugin stop your current log and take over? (current behavior)
		-- or leave Transcriptor alone and not do anything (starting or stopping) until you stop the current log yourself?
		if Transcriptor:IsLogging() then
			Transcriptor:StopLog(true)
		end
		Transcriptor:StartLog(self.db.profile.silent)
		logging = true
	end
end

function plugin:BigWigs_OnBossWin(event, module)
	if logging then
		if Transcriptor:IsLogging() then
			Transcriptor:StopLog(self.db.profile.silent)
		end
		logging = nil
	end
end

function plugin:BigWigs_OnBossWipe(event, module)
	if logging then
		if Transcriptor:IsLogging() then
			Transcriptor:StopLog(self.db.profile.silent)
		end
		logging = nil
	end
end

