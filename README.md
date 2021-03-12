# ContainerService for [Knit](https://github.com/Sleitnick/Knit/)
ContainerService is a Service and Controller pair for [@Sleitnick](https://github.com/Sleitnick/)'s [Knit framework](https://github.com/Sleitnick/Knit/), which allows for selective replication to clients. This means that an Instance can be replicated to a specific client without it being replicated to any other client.

ContainerService uses the concept of "Containers" (hence the name), and allows multiple containers to exist on the client. This makes it easy to determine why an Instance was replicated to client and what to do with it.

## Download
* The ContainerService repository supports [Rojo](https://github.com/rojo-rbx/rojo)&mdash;You can sync ContainerService into your project.
* ContainerService can be downloaded in Roblox model format (`.rbxm` or `.rbxmx`) from the Releases tab.
* Alternatively, you can import it to your game directly from the toolbox. The link to the library page can be found below:

https://www.roblox.com/library/6506132961/ContainerService-for-Knit

## Demo
You can find an uncopylocked demo game at the link below:

https://www.roblox.com/games/6506113313/ContainerService-Knit-Demo

This demo place uses [@1ForeverHD](https://github.com/1ForeverHD)'s [ZonePlus v2 module](https://github.com/1ForeverHD/ZonePlus), which allows it to determine which room your character is in and replicate the room's furniture accordingly.

## What is a Container?
A container, simply put, is a Folder which holds Instances replicated to the client. Once the client receives an Instance from the server, it is up to your own code to determine what to do with it.

## Why not use ReplicatedStorage?
ReplicatedStorage is fine for replicating items you want accessible to all players, but not necessarily visible in the workspace; however, by storing items in ReplicatedStorage, you are still using extra bandwidth and memory on the player's device. This means increased loading times and additional data usage (important if they're playing on mobile!).

## How does it work?
ContainerService consists of two parts: **ContainerService** and **ContainerController**. ContainerService works on the server and allows your Knit services to replicate instances to players as needed. ContainerController lives on the client and responds to actions made by the server.

* A ScreenGui is created inside the Player's PlayerGui when they join the game by the server.
    * The ScreenGui has its `ResetOnSpawn` property set to `false`. This prevents any child Instances from being destroyed when the player dies.
    * A Player's PlayerGui is [only accessible to the server and the Player which it belongs to](https://developer.roblox.com/en-us/api-reference/class/PlayerGui#switch_checkbox:~:text=PlayerReplicated). This makes it the perfect target for replicating Instances to specific players.
* The client then moves this ScreenGui into ServerStorage&mdash;this keeps the PlayerGui clean of non-UI objects on the client.
    * [The contents of ServerStorage is not accessible to the client](https://developer.roblox.com/en-us/api-reference/class/ServerStorage#switch_checkbox:~:text=NotReplicated); this means by default this Service is empty on the client, which means it can be used as a client storage location.
* When the server is ready to send Instances to the client, it specifies a containerId and an Instance to send. If the container does not exist, it is created, and a clone of the Instance is sent over.
* When the client receives an Instance, an event is emitted by the ContainerController, which allows other scripts listening to this event to determine what to do with it.

## Documentation
Below is a summary of properties, methods and events exposed by ContainerService. This does not cover all members of the service; only ones relevant to developers.
### ContainerService (Server)
#### Properties
* `Service.Name: string`

#### Methods
* `Service:GetContainer(player: Player, containerId: string): Promise<Folder>`
* `Service:ClearContainer(player: Player, containerId: string): nil`
* `Service:ReplicateTo(player: Player, containerId: string, instance: Instance): Promise<clonedInstance: Instance>`
* `Service:DereplicateFrom(player: Player, instance: Instance): nil`
    * The Instance to dereplicate should be the **original Instance**, not the cloned Instance. Instances are tracked when they are cloned to players, so ContainerService knows which copies to delete when you want to dereplicate.

### ContainerController (Client)
#### Properties
* `Controller.Name: string`

#### Methods
* `Controller:GetRootContainer(): Promise<ScreenGui>`
* `Controller:GetContainer(containerId: string): Promise<Folder>`

#### Events
* `Controller.ItemReplicated<containerId: string, instance: Instance>`

### EStatus (Shared)
EStatus works as a custom "Enum," which represents the status of remote requests.

* `EStatus.Success = 100`
* `EStatus.NotReady = 200`
