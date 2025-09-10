--> Services <--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--> Replicated Models <--
local repModels = ReplicatedStorage:WaitForChild("Models")
local repBeeModels = repModels:WaitForChild("Bees")

--> Replicated Modules <--
local repModules = ReplicatedStorage:WaitForChild("Modules")
local repSystems = repModules:WaitForChild("Systems")
local repUtils = repModules:WaitForChild("Utilities")
local repTools = repModules:WaitForChild("Tools")

--> Server Modules <--
local serverModules = ServerStorage:WaitForChild("Modules")
local serverSystems = serverModules:WaitForChild("Systems")
local serverEntities = serverModules:WaitForChild("Entities")

--> Required Modules <--
local Event_Handler = require(repUtils:WaitForChild("Event_Handler"))
local SetCollision = require(repTools:WaitForChild("SetCollision"))
local TableEditor = require(repTools:WaitForChild("TableEditor"))
local DataStore = require(serverSystems:WaitForChild("DataStore"))
local BeeInfos = require(serverEntities:WaitForChild("BeeInfos"))
local PlotHandler = require(serverSystems:WaitForChild("PlotHandler"))
local _config = require(repSystems:WaitForChild("BeeHandler"):WaitForChild("Config"))

--> Events <--
local repBeeEvents = "ReplicatedStorage.Events.BeeSystem"
local repChatEvents = "ReplicatedStorage.Events.ChatSystem"
local serverBeeEvents = "ServerStorage.Events.BeeSystem"

local SendMsgEvent : Event_Handler.CustomRemote = Event_Handler.GetEvent("SendMsg", repChatEvents) :: Event_Handler.CustomRemote

local LinkEvent : Event_Handler.CustomRemote = Event_Handler.GetEvent("Link", repBeeEvents) :: Event_Handler.CustomRemote
local SellEvent : Event_Handler.CustomRemote = Event_Handler.GetEvent("Sell", repBeeEvents) :: Event_Handler.CustomRemote
local StealEvent: Event_Handler.CustomRemote = Event_Handler.GetEvent("Steal", repBeeEvents) :: Event_Handler.CustomRemote
local DestroyEvent : Event_Handler.CustomRemote = Event_Handler.GetEvent("Destroy", repBeeEvents) :: Event_Handler.CustomRemote
local PurchaseEvent : Event_Handler.CustomRemote = Event_Handler.GetEvent("Purchase", repBeeEvents) :: Event_Handler.CustomRemote

local BeeActionEvent : Event_Handler.CustomBindable = Event_Handler.GetEvent("BeeAction", serverBeeEvents) :: Event_Handler.CustomBindable
local GenerateEvent : Event_Handler.CustomBindable = Event_Handler.GetEvent("Generate", serverBeeEvents) :: Event_Handler.CustomBindable
local GetBeeEvent : Event_Handler.CustomBindable = Event_Handler.GetEvent("GetBee", serverBeeEvents) :: Event_Handler.CustomBindable

--> Bee Related Instances <--
local BeeFolder = workspace:WaitForChild("Bees")
local PlotBees = BeeFolder:WaitForChild("Plot")
local WalkingBees = BeeFolder:WaitForChild("Walking")

--> Tables & Dictionaries <--
local BeeHandler = {}
local API = {}

local Bees = {}

--> Indexes <--
BeeHandler.__index = BeeHandler

--> Constants <--
local requireID = HttpService:GenerateGUID(false)

local walkAlpha = 8.85
local moveLogBase = 1000
local nestYPosOffset = 4
local beeIdleAnim = "rbxassetid://71569760671616"

local CurrencyPath = "Inventory.Currency"
local BeePath = "Inventory.Bees"

local init = false

local Rarities = {
	["Basic"] = NumberRange.new(0, 66), --> 66%
	["Rare"] = NumberRange.new(66, 94), --> 28%
	["Legendary"] = NumberRange.new(94, 99), --> 5%
	["Mythic"] = NumberRange.new(99, 99.7), --> 0.7%
	["Divine"] = NumberRange.new(99.7, 99.9), --> 0.2%
	["Secret"] = NumberRange.new(99.99, 100), --> 0.01%
}

local Precisions = {
	["Rarity"] = 100
}

--> Types <--
export type BeeAnims = _config.Animations
export type BeeInfo = _config.Info

export type BeeRarity = _config.BeeRarity
export type BeeVariant = _config.BeeVariant

