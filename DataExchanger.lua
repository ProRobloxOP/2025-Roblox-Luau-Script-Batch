--> Services <--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
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
local Event_Handler = require(script:WaitForChild("Event_Handler"))

--> Tables & Dictionaries (OOP) <--
local Function_Handler = {}
local API = {
	["Functions"] = Function_Handler,
	["Events"] = Event_Handler
}

local CustomFunctions = {
	["BindableEvent"] = {},
	["RemoteEvent"] = {},
	["Storage"] = {}
}
local EventStorage = CustomFunctions.Storage
local CustomRemotes = CustomFunctions.RemoteEvent
local CustomBindables = CustomFunctions.BindableEvent

--> Indexes <--
CustomRemotes.__index = CustomRemotes
CustomBindables.__index = CustomBindables

--> Types <--

export type CustomRemoteEvent = Event_Handler.CustomRemote
export type CustomBindableEvent = Event_Handler.CustomBindable
export type CustomEvent = Event_Handler.CustomEvent

export type CustomRemoteFunction = typeof(setmetatable({}, CustomRemotes)) & {
	["Object"] : RemoteEvent
} & CustomFunction

export type CustomBindableFunction = typeof(setmetatable({}, CustomBindables)) & {
	["Object"] : BindableEvent
} & CustomFunction

export type CustomFunction = CustomEvent

--> Custom Remote Functions <--

--[[
	Handles a server event fired from a client. For a wait function, refer back to the object. Note: Compressed args are automatically unstringified.
	
	_callback : Function to be called when the event is fired.
]]
function CustomRemotes.OnServerEvent(self : CustomRemoteFunction, compressReturn : boolean, _callback : (player : Player, ...any?) -> ()) : RBXScriptConnection
	if RunService:IsClient() then error("Cannot call [OnServerEvent] on client...") end

	local rbxRemote : RemoteEvent = self.Object
	local connection : RBXScriptConnection

	connection = rbxRemote.OnServerEvent:Connect(function(player : Player, JobId : string, action : string, compressAsString : string, args)
		if action ~= "Invoke" then return end
		if compressAsString then args = TableEditor.Unstringify(args::string) else
			if #args < 1 then _callback(player) return end
		end
		
		--> Fire Back The Return Values <--
		local returnVals = _callback(player, table.unpack(args::{any}))
		returnVals = (compressReturn == true) and TableEditor.Stringify(returnVals) or returnVals

		rbxRemote:FireServer(JobId, "Return", compressReturn, returnVals)
	end)

	table.insert(self.Connections, connection)
	return connection
end

--[[
	Handles a client event fired from a server. For a wait function, refer back to the object. Note: Compressed args are automatically unstringified.
	
	_callback : Function to be called when the event is fired.
]]
function CustomRemotes.OnClientInvoke(self : CustomRemoteFunction, compressReturn : boolean, _callback : (...any?) -> ()) : RBXScriptConnection
	if RunService:IsServer() then error("Cannot call [OnClientEvent] on server...") end

	local rbxRemote : RemoteEvent = self.Object
	local connection : RBXScriptConnection

	connection = rbxRemote.OnClientEvent:Connect(function(JobId : string, action : string, compressAsString : string, args)
		if action ~= "Invoke" then return end
		if compressAsString then args = TableEditor.Unstringify(args::string) else
			if #args < 1 then _callback() return end
		end
		
		--> Fire Back The Return Values <--
		local returnVals = _callback(table.unpack(args::{any}))
		returnVals = (compressReturn == true) and TableEditor.Stringify(returnVals) or returnVals

		rbxRemote:FireServer(JobId, "Return", compressReturn, returnVals)
	end)

	table.insert(self.Connections, connection)
	return connection
end

--[[
	Fires the Custom Remote via. object and will compress the arguments if given.
	
	compressAsString : Determines if the arguments should be converted to string and compressed (used to reduce recv).
	fireToFromServer : Specific to server, clients should set as nil.
	... : Extra arguments that are exchanged.
	
	Returns the client (server only) and found Invoke values.
]]
function CustomRemotes.Invoke(self : CustomRemoteFunction, compressAsString : boolean, fireToFromServer : (Player | "AllPlayers")?, ... : any?) : ...any?
	local rbxRemote : RemoteEvent = self.Object
	local jobId = HttpService:GenerateGUID(false)
	local onClient = RunService:IsClient()
	local args = table.pack(...)

	local connection : RBXScriptConnection
	local returnVal = nil
	
	if type(compressAsString) ~= "boolean" then error("Need To Specify Compressability!") end
	
	--> Connection To Return <--
	local function ClientReturn (JobId : string, action : string, compressReturn : boolean, args)
		if JobId ~= jobId or action ~= "Return" then return end 
		if compressReturn then args = TableEditor.Unstringify(args::string) else
			if #args < 1 then returnVal = {} connection:Disconnect() return end
		end

		returnVal = {table.unpack(args::{any})}
		connection:Disconnect()
	end
	
	local function ServerReturn(player : Player, JobId : string, action : string, compressReturn : boolean, args)
		if JobId ~= jobId or action ~= "Return" then return end 
		if compressReturn then args = TableEditor.Unstringify(args::string) else
			if #args < 1 then returnVal = {player} connection:Disconnect() return end
		end

		returnVal = {player, table.unpack(args::{any})}
		connection:Disconnect()
	end
	
	connection = (onClient == true) and rbxRemote.OnClientEvent:Connect(ClientReturn) or rbxRemote.OnServerEvent:Connect(ServerReturn)
	
	--> Event Firing <--
	args.n = nil
	args = (compressAsString == true) and TableEditor.Stringify(args) or args

	if RunService:IsClient() then
		rbxRemote:FireServer(jobId, "Invoke", compressAsString, args)
		return
	end

	if not fireToFromServer then error("Cannot fire custom remote ["..rbxRemote.Name.."] without specifying player...") end
	if fireToFromServer == "AllPlayers" then
		rbxRemote:FireAllClients(jobId, "Invoke", compressAsString, args)
		return
	end

	rbxRemote:FireClient(jobId, "Invoke", fireToFromServer::Player, compressAsString, args)
	
	--> Yield Until Return Value Found <--
	repeat RunService.Heartbeat:Wait() until type(returnVal) ~= type(nil)
	return table.unpack(returnVal)
