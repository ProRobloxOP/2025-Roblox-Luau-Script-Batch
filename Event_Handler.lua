--> Services <--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--> Replicated Modules <--
local repModules = ReplicatedStorage:WaitForChild("Modules")

--> Replicated Utilities <--
local repUtilities = repModules:WaitForChild("Utils")

--> Replicated Tools <--
local repTools = repUtilities:WaitForChild("Tools")

--> Required Modules <--
local PathLocator = require(repTools:WaitForChild("PathLocator"))
local TableEditor = require(repTools:WaitForChild("TableEditorV1"))

--> Constants / Others <-- 

--> Tables & Dictionaries (OOP) <--
local API = {}

local CustomEvents = {
	["BindableEvent"] = {},
	["RemoteEvent"] = {},
	["Storage"] = {}
}
local EventStorage = CustomEvents.Storage
local CustomRemotes = CustomEvents.RemoteEvent
local CustomBindables = CustomEvents.BindableEvent

--> Indexes <--
CustomRemotes.__index = CustomRemotes
CustomBindables.__index = CustomBindables

--> Types <--
export type CustomRemote = typeof(setmetatable({}, CustomRemotes)) & {
	["Object"] : RemoteEvent
} & CustomEvent

export type CustomBindable = typeof(setmetatable({}, CustomBindables)) & {
	["Object"] : BindableEvent
} & CustomEvent

export type CustomEvent = {
	["Object"] : RemoteEvent | BindableEvent,
	["Connections"] : {RBXScriptConnection},

	["Destroy"] : (CustomEvent : CustomEvent, objectDestroyed : boolean?) -> ()
}

--> Local Functions <--

--[[
	Handles Destroying Custom Events.
	
	CustomEvent : Custom Event to be destroyed.
	objectDestroyed : Determines if the object is already destroyed.
]]
local function DestroyCustomEvent(CustomEvent : CustomEvent, objectDestroyed : boolean?)
	if not objectDestroyed then 
		CustomEvent.Object:Destroy() 
		return
	end

	for _, connection : RBXScriptConnection in pairs(CustomEvent.Connections) do
		connection:Disconnect()
	end
	EventStorage[CustomEvent.Object.Name] = nil
end

--> Custom Remote Functions <--

--[[
	Handles a server event fired from a client. For a wait function, refer back to the object. Note: Compressed args are automatically unstringified.
	
	_callback : Function to be called when the event is fired.
]]
function CustomRemotes.OnServerEvent(self : CustomRemote, _callback : (player : Player, ...any?) -> ()) : RBXScriptConnection
	if RunService:IsClient() then error("Cannot call [OnServerEvent] on client...") end

	local rbxRemote : RemoteEvent = self.Object
	local connection : RBXScriptConnection

	connection = rbxRemote.OnServerEvent:Connect(function(player : Player, compressAsString : string, args)
		if compressAsString then args = TableEditor.Unstringify(args::string) else
			if #args < 1 then _callback(player) return end
		end
		_callback(player, table.unpack(args))
	end)

	table.insert(self.Connections, connection)
	return connection
end

--[[
	Handles a client event fired from a server. For a wait function, refer back to the object. Note: Compressed args are automatically unstringified.
	
	_callback : Function to be called when the event is fired.
]]
function CustomRemotes.OnClientEvent(self : CustomRemote, _callback : (...any?) -> ()) : RBXScriptConnection
	if RunService:IsServer() then error("Cannot call [OnClientEvent] on server...") end

	local rbxRemote : RemoteEvent = self.Object
	local connection : RBXScriptConnection

	connection = rbxRemote.OnClientEvent:Connect(function(compressAsString : string, args)
		if compressAsString then args = TableEditor.Unstringify(args::string) else
			if #args < 1 then _callback() return end
		end

		_callback(table.unpack(args))
	end)

	table.insert(self.Connections, connection)
	return connection
end

--[[
	Fires the Custom Remote via. object and will compress the arguments if given.
	
	compressAsString : Determines if the arguments should be converted to string and compressed (used to reduce recv).
	fireToFromServer : Specific to server, clients should set as nil.
	... : Extra arguments that are exchanged.
]]
function CustomRemotes.Fire(self : CustomRemote, compressAsString : boolean, fireToFromServer : (Player | "AllPlayers")?, ... : any?)
	local args = table.pack(...)
	local rbxRemote : RemoteEvent = self.Object
	if type(compressAsString) ~= "boolean" then error("Need To Specify Compressability!") end

	args.n = nil
	args = (compressAsString == true) and TableEditor.Stringify(args) or args

	if RunService:IsClient() then
		rbxRemote:FireServer(compressAsString, args)
		return
	end

	if not fireToFromServer then error("Cannot fire custom remote ["..rbxRemote.Name.."] without specifying player...") end
	if fireToFromServer == "AllPlayers" then
		rbxRemote:FireAllClients(compressAsString, args)
		return
	end

	rbxRemote:FireClient(fireToFromServer::Player, compressAsString, args)