export type nonMetaBee =  {
	["Rarity"] : BeeRarity,
	["Variant"] : BeeVariant
} & _config.Bee

export type Bee = nonMetaBee & typeof(setmetatable({}, BeeHandler))

--> Local Functions <--

local function GetBee(senderID : string, fromInit : boolean, beeGUID : string)
	if fromInit ~= false then return end
	
	local bee : Bee = Bees[beeGUID]
	GetBeeEvent:Fire(true, senderID, true, setmetatable(bee, nil))
	setmetatable(bee, BeeHandler)
end

local function doBeeAction(beeGUID : string, action : string, args : {any})
	local bee : Bee? = Bees[beeGUID]
	if not (bee and bee[action]) then return end
	
	bee[action](bee, table.unpack(args or {}))
end

local function GenerateBee(senderID : string, fromInit : boolean, rarity : BeeRarity?, name : string?, variant : BeeVariant?, ownerID : number?)
	if fromInit ~= false then return end
	local bee : Bee = API.GenerateBee(rarity, name, variant, ownerID)
	
	GenerateEvent:Fire(true, senderID, true, setmetatable(bee, nil))
	setmetatable(bee, BeeHandler)
end

local function PsuedoGenerate(beeRarity : BeeRarity?, beeName : string?, beeVariant : BeeVariant?, ownerID : number?)
	local connection : RBXScriptConnection
	local bee : Bee

	connection = GenerateEvent:OnEvent(function(senderID : string, fromInit : boolean, nonMetaBee : nonMetaBee)
		if senderID ~= requireID or not fromInit then return end
		connection:Disconnect()
		bee = setmetatable(nonMetaBee, BeeHandler) :: Bee
	end)
	
	GenerateEvent:Fire(false, requireID, false, beeRarity, beeName, beeVariant, ownerID)

	while type(bee) == type(nil) do RunService.Heartbeat:Wait() end
	return bee
end

local function SellBee(player : Player, beeGUID : string)
	local bee : Bee? = Bees[beeGUID]
	if bee then bee:Sell() end
end

local function PurchaseBee(player : Player, beeGUID : string)
	local bee : Bee? = Bees[beeGUID]
	local playerCash : number = DataStore.GetValue(player, CurrencyPath, "Cash") :: number
	if not bee or (bee.OwnerID and player.UserId ~= bee.OwnerID) then return end
	
	if (playerCash < bee.Price) then
		SendMsgEvent:Fire(false, player, "[Bees]: Not enough cash to buy bee!", "Fail")
		return 
	end
	
	setmetatable(bee, BeeHandler)
	bee:WalkToBase(player)
end

local function StealBee(player : Player, beeGUID : string)
	local bee : Bee = Bees[beeGUID]
	if not (bee and player.UserId ~= bee.OwnerID) then return end 
	
	bee.GiveCash = false
	bee:Hold(player)
end

local function ProfileRelease(player : Player, profile : DataStore.Profile)
	local playerBees : {[string] : nonMetaBee} = profile.Data.Inventory.Bees
	local plot = PlotHandler.GetPlot(player)
	
	plot:GetAttributeChangedSignal("Owner"):Wait()

	for _, nonMetaBee : nonMetaBee in pairs(playerBees) do
		local bee : Bee = setmetatable(nonMetaBee, BeeHandler) :: Bee
		bee:Destroy()
	end
end

local function PlayerJoined(player : Player)
	if not player:GetAttribute("Loaded") then player:GetAttributeChangedSignal("Loaded"):Wait() end
	
	local profile : DataStore.Profile = DataStore.GetProfile(player) :: DataStore.Profile
	local playerBees : {[string] : nonMetaBee} = DataStore.GetValue(player, "Inventory", "Bees") :: {[string] : nonMetaBee}
	
	profile:ListenToRelease(function()
		task.spawn(ProfileRelease, player, profile)
		PlotHandler.UnassignPlot(player)
	end)
	
	for _, nonMetaBee : nonMetaBee in pairs(playerBees) do
		local bee : Bee = setmetatable(nonMetaBee, BeeHandler) :: Bee
		bee.Destroyed = false
		
		Bees[bee.GUID] = bee
		bee:AddToNest(player, bee.NestNum, true)
	end
end

--> Bee General Functions <--