end

--> Custom Bindable Functions <--

--[[
	Handles a bindable function, refer to the obejct for a wait funciton. Note: Compressed args are automatically unstringified.
	
	compressReturn : Determines if the return values should be compressed (used to reduce recv).
	_callback : Function to be called when the function is fired.
]]
function CustomBindables.OnInvoke(self : CustomBindableFunction, compressReturn : boolean, _callback : (...any?) -> (...any?)) : RBXScriptConnection
	local rbxBindable : BindableEvent = self.Object
	local connection : RBXScriptConnection

	connection = rbxBindable.Event:Connect(function(JobId : string, action : string, compressAsString : string, args)
		if action ~= "Invoke" then return end
		if compressAsString then args = TableEditor.Unstringify(args::string) else
			if #args < 1 then _callback() return end
		end
		
		--> Fire back the return values <--
		local returnVals = _callback(table.unpack(args::{any}))
		returnVals = (compressReturn == true) and TableEditor.Stringify(returnVals) or returnVals
		
		rbxBindable:Fire(JobId, "Return", compressReturn, returnVals)
	end)

	table.insert(self.Connections, connection)
	return connection
end

--[[
	Fires the Custom Bindable via. object and will compress the arguments if given.
	
	compressAsString : Determines if the arguments should be converted to string and compressed (used to reduce recv).
	_callback : Function to be called when the function is returned.
	... : Extra arguments that are exchanged.
	
	Returns the found Invoke values.
]]
function CustomBindables.Invoke(self : CustomBindableFunction, compressAsString : boolean, ... : any?) : ...any?
	local rbxBindable : BindableEvent = self.Object
	local jobId = HttpService:GenerateGUID(false)
	local args = table.pack(...)
	
	local connection : RBXScriptConnection
	local returnVal = nil
	
	if type(compressAsString) ~= "boolean" then error("Need To Specify Compressability!") end
	
	--> Connection To Return <--
	connection = rbxBindable.Event:Connect(function(JobId : string, action : string, compressReturn : boolean, args)
		if JobId ~= jobId or action ~= "Return" then return end 
		if compressReturn then args = TableEditor.Unstringify(args::string) else
			if #args < 1 then returnVal = {} connection:Disconnect() return end
		end
		
		returnVal = {table.unpack(args::{any})}
		connection:Disconnect()
	end)
	
	--> Event Firing <--
	args.n = nil
	args = (compressAsString == true) and TableEditor.Stringify(args) or args
	rbxBindable:Fire(jobId, "Invoke", compressAsString, args)
	
	--> Yield Until Return Value Found <--
	repeat RunService.Heartbeat:Wait() until type(returnVal) ~= type(nil)
	return table.unpack(returnVal)
end
--[[
	Gets an event specified by name, and path if specified. If the event was already stored, then path is not needed. Note: All pre-runtime remotes are pre-stored.
	
	_name : Name of the event.
	_path : Path of the event ([Service].[Folder]+.[Remote Parent].[Remote]) (eg. ReplicatedStorage.Remotes.Systems.UnitSystem.Summon).
	_createIfMissing : Only creates a new event if a one is not found. Must specify path if included.
]]
function Function_Handler.GetFunction(_name : string, _path : RemoteEvent | BindableEvent | string, _createIfMissing : ("Remote" | "Bindable")?) : (CustomRemoteFunction | CustomBindableFunction)?
	local CustomFunction : CustomFunction = Event_Handler.GetEvent(_name, _path, _createIfMissing) :: (CustomRemoteFunction | CustomBindableFunction)
	setmetatable(CustomFunction, CustomFunctions[CustomFunction.Object.ClassName])

	return CustomFunction :: (CustomRemoteFunction | CustomBindableFunction)
end

return API
