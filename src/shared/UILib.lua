-- UILib: a small reusable window/tab/toggle/slider GUI library for your own Roblox games.
-- Usage:
--   local UILib = require(path.to.UILib)
--   local window = UILib.new({ Title = "My Game Menu" })
--   local tab = window:Tab("Settings")
--   tab:Toggle({ Text = "Show FPS", Default = false, Callback = function(on) ... end })
--   tab:Slider({ Text = "Volume", Min = 0, Max = 100, Default = 50, Callback = function(v) ... end })

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local UILib = {}
UILib.__index = UILib

local Tab = {}
Tab.__index = Tab

local COLORS = {
	Background = Color3.fromRGB(24, 24, 28),
	TitleBar = Color3.fromRGB(32, 32, 38),
	TabBar = Color3.fromRGB(20, 20, 24),
	TabIdle = Color3.fromRGB(28, 28, 33),
	TabActive = Color3.fromRGB(48, 90, 200),
	Control = Color3.fromRGB(38, 38, 44),
	Accent = Color3.fromRGB(70, 130, 240),
	Text = Color3.fromRGB(235, 235, 240),
	SubText = Color3.fromRGB(160, 160, 170),
}

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 6)
	c.Parent = parent
	return c
end

local function tween(obj, props, time)
	TweenService:Create(obj, TweenInfo.new(time or 0.15, Enum.EasingStyle.Quad), props):Play()
end

function UILib.new(config)
	config = config or {}

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Remove a previous copy so re-running the script doesn't stack windows.
	local existing = playerGui:FindFirstChild(config.Name or "UILibWindow")
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = config.Name or "UILibWindow"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	local main = Instance.new("Frame")
	main.Size = config.Size or UDim2.new(0, 480, 0, 320)
	main.Position = config.Position or UDim2.new(0.5, -240, 0.5, -160)
	main.BackgroundColor3 = COLORS.Background
	main.BorderSizePixel = 0
	main.Active = true
	main.Draggable = true
	main.Parent = screenGui
	corner(main, 10)

	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 36)
	titleBar.BackgroundColor3 = COLORS.TitleBar
	titleBar.BorderSizePixel = 0
	titleBar.Parent = main
	corner(titleBar, 10)

	local titleFix = Instance.new("Frame")
	titleFix.Size = UDim2.new(1, 0, 0, 10)
	titleFix.Position = UDim2.new(0, 0, 1, -10)
	titleFix.BackgroundColor3 = COLORS.TitleBar
	titleFix.BorderSizePixel = 0
	titleFix.Parent = titleBar

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -44, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = COLORS.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Title or "Window"
	title.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 26, 0, 26)
	closeBtn.Position = UDim2.new(1, -32, 0, 5)
	closeBtn.BackgroundColor3 = COLORS.Control
	closeBtn.TextColor3 = COLORS.Text
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.Text = "x"
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = titleBar
	corner(closeBtn, 6)
	closeBtn.MouseButton1Click:Connect(function()
		screenGui.Enabled = false
	end)

	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(0, 120, 1, -36)
	tabBar.Position = UDim2.new(0, 0, 0, 36)
	tabBar.BackgroundColor3 = COLORS.TabBar
	tabBar.BorderSizePixel = 0
	tabBar.Parent = main

	local tabPadding = Instance.new("UIPadding", tabBar)
	tabPadding.PaddingTop = UDim.new(0, 8)

	local tabList = Instance.new("UIListLayout", tabBar)
	tabList.Padding = UDim.new(0, 4)
	tabList.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local pageHolder = Instance.new("Frame")
	pageHolder.Size = UDim2.new(1, -120, 1, -36)
	pageHolder.Position = UDim2.new(0, 120, 0, 36)
	pageHolder.BackgroundTransparency = 1
	pageHolder.ClipsDescendants = true
	pageHolder.Parent = main

	local self = setmetatable({}, UILib)
	self._screenGui = screenGui
	self._main = main
	self._tabBar = tabBar
	self._pageHolder = pageHolder
	self._tabs = {}
	self._activeTab = nil

	return self
end

function UILib:SetEnabled(enabled)
	self._screenGui.Enabled = enabled
end

function UILib:Toggle()
	self._screenGui.Enabled = not self._screenGui.Enabled
end

function UILib:Destroy()
	self._screenGui:Destroy()
end

function UILib:Tab(name)
	local tabButton = Instance.new("TextButton")
	tabButton.Size = UDim2.new(1, -16, 0, 32)
	tabButton.BackgroundColor3 = COLORS.TabIdle
	tabButton.TextColor3 = COLORS.SubText
	tabButton.Font = Enum.Font.GothamMedium
	tabButton.TextSize = 14
	tabButton.Text = name
	tabButton.AutoButtonColor = false
	tabButton.Parent = self._tabBar
	corner(tabButton, 6)

	local page = Instance.new("ScrollingFrame")
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.Parent = self._pageHolder

	local layout = Instance.new("UIListLayout", page)
	layout.Padding = UDim.new(0, 8)
	local padding = Instance.new("UIPadding", page)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)

	local tabObj = setmetatable({ _page = page }, Tab)
	table.insert(self._tabs, { button = tabButton, page = page })

	local function activate()
		for _, t in ipairs(self._tabs) do
			t.page.Visible = false
			tween(t.button, { BackgroundColor3 = COLORS.TabIdle, TextColor3 = COLORS.SubText })
		end
		page.Visible = true
		tween(tabButton, { BackgroundColor3 = COLORS.TabActive, TextColor3 = COLORS.Text })
	end

	tabButton.MouseButton1Click:Connect(activate)

	if not self._activeTab then
		self._activeTab = tabObj
		activate()
	end

	return tabObj