function BeeHandler.Destroy(self : Bee)
	if not init then BeeActionEvent:Fire(false, self.GUID, "Destroy") return end
	
	local nest = PlotHandler.GetNest(self.OwnerID, self.NestNum)
	if nest then nest:SetAttribute("BeeGUID", nil) end
	
	for _, connection : RBXScriptConnection in pairs(self.Connections) do
		connection:Disconnect()
	end
	self.Destroyed = true
	
	DestroyEvent:Fire(false, "AllPlayers", self.GUID)
	Bees[self.GUID] = nil
end

function BeeHandler.SetMap(self : Bee, map : Model & {["Start"] : Part, ["End"] : Part})
	self.Map = map
	
	if not init then
		BeeActionEvent:Fire(false, self.GUID, "SetMap", table.pack(map)) 
	end
end

function BeeHandler.Sell(self : Bee)
	if not init then BeeActionEvent:Fire(false, self.GUID, "Sell") return end
	
	local owner = Players:GetPlayerByUserId(self.OwnerID)
	local currentCash : number = DataStore.GetValue(owner, CurrencyPath, "Cash") :: number
	
	self:Destroy()
	
	DataStore.RemoveValue(owner, BeePath, self.GUID)
	DataStore.SetValue(owner, CurrencyPath, "Cash", (currentCash + self.Price/2))
end

function BeeHandler.LoopCash(self :  Bee)
	if not init then BeeActionEvent:Fire(false, self.GUID, "LoopCash") return end
	local owner = Players:GetPlayerByUserId(self.OwnerID)
	local currentCash : number
	
	if self.GiveCash ~= true or self.Destroyed or not owner then 
		return 
	end
	
	currentCash = DataStore.GetValue(owner, CurrencyPath, "Cash") :: number
	DataStore.SetValue(owner, CurrencyPath, "Cash", currentCash + self.Cash)
	
	task.wait(1)
	task.spawn(self.LoopCash, self)
end

function BeeHandler.Hold(self : Bee, player : Player)
	if not init then BeeActionEvent:Fire(false, self.GUID, "Hold", table.pack(player)) end
	
	local plot : Model? = PlotHandler.GetPlot(player)
	local oldNest : Model = PlotHandler.GetBeeNest(self.OnHold, self.GUID) :: Model
	local nest : Model?, nestNum : number? = PlotHandler.FindAvailableNest(player)
	local playerChar = player.Character
	local collectZonePart
	local rightUpperArm
	
	local function forInit1()
		if not init then return end
		if not playerChar then
			player.CharacterAdded:Wait()
			playerChar = player.Character
		end
		
		rightUpperArm = playerChar.RightUpperArm
		rightUpperArm.RightShoulder.C1 *= CFrame.Angles(-90, 0, 0)
		collectZonePart = (plot::typeof(plot) & {["CollectZone"] : Part}).CollectZone

		self.Walkable = false
		self.OnHold = player
		
		LinkEvent:Fire(true, "AllPlayers", setmetatable(self, nil), {["Hold"] = player})
		setmetatable(self, BeeHandler)

		oldNest:SetAttribute("BeeGUID", nil)
		player:SetAttribute("HoldingBee", self.GUID)
	end
	
	local function forInit2()
		if not init then return end
		
		player:SetAttribute("HoldingBee", nil);
		(nest::Model):SetAttribute("BeeGUID", self.GUID)
		DataStore.RemoveValue(Players:GetPlayerByUserId(self.OwnerID), BeePath, self.GUID)
		
		SendMsgEvent:Fire(false, player, "[Bees]: Successfully stole a "..self.Name.."!", "Success")
		self.OwnerID = player.UserId
		self:AddToNest(player, nestNum)
	end
	
	if player:GetAttribute("HoldingBee") or not (plot and nest and nestNum) or self.Destroyed == true then return end
	forInit1()
	
	self.Walkable = false
	self.OnHold = player

	while (playerChar:GetPivot().Position - collectZonePart.Position).Magnitude > collectZonePart.Size.X and self.Destroyed ~= true do
		self.CFrame = CFrame.new(playerChar.RightHand.Position)
		RunService.Heartbeat:Wait()
	end
	
	forInit2()
	self.OwnerID = player.UserId
end

