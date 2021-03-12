--!strict
--[[
	Author: csqrl
	Date: 11-03-2021

	ContainerService
	* Handles replication to individual clients

	Server API:
		Properties:
		* Service.Name: string
		* Service.Hashes: Dictionary<userId: number, hash: string>
		* Service.RootContainers: Dictionary<userId: number, rootContainer: ScreenGui>
		* Service.InstanceRefs: Dictonary<instance: Instance, Dictionary<userId: number, cloneInstance: Instance>>

		Methods:
		* Service:GetContainer(player: Player, containerId: string): Promise<Folder>
		* Service:ClearContainer(player: Player, containerId: string): nil
		* Service:ReplicateTo(player: Player, containerId: string, instance: Instance): Promise<Instance>
		* Service:DereplicateFrom(player: Player, instance: Instance): nil

		Events:
		* Service.PendingContainerCompleted<userId: number, containerId: string>

	Client API:
		Methods:
		* Service:RequestRootContainerHash(): (hash: string?, statusCode: number)

		Events:
		* Service.RootContainerReady<hash: string>
--]]
local Replicated = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Knit = require(Replicated.Knit)
local Signal = require(Knit.Util.Signal)
local Promise = require(Knit.Util.Promise)
local RemoteSignal = require(Knit.Util.Remote.RemoteSignal)

local EStatus = require(Replicated.Enums.Status)
local PostSimulationEvent = RunService.Heartbeat

type Promise<T> = typeof(Promise)

local function InstanceDestroyedListener(instance: Instance, callback: () -> any?)
	local parentConnection: RBXScriptConnection = nil

	parentConnection = instance:GetPropertyChangedSignal("Parent"):Connect(function()
		PostSimulationEvent:Wait()

		if not parentConnection.Connected then
			callback()
		end
	end)
end

local Service = Knit.CreateService({
	Name = "ContainerService",
	Attribute = "__CONTAINER_ID__",

	Hashes = {},
	RootContainers = {},
	PendingContainers = {},
	PendingContainerCompleted = Signal.new(),
	InstanceRefs = {},

	Client = {
		RootContainerReady = RemoteSignal.new(),
	},
})

function Service:KnitInit()
	for _, player in ipairs(Players:GetPlayers()) do
		coroutine.wrap(self._PlayerInit)(self, player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_PlayerInit(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_PlayerDeinit(player)
	end)
end

function Service:_PlayerInit(player: Player)
	local containerHash = HttpService:GenerateGUID()
	local userId = player.UserId

	self.Hashes[userId] = containerHash
	self.RootContainers[userId] = Promise.new(function(resolve)
		local container = Instance.new("ScreenGui")
		container.Name = containerHash
		container.ResetOnSpawn = false
		container.Parent = player:WaitForChild("PlayerGui")

		resolve(container)
		self.Client.RootContainerReady:Fire(player, containerHash)
	end)
end

function Service:_PlayerDeinit(player: Player)
	local userId = player.UserId

	self.Hashes[userId] = nil
	self.RootContainers[userId] = nil

	for instanceRef, cloneRefs in pairs(self.InstanceRefs) do
		for userIdRef, _ in pairs(cloneRefs) do
			if userIdRef == userId then
				self.InstanceRefs[instanceRef][userIdRef] = nil
			end
		end
	end
end

function Service:GetContainer(player: Player, containerId: string): Promise<Folder>
	local userId = player.UserId

	if not self.RootContainers[userId] then
		return Promise.reject(EStatus.Common.NotReady)
	end

	if not self.PendingContainers[userId] then
		self.PendingContainers[userId] = {}
	end

	return self.RootContainers[userId]:andThen(function(rootContainer)
		local container = rootContainer:FindFirstChild(containerId)

		if container then
			return container
		end

		if self.PendingContainers[userId][containerId] then
			return Promise.fromEvent(self.PendingContainerCompleted, function(pendingUserId, pendingContainerId)
				return pendingUserId == userId and pendingContainerId == containerId
			end):andThen(function()
				return self:GetContainer(player, containerId)
			end)
		end

		self.PendingContainers[userId][containerId] = true

		container = Instance.new("Folder")
		container:SetAttribute(self.Attribute, containerId)
		container.Name = containerId
		container.Parent = rootContainer

		self.PendingContainers[userId][containerId] = nil
		self.PendingContainerCompleted:Fire(userId, containerId)

		return container
	end)
end

function Service:ClearContainer(player: Player, containerId: string): Promise<nil>
	return self:GetContainer(player, containerId):andThen(function(container)
		container:ClearAllChildren()
	end)
end

function Service:ReplicateTo(player: Player, containerId: string, instance: Instance): Promise<Instance>
	local userId = player.UserId

	if not self.InstanceRefs[instance] then
		self.InstanceRefs[instance] = {}
	end

	if self.InstanceRefs[instance][userId] then
		return Promise.resolve(self.InstanceRefs[instance][userId])
	end

	return self:GetContainer(player, containerId):andThen(function(container)
		local cloneInstance = instance:Clone()
		self.InstanceRefs[instance][userId] = cloneInstance

		cloneInstance.Parent = container

		InstanceDestroyedListener(cloneInstance, function()
			if self.InstanceRefs[instance][userId] == cloneInstance then
				self.InstanceRefs[instance][userId] = nil
			end
		end)

		return cloneInstance
	end)
end

function Service:DereplicateFrom(player: Player, instance: Instance)
	local userId = player.UserId
	local instanceRef = self.InstanceRefs[instance]

	if instanceRef and instanceRef[userId] then
		instanceRef[userId]:Destroy()
	end
end

function Service.Client:RequestRootContainerHash(player: Player): (string?, number)
	local userId = player.UserId
	local rootContainerHash = self.Server.Hashes[userId]

	if rootContainerHash then
		return rootContainerHash, EStatus.Common.Success
	end

	return nil, EStatus.Common.NotReady
end

return Service
