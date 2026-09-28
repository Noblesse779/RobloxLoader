-- Shared helper for creating/finding RemoteEvents.
-- Server code calls Remotes.getOrCreate(name); client code calls Remotes.wait(name).
-- Keeping this in one place avoids "Remotes doesn't exist yet" race conditions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "RemoteEvents"

local Remotes = {}

function Remotes.getOrCreate(name)
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end

	return remote
end

function Remotes.wait(name)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name)
end

return Remotes