function BeeHandler.AddToNest(self : Bee, player : Player, nestNum : number, staticNest : boolean?)
	if not init then BeeActionEvent:Fire(false, self.GUID, "AddToNest", table.pack(player, nestNum, staticNest)) end
	
	local nest : Model? = PlotHandler.GetNest(player, nestNum) :: Model?
	local lookAtCF : CFrame, collectorPos : Vector3, nestPos : Vector3, compareNestPos : Vector3
	local lookX : number, lookY : number, lookZ : number
	local newNest : Model?, newNestNum : number?
	
	if self.OwnerID ~= player.UserId or self.Destroyed == true or not nest then return end
	
	--> Search For New Nest <--
	newNest, newNestNum = PlotHandler.FindAvailableNest(player)
	
	if newNest and newNestNum and (newNest::Model).Name ~= nest.Name and newNestNum < nestNum and staticNest ~= true then
		nest:SetAttribute("BeeGUID", nil);
		nest = newNest
		nestNum = newNestNum
	end
	nest:SetAttribute("BeeGUID", self.GUID)
	
	--> Get Collector and Nest Position With Offsets <--
	collectorPos = (nest::typeof(nest) & {["Collector"] : Part}).Collector.Position
	collectorPos = Vector3.new(collectorPos.X, collectorPos.Y + nestYPosOffset, collectorPos.Z)
	nestPos = (nest::typeof(nest)&{["Nest"] : Model}).Nest:GetPivot().Position
	compareNestPos = Vector3.new(nestPos.X, collectorPos.Y, nestPos.Z)
	
	--> Get LookAt CFrame with Offsets <--
	lookAtCF = CFrame.lookAt(collectorPos, compareNestPos)
	lookX, lookY, lookZ = lookAtCF:ToOrientation()
	lookAtCF = CFrame.new(lookAtCF.Position)*CFrame.Angles(0, ((math.deg(lookY) < 0) and math.rad(-90) or math.rad(90)), 0)
	
	self.CFrame = lookAtCF*CFrame.new(0, 0, -5)*CFrame.Angles(0, math.rad(180), 0)
	self.OwnerID = player.UserId
	self.NestNum = nestNum
	self.GiveCash = true
	self.OnHold = player
	
	if not init then return end
	if not staticNest then SendMsgEvent:Fire(false, player, "[Bees]: Successfully bought a "..self.Name.."!", "Success") end
	
	DataStore.SetValue(player, BeePath.."."..self.GUID, "NestNum", nestNum)
	LinkEvent:Fire(true, "AllPlayers", self, {["Nested"] = true})
	
	setmetatable(self, BeeHandler)
	task.spawn(self.LoopCash, self)
end

function BeeHandler.WalkToBase(self : Bee, player : Player)
	if not init then BeeActionEvent:Fire(false, self.GUID, "WalkToBase", table.pack(player)) end
	
	local base : Model = PlotHandler.GetPlot(player) :: Model
	local oldNest : Model? = PlotHandler.GetBeeNest(player, self.GUID)
	local nest : Model?, nestNum : number? = PlotHandler.FindAvailableNest(player)
	local playerCash : number = DataStore.GetValue(player, CurrencyPath, "Cash") :: number
	
	local endCF : CFrame = (base::typeof(base)&{["CollectZoneCFrame"] : Part}).CollectZoneCFrame.CFrame :: CFrame
	local distance = (self.CFrame.Position - endCF.Position).Magnitude
	local dt : number = 1
	
	if self.OnHold or self.Destroyed == true then return end
	
	local function forInit()
		if not init then return end
		if not nest then
			SendMsgEvent:Fire(false, player, "[Bees]: You have max amount of bees!", "Fail")
			return "Early"
		end
		
		if oldNest then oldNest:SetAttribute("BeeGUID", nil) end

		DataStore.SetValue(player, CurrencyPath, "Cash", playerCash-self.Price)
		DataStore.SetValue(player, BeePath, self.GUID, setmetatable(self, nil))

		nest:SetAttribute("BeeGUID", self.GUID)
		LinkEvent:Fire(true, "AllPlayers", setmetatable(self, nil), {["ToBase"] = base})
		setmetatable(self, BeeHandler)
	end
	
	self.OwnerID = player.UserId
	self.Walkable = false
	self.NestNum = nestNum
	if forInit() == "Early" then return end
	
	while self.OwnerID == player.UserId and distance > 0.05 do
		distance = (self.CFrame.Position - endCF.Position).Magnitude
		self.CFrame = self.CFrame:Lerp(endCF, self.Speed*dt/distance)
		
		dt = RunService.Heartbeat:Wait()
	end
	
	if self.OwnerID == player.UserId then self:AddToNest(player, nestNum) end
end

--> Bee Path Functions <--

