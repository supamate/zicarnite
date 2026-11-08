local WEBHOOK_URL = ""
local DISCORD_USER_ID = "333656037347557377"
local ZIC_PINGS = 10
local SHOW_SERVER_NAME = true
local KEYWORDS = { "ZICARDITE", "ZIC" }
local SCAN_TIME = 10
local TELEPORT_WAIT = 8
local SERVER_LIST_PLACE_ID = 133950099874787
local HUB_JOIN_WAIT = 15
local MIN_FREE_SLOTS = 1
local VISITED_EXPIRY = 7200
local MAX_VISITED = 1500
local REPORT_DELAY = 2
local REPORT_SPACING = 0.3
local ALARM_LAYERS = 4
local PAUSE_KEY = Enum.KeyCode.RightControl
local VISITED_FILE = "zic-hunter-visited.json"
local LOG_FILE = "zic-hunter-finds.txt"
local LAST_SERVER_FILE = "zic-hunter-last-server.json"

local globalEnvironment = (getgenv and getgenv()) or _G
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local PlaceId = game.PlaceId

math.randomseed(os.time() + math.floor((os.clock() % 1) * 1000000) + #game.JobId * 7919)
for _ = 1, 5 do
	math.random()
end

local function firstFunction(...)
	for index = 1, select("#", ...) do
		local candidate = select(index, ...)
		if type(candidate) == "function" then
			return candidate
		end
	end
end

local function field(container, name)
	if type(container) == "table" then
		return container[name]
	end
end

local httpRequest = firstFunction(request, http_request, field(syn, "request"), field(http, "request"), field(fluxus, "request"))

if WEBHOOK_URL == "" and type(globalEnvironment.ZicWebhook) == "string" then
	WEBHOOK_URL = globalEnvironment.ZicWebhook
end
if type(globalEnvironment.ZicPingId) == "string" and string.match(globalEnvironment.ZicPingId, "^%d+$") then
	DISCORD_USER_ID = globalEnvironment.ZicPingId
end

local function postWebhook(content, ping)
	if WEBHOOK_URL == "" or not httpRequest then
		return
	end
	local canPing = ping and DISCORD_USER_ID ~= ""
	pcall(httpRequest, {
		Url = WEBHOOK_URL,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode({
			content = (canPing and ("<@" .. DISCORD_USER_ID .. "> ") or "") .. content,
			allowed_mentions = { parse = {}, users = canPing and { DISCORD_USER_ID } or {} },
		}),
	})
end

local function notify(title, text, duration)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = duration or 5 })
	end)
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local localPlayer = Players.LocalPlayer
while not localPlayer do
	task.wait()
	localPlayer = Players.LocalPlayer
end

if globalEnvironment.__ZicHunterJobId == game.JobId then
	return
end
globalEnvironment.__ZicHunterJobId = game.JobId

local state = { Found = false, Paused = false, FoundNodes = {} }
globalEnvironment.ZicHunter = state

local function matchesText(text)
	local upper = string.upper(tostring(text))
	for _, keyword in ipairs(KEYWORDS) do
		if string.find(upper, keyword, 1, true) then
			return true
		end
	end
	return false
end

local function instanceMatches(instance)
	if matchesText(instance.Name) then
		return true
	end
	if instance:IsA("StringValue") and matchesText(instance.Value) then
		return true
	end
	local success, attributes = pcall(instance.GetAttributes, instance)
	if success then
		for _, value in pairs(attributes) do
			if type(value) == "string" and matchesText(value) then
				return true
			end
		end
	end
	return false
end

local function getTopNode(instance, folder)
	local current = instance
	while current and current.Parent ~= folder do
		current = current.Parent
		if current == nil or current == game then
			return nil
		end
	end
	return current
end

local function getAnchorPart(node)
	if node:IsA("BasePart") then
		return node
	end
	if node:IsA("Model") and node.PrimaryPart then
		return node.PrimaryPart
	end
	return node:FindFirstChildWhichIsA("BasePart", true)
end