end

--> Custom Bindable Functions <--

--[[
	Handles a bindable event, refer to the obejct for a wait funciton. Note: Compressed args are automatically unstringified.
	
	_callback : Function to be called when the event is fired.
]]
function CustomBindables.OnEvent(self : CustomBindable, _callback : (...any?) -> ()) : RBXScriptConnection
	local rbxBindable : BindableEvent = self.Object
	local connection : RBXScriptConnection

	connection = rbxBindable.Event:Connect(function(compressAsString : string, args)
		if compressAsString then args = TableEditor.Unstringify(args::string) else
			if #args < 1 then _callback() return end
		end

		_callback(table.unpack(args::{any}))
	end)

	table.insert(self.Connections, connection)
	return connection
end

--[[
	Fires the Custom Bindable via. object and will compress the arguments if given.
	
	compressAsString : Determines if the arguments should be converted to string and compressed (used to reduce recv).
	... : Extra arguments that are exchanged.
]]
function CustomBindables.Fire(self : CustomBindable, compressAsString : boolean, ... : any?)
	local args = table.pack(...)
	local rbxBindable : BindableEvent = self.Object
	if type(compressAsString) ~= "boolean" then error("Need To Specify Compressability!") end

	args.n = nil
	args = (compressAsString == true) and TableEditor.Stringify(args) or args
	rbxBindable:Fire(compressAsString, args)
end

--> Custom Event Functions <--

function CustomEvents.OnObjectDestroying(CustomEvent : CustomEvent)
	local rbxEvent = CustomEvent.Object
	local connection
	connection = rbxEvent.Destroying:Connect(function()
		CustomEvent:Destroy(true)
		connection:Disconnect()
	end)

	table.insert(CustomEvent.Connections, connection)
end

--> API Functions <--

--[[
	Creates a new Roblox event given a parent.
	
	_parent : Instance to parent to.
	eventType : Type of event to be created.
]]
function API.CreateRBXEvent(_parent : Instance, eventType : "Remote" | "Bindable") : RemoteEvent | BindableEvent
	local rbxEvent : RemoteEvent | BindableEvent = Instance.new(eventType.."Event");
	(rbxEvent::Instance).Parent = _parent
	return rbxEvent
end

--[[
	Checks if a given instance is a Roblox Event (Remote / Bindable)
	
	_instance : Instance to be checked.
]]
function API.IsAnEvent(_instance : Instance)
	return _instance:IsA("RemoteEvent") or _instance:IsA("BindableEvent")
end

--[[
	Gets an event specified by name, and path if specified. If the event was already stored, then path is not needed. Note: All pre-runtime remotes are pre-stored.
	
	_name : Name of the event.
	_path : Path of the event ([Service].[Folder]+.[Remote Parent].[Remote]) (eg. ReplicatedStorage.Remotes.Systems.UnitSystem.Summon).
	_createIfMissing : Only creates a new event if a one is not found. Must specify path if included.
]]
function API.GetEvent(_name : string, _path : RemoteEvent | BindableEvent | string, _createIfMissing : ("Remote" | "Bindable")?) : (CustomRemote | CustomBindable)?
	local lastPathItem
	local CustomEvent : CustomEvent = {} :: CustomEvent

	local rbxEvent : RemoteEvent | BindableEvent

	if _createIfMissing and not _path then 
		error("Path not specified for custom remote creation...") 
	end

	if EventStorage[{_name, _path}] then return EventStorage[{_name, _path}] end
	lastPathItem = (typeof(_path) == "Instance") and _path or PathLocator.GetPathInstance((_path::string)..".".._name, true, nil, true)

	if not (_createIfMissing or (lastPathItem and API.IsAnEvent(lastPathItem))) then 
		return 
	end

	rbxEvent = (typeof(_path) == "Instance") and _path or lastPathItem
	rbxEvent = (API.IsAnEvent(rbxEvent)) and rbxEvent or API.CreateRBXEvent(lastPathItem, _createIfMissing::"Remote" | "Bindable")
	CustomEvent.Object = rbxEvent
	CustomEvent.Connections = {}

	CustomEvent.Destroy = DestroyCustomEvent

	CustomEvents.OnObjectDestroying(CustomEvent)
	setmetatable(CustomEvent, CustomEvents[rbxEvent.ClassName])
	EventStorage[{_name, _path}] = CustomEvent

	return CustomEvent :: (CustomRemote | CustomBindable)
end

return API