function BeeHandler.MoveOnPath(self : Bee)
	if not init then BeeActionEvent:Fire(false, self.GUID, "MoveOnPath") end
	
	local endCF : CFrame = CFrame.new(self.Map.End.Position)
	local distance = (self.CFrame.Position - endCF.Position).Magnitude
	local dt : number = 1

	repeat
		local playerSpeedOffset = 1 + math.log(#Players:GetPlayers(), moveLogBase)
		distance = (self.CFrame.Position - endCF.Position).Magnitude

		self.CFrame = self.CFrame:Lerp(endCF, playerSpeedOffset*self.Speed*dt/distance)

		dt = RunService.Heartbeat:Wait()
	until distance < 0.05 or not self.Walkable or self.Destroyed == true
	
	if self.Walkable == true and self.Destroyed ~= false then self:Destroy() end
end

function BeeHandler.WalkOnPath(self : Bee)
	if not init then BeeActionEvent:Fire(false, self.GUID, "WalkOnPath") end
	if self.Destroyed == true or self.Walkable == false then return end
	if typeof(self.Map) ~= "Instance" then error("Map must be specified for bee to walk!") end
	
	local function forInit()
		if not init then return end
		
		LinkEvent:Fire(true, "AllPlayers", self, {["Walking"] = true})
		setmetatable(self, BeeHandler)
	end

	self.CFrame = CFrame.new(self.Map.Start.Position)
	forInit()
	
	task.spawn(self.MoveOnPath, self)
end

--> API Functions <--

function API.Init()
	if script:GetAttribute("Init") then return end
	script:SetAttribute("Init", true)
	init = true
	
	GetBeeEvent:OnEvent(GetBee)
	GenerateEvent:OnEvent(GenerateBee)
	BeeActionEvent:OnEvent(doBeeAction)
	
	SellEvent:OnServerEvent(SellBee)
	StealEvent:OnServerEvent(StealBee)
	PurchaseEvent:OnServerEvent(PurchaseBee)
	
	Players.PlayerAdded:Connect(PlayerJoined)
end

function API.GetBee(GUID : string) : Bee?
	local getConnection : RBXScriptConnection
	local bee : Bee? = Bees[GUID]
	if init then return bee end
	
	getConnection = GetBeeEvent:OnEvent(function(senderID : string, fromInit : boolean, nonMetaBee : nonMetaBee)
		if senderID ~= requireID or not fromInit then return end
		getConnection:Disconnect()
		
		bee = setmetatable(nonMetaBee, BeeHandler)
	end)
	GetBeeEvent:Fire(false, false, requireID, GUID)
	
	while not bee do RunService.Heartbeat:Wait() end
	
	return bee
end

function API.GenerateBee(rarity : BeeRarity?, name : string?, variant : BeeVariant?, ownerID : number?) : Bee
	local beeRarity : BeeRarity = rarity or API.GenerateRarity()
	local beeName : string = name or API.GenerateBeeName(beeRarity)
	if not (BeeInfos[beeRarity] and BeeInfos[beeRarity][beeName]) then return API.GenerateBee(rarity, name, variant, ownerID) end
	if not init then return PsuedoGenerate(beeRarity, beeName, variant, ownerID) end
	
	local Bee : Bee = TableEditor.Duplicate(BeeInfos[beeRarity][beeName]) :: Bee
	Bee.Name = Bee.Name or beeName.." Bee"
	Bee.GUID = HttpService:GenerateGUID(false)
	Bee.Rarity = beeRarity
	Bee.Variant = variant or "Normal"
	Bee.OwnerID = ownerID
	
	Bee.Connections = {}
	Bee.Animations = Bee.Animations or {}
	Bee.Speed = Bee.Speed or walkAlpha
	Bee.Walkable = true
	
	Bees[Bee.GUID] = setmetatable(Bee, BeeHandler)
	return Bee
end

function API.GenerateBeeName(rarity:BeeRarity?)
	local beeNames : {string} = {}
	rarity = rarity or API.GenerateRarity()

	for beeName : string in pairs(BeeInfos[rarity]) do
		table.insert(beeNames, beeName)
	end

	return beeNames[math.random(1, #beeNames)]
end

function API.GenerateRarity() : BeeRarity
	local n = math.random(0, 100*Precisions.Rarity)
	local selectedRarity : BeeRarity
	
	for rarity : BeeRarity, numRange : NumberRange in pairs(Rarities) do
		if not (n > 100*Precisions.Rarity or (numRange.Min*Precisions.Rarity < n and n < numRange.Max*Precisions.Rarity)) then 
			continue
		end

		selectedRarity = rarity
	end

	return selectedRarity
end

return API