local function parentGui(gui)
	local success = pcall(function()
		gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if not success then
		gui.Parent = localPlayer:WaitForChild("PlayerGui")
	end
end

local alertGui, alertDetails

local alarmSounds = {}

local function stopAlarm()
	for _, sound in ipairs(alarmSounds) do
		sound:Destroy()
	end
	alarmSounds = {}
end

local function startAlarm()
	if #alarmSounds > 0 then
		return
	end

	pcall(function()
		UserSettings():GetService("UserGameSettings").MasterVolume = 1
	end)

	for index = 1, ALARM_LAYERS do
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		sound.Volume = 10
		sound.Looped = true
		local distortion = Instance.new("DistortionSoundEffect")
		distortion.Level = 0.6
		distortion.Parent = sound
		sound.Parent = SoundService
		sound:Play()
		table.insert(alarmSounds, sound)
	end

	task.spawn(function()
		local high = false
		while #alarmSounds > 0 do
			high = not high
			for _, sound in ipairs(alarmSounds) do
				sound.PlaybackSpeed = high and 1.6 or 1.1
			end
			task.wait(0.25)
		end
	end)
end

local function buildAlertGui()
	if alertGui then
		return
	end

	alertGui = Instance.new("ScreenGui")
	alertGui.Name = "ZicHunterAlert"
	alertGui.IgnoreGuiInset = true
	alertGui.ResetOnSpawn = false
	alertGui.DisplayOrder = 999999

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(255, 0, 90)
	flash.BorderSizePixel = 0
	flash.Parent = alertGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.7, 0.45)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	panel.BorderSizePixel = 0
	panel.Parent = alertGui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)

	local stroke = Instance.new("UIStroke", panel)
	stroke.Thickness = 6

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.05, 0.05)
	title.Size = UDim2.fromScale(0.9, 0.4)
	title.Font = Enum.Font.GothamBlack
	title.Text = "ZICARDITE FOUND!"
	title.TextColor3 = Color3.fromRGB(255, 220, 0)
	title.TextScaled = true
	title.Parent = panel

	alertDetails = Instance.new("TextLabel")
	alertDetails.BackgroundTransparency = 1
	alertDetails.Position = UDim2.fromScale(0.05, 0.46)
	alertDetails.Size = UDim2.fromScale(0.9, 0.3)
	alertDetails.Font = Enum.Font.GothamBold
	alertDetails.TextColor3 = Color3.fromRGB(255, 255, 255)
	alertDetails.TextScaled = true
	alertDetails.TextWrapped = true
	alertDetails.Parent = panel

	local dismiss = Instance.new("TextButton")
	dismiss.AnchorPoint = Vector2.new(0.5, 0)
	dismiss.Position = UDim2.fromScale(0.5, 0.8)
	dismiss.Size = UDim2.fromScale(0.4, 0.14)
	dismiss.BackgroundColor3 = Color3.fromRGB(255, 220, 0)
	dismiss.Font = Enum.Font.GothamBlack
	dismiss.Text = "GOT IT"
	dismiss.TextColor3 = Color3.fromRGB(0, 0, 0)
	dismiss.TextScaled = true
	dismiss.Parent = panel
	Instance.new("UICorner", dismiss).CornerRadius = UDim.new(0, 10)

	dismiss.MouseButton1Click:Connect(function()
		stopAlarm()
		alertGui:Destroy()
		alertGui = nil
		alertDetails = nil
	end)

	parentGui(alertGui)

	task.spawn(function()
		local on = false
		while alertGui and alertGui.Parent do
			on = not on
			flash.BackgroundTransparency = on and 0.15 or 0.75
			stroke.Color = on and Color3.fromRGB(255, 220, 0) or Color3.fromRGB(255, 0, 90)
			task.wait(0.35)
		end
	end)
end

local function markNode(node)
	local anchor = getAnchorPart(node)

	pcall(function()
		local highlight = Instance.new("Highlight")
		highlight.Adornee = node
		highlight.FillColor = Color3.fromRGB(255, 0, 200)
		highlight.OutlineColor = Color3.fromRGB(255, 255, 0)
		highlight.FillTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = node
	end)

	if not anchor then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(240, 60)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.MaxDistance = math.huge
	billboard.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 220, 0)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Text = node.Name
	label.Parent = billboard

	parentGui(billboard)

	task.spawn(function()
		while billboard.Parent and anchor.Parent do
			local character = localPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				label.Text = string.format("%s\n%d studs", node.Name, math.floor((root.Position - anchor.Position).Magnitude))
			end
			task.wait(0.25)
		end
		billboard:Destroy()
	end)
end

local serverInfoCache

