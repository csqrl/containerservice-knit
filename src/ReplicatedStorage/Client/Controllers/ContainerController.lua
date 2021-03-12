--!strict
--[[
	Author: csqrl
	Date: 11-03-2021

	ContainerController
	* Receives replicated instances from the server and emits events regarding
		transactions

	Public API:
		Properties:
		* Controller.Name: string
		* Controller.RootContainer: ScreenGui?
		* Controller.Containers: Dictionary<containerId: string, container: Folder>

		Methods:
		* Controller:GetRootContainer(): Promise<ScreenGui>
		* Controller:GetContainer(containerId: string): Promise<Folder>

		Events:
		* Controller.ItemReplicated<containerId: string, instance: Instance>
--]]
local Replicated = game:GetService("ReplicatedStorage")
local ClientStorage = game:GetService("ServerStorage")
local LocalPlayer = game:GetService("Players").LocalPlayer
local RunService = game:GetService("RunService")

local Knit = require(Replicated.Knit)
local Signal = require(Knit.Util.Signal)
local Promise = require(Knit.Util.Promise)

local EStatus = require(Replicated.Enums.Status)
local PostSimulationEvent = RunService.Heartbeat

local function InstanceDestroyedListener(instance: Instance, callback: () -> any?)
	local parentConnection: RBXScriptConnection = nil

	parentConnection = instance:GetPropertyChangedSignal("Parent"):Connect(function()
		PostSimulationEvent:Wait()

		if not parentConnection.Connected then
			callback()
		end
	end)
end

local Controller = Knit.CreateController({
	Name = "ContainerController",
	Attribute = "__CONTAINER_ID__",

	RootContainerPendingCompleted = Signal.new(),
	RootContainerPending = nil,
	RootContainer = nil,

	ContainerPendingCompleted = Signal.new(),
	ContainersPending = {},
	Containers = {},

	ItemReplicated = Signal.new(),
})

function Controller:KnitStart()
	self:GetRootContainer():catch(warn)
end

function Controller:GetRootContainer()
	local ContainerService = Knit.GetService("ContainerService")

	return Promise.new(function(resolve, reject)
		if self.RootContainer then
			return resolve(self.RootContainer)
		end

		if self.RootContainerPending then
			return resolve(Promise.fromEvent(self.RootContainerPendingCompleted))
		end

		self.RootContainerPending = true

		ContainerService:RequestRootContainerHashPromise():andThen(function(hash, status)
			assert(hash, status)
			return hash
		end):catch(function(err)
			if err == EStatus.Common.NotReady then
				return Promise.fromEvent(ContainerService.RootContainerReady)
			end

			warn("Encountered an error waiting for hash:", err)

			reject(err)
		end):andThen(function(hash)
			local playerGui = LocalPlayer:WaitForChild("PlayerGui")
			local rootContainer = playerGui:WaitForChild(hash)

			self.RootContainer = rootContainer
			self.RootContainerPending = nil

			resolve(rootContainer)

			self.RootContainerPendingCompleted:Fire(rootContainer)
			self.RootContainerPendingCompleted:Destroy()
			self.RootContainerPendingCompleted = nil

			rootContainer.Parent = ClientStorage

			for _, child in ipairs(rootContainer:GetChildren()) do
				if child:GetAttribute(self.Attribute) then
					coroutine.wrap(self.GetContainer)(self, child.Name)
				end
			end

			rootContainer.ChildAdded:Connect(function(child)
				if child:GetAttribute(self.Attribute) then
					self:GetContainer(child.Name)
				end
			end)
		end)
	end)
end

function Controller:_ProcessContainerChildAdded(containerId: string, child: Instance)
	PostSimulationEvent:Wait()
	self.ItemReplicated:Fire(containerId, child)
end

function Controller:GetContainer(containerId: string)
	if self.Containers[containerId] then
		return Promise.resolve(self.Containers[containerId])
	end

	return self:GetRootContainer():andThen(function(rootContainer)
		if self.ContainersPending[containerId] then
			return Promise.fromEvent(self.ContainerPendingCompleted, function(pendingId, pendingContainer)
				if pendingId == containerId then
					return pendingContainer
				end
			end)
		end

		self.ContainersPending[containerId] = true

		local container = rootContainer:WaitForChild(containerId)

		self.Containers[containerId] = container
		self.ContainerPendingCompleted:Fire(containerId, container)

		InstanceDestroyedListener(container, function()
			self.Containers[containerId] = nil
		end)

		for _, child in ipairs(container:GetChildren()) do
			coroutine.wrap(self._ProcessContainerChildAdded)(self, containerId, child)
		end

		container.ChildAdded:Connect(function(child)
			self:_ProcessContainerChildAdded(containerId, child)
		end)

		return container
	end)
end

return Controller
