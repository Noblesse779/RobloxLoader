-- Sends Discord webhook notifications for game events.
-- Only the server can call HttpService, and the destination URL lives here in server-only
-- code -- never accept a webhook URL from the client, or anyone could redirect your
-- notifications (or use your game as an open relay) to a URL of their choosing.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

-- Fill this in with your own Discord webhook URL (Server Settings > Integrations > Webhooks).
-- Remember to enable HttpService: Game Settings > Security > Allow HTTP Requests.
local DISCORD_WEBHOOK_URL = ""

local COOLDOWN_SECONDS = 5
local lastSent = {}

local function postToDiscord(content)
	if DISCORD_WEBHOOK_URL == "" then
		warn("[WebhookRelay] DISCORD_WEBHOOK_URL is not set.")
		return
	end

	local ok, err = pcall(function()
		HttpService:PostAsync(DISCORD_WEBHOOK_URL, HttpService:JSONEncode({ content = content }))
	end)
	if not ok then
		warn("[WebhookRelay] Failed to send webhook:", err)
	end
end

local sendWebhookMessage = Remotes.getOrCreate("SendWebhookMessage")

sendWebhookMessage.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastSent[player.UserId] and now - lastSent[player.UserId] < COOLDOWN_SECONDS then
		return
	end
	lastSent[player.UserId] = now

	postToDiscord(string.format("Test notification from **%s**", player.Name))
end)

Players.PlayerRemoving:Connect(function(player)
	lastSent[player.UserId] = nil
end)