local function getServerInfo()
	if serverInfoCache then
		return serverInfoCache[1], serverInfoCache[2]
	end
	local serverName, labelFound, regionName
	local deadline = os.clock() + 6
	repeat
		local playerGui = localPlayer:FindFirstChild("PlayerGui")
		local label = playerGui and playerGui:FindFirstChild("ServerAame", true)
		if label then
			labelFound = true
			pcall(function()
				serverName = label.ContentText ~= "" and label.ContentText or label.Text
			end)
			pcall(function()
				for _, other in ipairs(label.Parent:GetDescendants()) do
					if other:IsA("TextLabel") and string.find(string.lower(other.Name), "region", 1, true) and other.ContentText ~= "" then
						regionName = other.ContentText
						break
					end
				end
			end)
		end
		if serverName and serverName ~= "" then
			break
		end
		task.wait(0.25)
	until os.clock() > deadline
	pcall(function()
		local last = HttpService:JSONDecode(readfile(LAST_SERVER_FILE))
		if os.time() - (tonumber(last.Time) or 0) < 300 then
			if (not serverName or serverName == "") and type(last.Name) == "string" and last.Name ~= "" then
				serverName = last.Name
			end
			if not regionName and type(last.Region) == "string" and last.Region ~= "" then
				regionName = last.Region
			end
		end
	end)
	if not serverName or serverName == "" then
		serverName = labelFound and "Unknown (label empty)" or "Unknown (label not found)"
	end
	regionName = regionName or "Unknown"
	serverInfoCache = { serverName, regionName }
	return serverName, regionName
end

local function findDetails()
	local serverName, regionName = getServerInfo()
	return string.format(
		"SERVER NAME: **%s**\nREGION: **%s**\nACCOUNT: **%s** (%s)\nJobId: `%s`",
		serverName,
		regionName,
		localPlayer.Name,
		localPlayer.DisplayName,
		game.JobId
	)
end

local function triggerAlert(node)
	if state.FoundNodes[node] then
		return
	end
	state.FoundNodes[node] = true
	state.Found = true

	local names = {}
	for foundNode in pairs(state.FoundNodes) do
		table.insert(names, foundNode.Name)
	end
	local nameList = table.concat(names, ", ")
	local rejoin = string.format('game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s")', PlaceId, game.JobId)

	warn("[ZicHunter] FOUND:", node:GetFullName(), game.JobId)

	buildAlertGui()
	startAlarm()
	markNode(node)

	if alertDetails then
		alertDetails.Text = nameList .. "\nServer hop STOPPED\nJobId: " .. game.JobId
	end

	notify("ZICARDITE FOUND!", nameList .. " - server hop stopped", 60)

	if setclipboard then
		pcall(setclipboard, rejoin)
	end

	local line = string.format("[%s] %s | %s\n", os.date("%Y-%m-%d %H:%M:%S"), nameList, rejoin)
	pcall(appendfile or writefile, LOG_FILE, line)

	if not state.Pinging then
		state.Pinging = true
		task.spawn(function()
			local details = findDetails()
			postWebhook("**ZICARDITE FOUND** (" .. nameList .. ")\n" .. details .. "\n```lua\n" .. rejoin .. "\n```", true)
			for index = 2, ZIC_PINGS do
				task.wait(2)
				postWebhook("**ZICARDITE FOUND** " .. index .. "/" .. ZIC_PINGS .. "\n" .. details, true)
			end
			while alertGui do
				task.wait(60)
				if alertGui then
					postWebhook("**ZICARDITE STILL HERE**\n" .. details, true)
				end
			end
		end)
	end

	if messagebox then
		task.spawn(pcall, messagebox, "ZICARDITE FOUND: " .. nameList, "Zicardite Hunter", 0x30)
	end
end

local function loadVisited()
	local now = os.time()
	local merged = { Servers = {}, Hops = 0 }

	local sources = { globalEnvironment.ZicVisited }
	pcall(function()
		table.insert(sources, HttpService:JSONDecode(readfile(VISITED_FILE)))
	end)

	for _, source in pairs(sources) do
		if type(source) == "table" and type(source.Servers) == "table" then
			for id, stamp in pairs(source.Servers) do
				if type(stamp) == "number" and now - stamp < VISITED_EXPIRY then
					merged.Servers[id] = math.max(merged.Servers[id] or 0, stamp)
				end
			end
			merged.Hops = math.max(merged.Hops, tonumber(source.Hops) or 0)
		end
	end

	return merged
end