end

function Tab:Label(text)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = COLORS.SubText
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = self._page
	return label
end

function Tab:Button(config)
	config = config or {}
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 34)
	btn.BackgroundColor3 = COLORS.Control
	btn.TextColor3 = COLORS.Text
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 14
	btn.Text = config.Text or "Button"
	btn.AutoButtonColor = true
	btn.Parent = self._page
	corner(btn, 6)

	btn.MouseButton1Click:Connect(function()
		if config.Callback then
			config.Callback()
		end
	end)

	return btn
end

function Tab:Toggle(config)
	config = config or {}
	local state = config.Default or false

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 34)
	holder.BackgroundColor3 = COLORS.Control
	holder.Parent = self._page
	corner(holder, 6)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -56, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.TextColor3 = COLORS.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Text or "Toggle"
	label.Parent = holder

	local track = Instance.new("Frame")
	track.Size = UDim2.new(0, 40, 0, 20)
	track.Position = UDim2.new(1, -50, 0.5, -10)
	track.BackgroundColor3 = state and COLORS.Accent or COLORS.TabIdle
	track.Parent = holder
	corner(track, 10)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
	knob.BackgroundColor3 = COLORS.Text
	knob.Parent = track
	corner(knob, 8)

	local clickArea = Instance.new("TextButton")
	clickArea.Size = UDim2.new(1, 0, 1, 0)
	clickArea.BackgroundTransparency = 1
	clickArea.Text = ""
	clickArea.Parent = holder

	clickArea.MouseButton1Click:Connect(function()
		state = not state
		tween(track, { BackgroundColor3 = state and COLORS.Accent or COLORS.TabIdle })
		tween(knob, { Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8) })
		if config.Callback then
			config.Callback(state)
		end
	end)

	return { Set = function(_, value)
		state = value
		track.BackgroundColor3 = state and COLORS.Accent or COLORS.TabIdle
		knob.Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
	end }
end

function Tab:Slider(config)
	config = config or {}
	local min = config.Min or 0
	local max = config.Max or 100
	local value = math.clamp(config.Default or min, min, max)

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 50)
	holder.BackgroundColor3 = COLORS.Control
	holder.Parent = self._page
	corner(holder, 6)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -60, 0, 20)
	label.Position = UDim2.new(0, 10, 0, 6)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.TextColor3 = COLORS.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Text or "Slider"
	label.Parent = holder

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0, 50, 0, 20)
	valueLabel.Position = UDim2.new(1, -60, 0, 6)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 13
	valueLabel.TextColor3 = COLORS.Accent
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = tostring(value)
	valueLabel.Parent = holder

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -20, 0, 6)
	barBg.Position = UDim2.new(0, 10, 1, -16)
	barBg.BackgroundColor3 = COLORS.TabIdle
	barBg.Parent = holder
	corner(barBg, 3)

	local fraction = (value - min) / (max - min)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(fraction, 0, 1, 0)
	fill.BackgroundColor3 = COLORS.Accent
	fill.Parent = barBg
	corner(fill, 3)

	local dragging = false

	local function setFromX(x)
		local relative = math.clamp((x - barBg.AbsolutePosition.X) / barBg.AbsoluteSize.X, 0, 1)
		value = math.floor(min + relative * (max - min) + 0.5)
		fill.Size = UDim2.new(relative, 0, 1, 0)
		valueLabel.Text = tostring(value)
		if config.Callback then
			config.Callback(value)
		end
	end

	barBg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)

	local UserInputService = game:GetService("UserInputService")
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return { Set = function(_, v)
		value = math.clamp(v, min, max)
		local f = (value - min) / (max - min)
		fill.Size = UDim2.new(f, 0, 1, 0)
		valueLabel.Text = tostring(value)
	end }
end

function Tab:TextBox(config)
	config = config or {}

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 34)
	holder.BackgroundColor3 = COLORS.Control
	holder.Parent = self._page
	corner(holder, 6)

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -20, 1, -10)
	box.Position = UDim2.new(0, 10, 0, 5)
	box.BackgroundTransparency = 1
	box.Font = Enum.Font.Gotham
	box.TextSize = 13
	box.TextColor3 = COLORS.Text
	box.PlaceholderText = config.Placeholder or ""
	box.PlaceholderColor3 = COLORS.SubText
	box.Text = config.Default or ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = holder

	box.FocusLost:Connect(function(enterPressed)
		if config.Callback then
			config.Callback(box.Text, enterPressed)
		end
	end)

	return box
end

return UILib
