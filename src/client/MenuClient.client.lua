-- Demo menu built with UILib. Shows a Tab/Toggle/Slider window wired up to the
-- server-authoritative systems in src/server (walk speed, webhook test).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UILib = require(ReplicatedStorage:WaitForChild("UILib"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local setWalkSpeed = Remotes.wait("SetWalkSpeed")
local sendWebhookMessage = Remotes.wait("SendWebhookMessage")

local window = UILib.new({ Title = "Game Menu" })

local homeTab = window:Tab("Home")
homeTab:Label("Press Right Ctrl to show/hide this menu.")
homeTab:Label("Press Tab in-game to cycle lock-on targets.")

local movementTab = window:Tab("Movement")
movementTab:Slider({
	Text = "Walk Speed",
	Min = 8,
	Max = 50,
	Default = 16,
	Callback = function(value)
		setWalkSpeed:FireServer(value)
	end,
})

local webhookTab = window:Tab("Webhook")
webhookTab:Label("Sends a test message through the server-side Discord webhook.")
webhookTab:Button({
	Text = "Send Test Notification",
	Callback = function()
		sendWebhookMessage:FireServer()
	end,
})

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightControl then
		window:Toggle()
	end
end)