local function saveVisited(data)
	local list = {}
	for id, stamp in pairs(data.Servers) do
		table.insert(list, { id, stamp })
	end
	if #list > MAX_VISITED then
		table.sort(list, function(a, b)
			return a[2] > b[2]
		end)
		data.Servers = {}
		for index = 1, MAX_VISITED do
			data.Servers[list[index][1]] = list[index][2]
		end
	end

	globalEnvironment.ZicVisited = data
	pcall(function()
		writefile(VISITED_FILE, HttpService:JSONEncode(data))
	end)
end

local teleportFailed = false
TeleportService.TeleportInitFailed:Connect(function(player)
	if player == localPlayer then
		teleportFailed = true
	end
end)

local function hubHop(pickServer, serverFolders)
	local deadline = os.clock() + 15
	while os.clock() < deadline and #serverFolders:GetDescendants() == 0 do
		task.wait(0.5)
	end
	task.wait(1)

	while not state.Found and not state.Paused do
		local visited = loadVisited()
		local pool, names, regions = {}, {}, {}
		for _, region in ipairs(serverFolders:GetChildren()) do
			for _, server in ipairs(region:GetChildren()) do
				local numPlayers = server:FindFirstChild("NumPlayers")
				local maxPlayers = server:FindFirstChild("MaxPlayers")
				if numPlayers and maxPlayers and not visited.Servers[server.Name] and numPlayers.Value >= 1 and maxPlayers.Value - numPlayers.Value >= MIN_FREE_SLOTS then
					table.insert(pool, server.Name)
					local serverName = server:FindFirstChild("ServerName")
					names[server.Name] = serverName and tostring(serverName.Value) or nil
					local serverRegion = server:FindFirstChild("Region")
					regions[server.Name] = serverRegion and tostring(serverRegion.Value) or region.Name
				end
			end
		end

		local id = #pool > 0 and pool[math.random(1, #pool)] or nil
		if id then
			visited.Servers[id] = os.time()
		end
		pcall(function()
			writefile(LAST_SERVER_FILE, HttpService:JSONEncode({ Id = id, Name = id and names[id] or nil, Region = id and regions[id] or nil, Time = os.time() }))
		end)
		visited.Hops = visited.Hops + 1
		saveVisited(visited)
		notify("Zicardite Hunter", "Joining server #" .. visited.Hops .. " (" .. #pool .. " unvisited)", 3)

		local success, joined = pcall(function()
			if id then
				return pickServer:InvokeServer(id)
			end
			return pickServer:InvokeServer("none", "All")
		end)
		task.wait((success and joined) and HUB_JOIN_WAIT or 1)
	end
end

local function findServerListButton()
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	local root = playerGui and (playerGui:FindFirstChild("TopbarStandard") or playerGui)
	if not root then
		return nil
	end

	for _, gui in ipairs(root:GetDescendants()) do
		local text = gui.Name
		if gui:IsA("TextLabel") or gui:IsA("TextButton") then
			text = text .. " " .. gui.Text
		end
		if gui:IsA("GuiObject") and string.find(string.lower(text), "server", 1, true) and not gui:FindFirstAncestor("ServerInfoGui") then
			local current = gui
			while current and current ~= root do
				if current:IsA("GuiButton") then
					return current
				end
				local button = current:FindFirstChildWhichIsA("GuiButton", true)
				if button then
					return button
				end
				current = current.Parent
			end
		end
	end
	return nil
end

local function fireConnections(button)
	if not getconnections then
		return false
	end
	for _, signalName in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up" }) do
		local ok, connections = pcall(getconnections, button[signalName])
		if ok and type(connections) == "table" and #connections > 0 then
			for _, connection in ipairs(connections) do
				pcall(function()
					connection:Fire()
				end)
			end
			return true
		end
	end
	return false
end

local function mouseClick(button)
	return pcall(function()
		local inputManager = game:GetService("VirtualInputManager")
		local center = button.AbsolutePosition + button.AbsoluteSize / 2
		local screenGui = button:FindFirstAncestorWhichIsA("ScreenGui")
		if not (screenGui and screenGui.IgnoreGuiInset) then
			center = center + game:GetService("GuiService"):GetGuiInset()
		end
		inputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
		task.wait(0.05)
		if state.Found then
			inputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
			return
		end
		inputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
	end)
end

local serverListAttempts = 0

local function teleportToHub()
	local visited = loadVisited()
	visited.Servers[game.JobId] = os.time()
	saveVisited(visited)

	if state.Found then
		return
	end
	serverListAttempts = serverListAttempts + 1
	teleportFailed = false

	local button = findServerListButton()
	local method = serverListAttempts % 3
	if not button then
		notify("Zicardite Hunter", "Server List button not found, teleporting", 3)
		method = 0
	end
	if method == 1 and not state.Found and fireConnections(button) then
		notify("Zicardite Hunter", "Clicking Server List...", 3)
	elseif method ~= 0 and not state.Found then
		notify("Zicardite Hunter", "Clicking Server List (mouse)...", 3)
		mouseClick(button)
	else
		notify("Zicardite Hunter", "Opening server list...", 3)
		pcall(function()
			if state.Found then
				return
			end
			TeleportService:Teleport(SERVER_LIST_PLACE_ID, localPlayer)
		end)
	end

	local deadline = os.clock() + TELEPORT_WAIT * 2
	while os.clock() < deadline and not teleportFailed do
		task.wait(0.2)
	end
end

local function serverHop()
	local storage = game:GetService("ReplicatedStorage")
	local pickServer = storage:FindFirstChild("PickServer")
	local serverFolders = storage:FindFirstChild("Servers")
	if pickServer and serverFolders then
		hubHop(pickServer, serverFolders)
	elseif workspace:FindFirstChild("OreNodes") then
		teleportToHub()
	end
	task.wait(2)
end

localPlayer.Idled:Connect(function()
	if state.Found then
		pcall(function()
			local VirtualUser = game:GetService("VirtualUser")
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= PAUSE_KEY then
		return
	end
	state.Paused = not state.Paused
	notify("Zicardite Hunter", state.Paused and "Server hop PAUSED" or "Server hop RESUMED", 4)
end)

notify("Zicardite Hunter", "Scanning OreNodes... (Right Ctrl = pause)", 4)

local inServerList = game:GetService("ReplicatedStorage"):FindFirstChild("PickServer") ~= nil
local oreNodes = workspace:WaitForChild("OreNodes", inServerList and 3 or 25)

if oreNodes then
	local function check(instance)
		local node = getTopNode(instance, oreNodes)
		if node and instanceMatches(instance) then
			triggerAlert(node)
		end
	end

	for _, descendant in ipairs(oreNodes:GetDescendants()) do
		check(descendant)
	end
	oreNodes.DescendantAdded:Connect(check)

	task.spawn(function()
		task.wait(REPORT_DELAY)
		local counts, order = {}, {}
		for _, node in ipairs(oreNodes:GetChildren()) do
			if not state.FoundNodes[node] and not instanceMatches(node) then
				if not counts[node.Name] then
					counts[node.Name] = 0
					table.insert(order, node.Name)
				end
				counts[node.Name] = counts[node.Name] + 1
			end
		end
		table.sort(order)
		if #order == 0 then
			notify("OreNodes", "Nothing else found", 2)
		end
		for _, name in ipairs(order) do
			notify("OreNodes", name .. " x" .. counts[name], 2)
			task.wait(REPORT_SPACING)
		end
	end)

	task.spawn(function()
		task.wait(REPORT_DELAY)
		if WEBHOOK_URL == "" or not httpRequest then
			return
		end
		local counts, order, ping = {}, {}, false
		for _, node in ipairs(oreNodes:GetChildren()) do
			if string.find(string.upper(node.Name), "GOLD", 1, true) then
				ping = true
			end
			if not counts[node.Name] then
				counts[node.Name] = 0
				table.insert(order, node.Name)
			end
			counts[node.Name] = counts[node.Name] + 1
		end
		table.sort(order)
		local lines = { "Joined server: `" .. game.JobId .. "`" }
		if SHOW_SERVER_NAME then
			local serverName, regionName = getServerInfo()
			table.insert(lines, "SERVER NAME: **" .. serverName .. "**")
			table.insert(lines, "REGION: **" .. (regionName or "Unknown") .. "**")
		end
		table.insert(lines, "━━━━━━━━━━━━━━━━━━━━")
		for _, name in ipairs(order) do
			table.insert(lines, name .. " x" .. counts[name])
		end
		if #order == 0 then
			table.insert(lines, "No ores")
		end
		postWebhook(table.concat(lines, "\n"), ping)
	end)

	local deadline = os.clock() + SCAN_TIME
	while os.clock() < deadline and not state.Found do
		task.wait(0.25)
	end
end

while not state.Found do
	if state.Paused then
		task.wait(0.5)
	else
		serverHop()
		task.wait(1)
	end
end
