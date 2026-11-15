--[[
	Helen Keller Experience  (v2 - touch mapping)
	Client-side LocalScript. Put it in StarterPlayer > StarterPlayerScripts
	(or run it from your executor/test environment as a LocalScript).

	What it does:
	  * Blacks out the screen (no sight)
	  * Silences every Sound, including ones added later (no hearing)
	  * Hides chat, player list and other CoreGui
	  * Anything you touch gets "mapped": a faint outline of it appears in
	    the blackout and stays there. Touch it again and it pulses brighter,
	    then slowly fades back to its faint resting glow.
	  * A line of text describes what you felt, and gamepads rumble
	  * Press H to toggle the experience on/off

	How the mapping works:
	  A ViewportFrame sits on top of the black overlay. Each touched part is
	  cloned into it (clone only, the real world is never changed) and the
	  viewport camera is synced to your real camera every frame, so outlines
	  line up with the real world.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HapticService = game:GetService("HapticService")

local player = Players.LocalPlayer

--// CONFIG
local CONFIG = {
	ToggleKey = Enum.KeyCode.H,
	FadeInTime = 2.5,
	TouchTextTime = 1.2,
	TouchCooldown = 0.35,
	Haptics = true,
	ShowTitle = true,

	-- touch mapping
	MapTouched = true,
	MaxMapped = 300,            -- cap so a huge map can't tank performance
	MapFloor = false,           -- false = ignore the ground you're standing on
	MapPlayers = false,         -- false = don't map other players
	OutlineColor = Color3.fromRGB(190, 210, 255),
	PulseTransparency = 0.1,    -- outline brightness right when touched
	RestTransparency = 0.82,    -- faint resting outline (higher = fainter)
	FillTransparency = 0.95,    -- ghost fill inside the outline (1 = outline only)
	FadeBackTime = 6,           -- seconds to fade from pulse back to resting
	OutlineThickness = 0.03,
}

local enabled = false

--// UI
local gui = Instance.new("ScreenGui")
gui.Name = "HelenKellerExperience"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- layer 1: the black
local blackout = Instance.new("Frame")
blackout.Name = "Blackout"
blackout.Size = UDim2.fromScale(1, 1)
blackout.BackgroundColor3 = Color3.new(0, 0, 0)
blackout.BackgroundTransparency = 1
blackout.BorderSizePixel = 0
blackout.ZIndex = 1
blackout.Parent = gui

-- layer 2: the touch map (ghosts of everything you've felt)
local viewport = Instance.new("ViewportFrame")
viewport.Name = "TouchMap"
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundTransparency = 1
viewport.BorderSizePixel = 0
viewport.ZIndex = 2
viewport.Ambient = Color3.new(1, 1, 1)
viewport.LightColor = Color3.new(1, 1, 1)
viewport.Parent = gui

local vpCamera = Instance.new("Camera")
vpCamera.Name = "MapCamera"
vpCamera.Parent = viewport
viewport.CurrentCamera = vpCamera

local mapFolder = Instance.new("Folder")
mapFolder.Name = "Mapped"
mapFolder.Parent = viewport

-- layer 3: text
local textLayer = Instance.new("Frame")
textLayer.Name = "TextLayer"
textLayer.Size = UDim2.fromScale(1, 1)
textLayer.BackgroundTransparency = 1
textLayer.ZIndex = 3
textLayer.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.45)
title.Size = UDim2.fromOffset(600, 60)
title.BackgroundTransparency = 1
title.Font = Enum.Font.Garamond
title.Text = "Helen Keller Experience"
title.TextColor3 = Color3.fromRGB(235, 235, 235)
title.TextSize = 42
title.TextTransparency = 1
title.Parent = textLayer

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 0.5)
hint.Position = UDim2.fromScale(0.5, 0.53)
hint.Size = UDim2.fromOffset(600, 30)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Garamond
hint.Text = "No sight. No sound. Only touch.  (" .. CONFIG.ToggleKey.Name .. " to exit)"
hint.TextColor3 = Color3.fromRGB(150, 150, 150)
hint.TextSize = 20
hint.TextTransparency = 1
hint.Parent = textLayer

local touchLabel = Instance.new("TextLabel")
touchLabel.Name = "TouchLabel"
touchLabel.AnchorPoint = Vector2.new(0.5, 0.5)
touchLabel.Position = UDim2.fromScale(0.5, 0.85)
touchLabel.Size = UDim2.fromOffset(600, 40)
touchLabel.BackgroundTransparency = 1
touchLabel.Font = Enum.Font.Garamond
touchLabel.Text = ""
touchLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
touchLabel.TextSize = 28
touchLabel.TextTransparency = 1
touchLabel.Parent = textLayer

--// AUDIO (mute everything, restore on exit)
local originalVolumes = {}   -- [Sound] = original volume
local volumeConns = {}       -- [Sound] = RBXScriptConnection
local descendantConns = {}

local function muteSound(sound)
	if originalVolumes[sound] == nil then
		originalVolumes[sound] = sound.Volume
	end
	sound.Volume = 0
	if not volumeConns[sound] then
		volumeConns[sound] = sound:GetPropertyChangedSignal("Volume"):Connect(function()
			if enabled and sound.Volume ~= 0 then
				originalVolumes[sound] = sound.Volume
				sound.Volume = 0
			end
		end)
	end
end

local function muteAll()
	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("Sound") then
			muteSound(inst)
		end
	end
	table.insert(descendantConns, game.DescendantAdded:Connect(function(inst)
		if enabled and inst:IsA("Sound") then
			muteSound(inst)
		end
	end))
end

local function restoreAudio()
	for _, c in ipairs(descendantConns) do
		c:Disconnect()
	end
	table.clear(descendantConns)

	for _, conn in pairs(volumeConns) do
		conn:Disconnect()
	end
	table.clear(volumeConns)

	for sound, vol in pairs(originalVolumes) do
		if sound and sound.Parent then
			sound.Volume = vol
		end
	end
	table.clear(originalVolumes)
end

--// TOUCH MAP
local mapped = {}       -- [realPart] = { ghost = Part, box = SelectionBox, tween = Tween? }
local mappedCount = 0
local renderConn

local function pulse(record)
	if record.tween then
		record.tween:Cancel()
	end
	record.box.Transparency = CONFIG.PulseTransparency
	record.tween = TweenService:Create(
		record.box,
		TweenInfo.new(CONFIG.FadeBackTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = CONFIG.RestTransparency }
	)
	record.tween:Play()
end

local function unmap(realPart)
	local record = mapped[realPart]
	if not record then return end
	if record.tween then
		record.tween:Cancel()
	end
	record.ghost:Destroy()
	mapped[realPart] = nil
	mappedCount -= 1
end

local function clearMap()
	for realPart in pairs(mapped) do
		unmap(realPart)
	end
	mapFolder:ClearAllChildren()
	mappedCount = 0
end

local function mapPart(hit)
	local existing = mapped[hit]
	if existing then
		pulse(existing)
		return
	end
	if mappedCount >= CONFIG.MaxMapped then return end
	if hit:IsA("Terrain") then return end

	local ok, ghost = pcall(function()
		return hit:Clone()
	end)
	if not ok or not ghost then return end -- Archivable = false parts can't be cloned

	ghost:ClearAllChildren()
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanTouch = false
	ghost.CanQuery = false
	ghost.CastShadow = false
	ghost.Material = Enum.Material.Neon
	ghost.Color = CONFIG.OutlineColor
	ghost.Transparency = CONFIG.FillTransparency
	ghost.Reflectance = 0
	if ghost:IsA("MeshPart") then
		pcall(function() ghost.TextureID = "" end)
	end

	local box = Instance.new("SelectionBox")
	box.Adornee = ghost
	box.Color3 = CONFIG.OutlineColor
	box.LineThickness = CONFIG.OutlineThickness
	box.SurfaceTransparency = 1
	box.Transparency = CONFIG.PulseTransparency
	box.Parent = ghost

	ghost.CFrame = hit.CFrame
	ghost.Parent = mapFolder

	local record = { ghost = ghost, box = box }
	mapped[hit] = record
	mappedCount += 1
	pulse(record)

	-- if the real part is removed from the world, forget it
	hit.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unmap(hit)
		end
	end)
end

local function syncMap()
	local cam = workspace.CurrentCamera
	if cam then
		vpCamera.CFrame = cam.CFrame
		vpCamera.FieldOfView = cam.FieldOfView
	end
	for realPart, record in pairs(mapped) do
		if realPart.Parent then
			record.ghost.CFrame = realPart.CFrame
			record.ghost.Size = realPart.Size
		end
	end
end

--// TOUCH SENSE
local lastTouch = 0
local touchTween

local materialFeel = {
	Grass = "soft, prickly blades",
	Sand = "fine, gritty grains",
	Wood = "grainy and warm",
	WoodPlanks = "grainy and warm",
	Metal = "cold and smooth",
	DiamondPlate = "cold, ridged metal",
	Concrete = "rough and solid",
	Brick = "rough, blocky edges",
	Cobblestone = "uneven stones",
	Glass = "smooth and slick",
	Ice = "freezing and slippery",
	Snow = "cold and powdery",
	Fabric = "soft weave",
	Plastic = "smooth and light",
	SmoothPlastic = "smooth and light",
	Water = "wet",
	Slate = "flat, cool stone",
	Granite = "hard, cool stone",
	Marble = "polished, cool stone",
	Neon = "faintly warm",
}

local function rumble(strength)
	if not CONFIG.Haptics then return end
	pcall(function()
		if HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1)
			and HapticService:IsMotorSupported(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small) then
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, strength)
			task.delay(0.15, function()
				pcall(function()
					HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
				end)
			end)
		end
	end)
end

-- is this part basically the ground under the player's feet?
local function isFloor(hit)
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return false end

	local legHeight = hum.RigType == Enum.HumanoidRigType.R6 and 2 or hum.HipHeight
	local feetY = root.Position.Y - root.Size.Y / 2 - legHeight
	local topY = hit.Position.Y + hit.Size.Y / 2
	return topY <= feetY + 0.7
end

local function feel(hit)
	if not enabled then return end

	local char = player.Character
	if char and hit:IsDescendantOf(char) then return end

	local model = hit:FindFirstAncestorOfClass("Model")
	local isPlayer = model ~= nil and Players:GetPlayerFromCharacter(model) ~= nil

	if not CONFIG.MapFloor and not isPlayer and isFloor(hit) then return end

	-- map it (every touch pulses it, even during the text cooldown)
	if CONFIG.MapTouched and (CONFIG.MapPlayers or not isPlayer) then
		mapPart(hit)
	end

	local now = os.clock()
	if now - lastTouch < CONFIG.TouchCooldown then return end
	lastTouch = now

	local what
	if isPlayer then
		what = "someone's hand? a person is here."
	else
		what = materialFeel[hit.Material.Name] or hit.Material.Name:lower()
	end

	touchLabel.Text = "you feel something: " .. what
	touchLabel.TextTransparency = 0.35
	rumble(0.5)

	if touchTween then touchTween:Cancel() end
	touchTween = TweenService:Create(
		touchLabel,
		TweenInfo.new(CONFIG.TouchTextTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1 }
	)
	touchTween:Play()
end

local function hookCharacter(char)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Touched:Connect(feel)
		end
	end
	char.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.Touched:Connect(feel)
		end
	end)
end

if player.Character then
	hookCharacter(player.Character)
end
player.CharacterAdded:Connect(hookCharacter)

--// TOGGLE
local function setEnabled(state)
	if state == enabled then return end
	enabled = state

	if state then
		gui.Parent = player:WaitForChild("PlayerGui")
		muteAll()
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)

		renderConn = RunService.RenderStepped:Connect(syncMap)

		TweenService:Create(
			blackout,
			TweenInfo.new(CONFIG.FadeInTime, Enum.EasingStyle.Sine),
			{ BackgroundTransparency = 0 }
		):Play()

		if CONFIG.ShowTitle then
			TweenService:Create(title, TweenInfo.new(1.5), { TextTransparency = 0 }):Play()
			TweenService:Create(hint, TweenInfo.new(1.5), { TextTransparency = 0.2 }):Play()
			task.delay(5, function()
				if enabled then
					TweenService:Create(title, TweenInfo.new(2), { TextTransparency = 1 }):Play()
					TweenService:Create(hint, TweenInfo.new(2), { TextTransparency = 1 }):Play()
				end
			end)
		end
	else
		restoreAudio()
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		clearMap()
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		end)
		title.TextTransparency = 1
		hint.TextTransparency = 1
		touchLabel.TextTransparency = 1

		local t = TweenService:Create(
			blackout,
			TweenInfo.new(1, Enum.EasingStyle.Sine),
			{ BackgroundTransparency = 1 }
		)
		t:Play()
		t.Completed:Once(function()
			if not enabled then
				gui.Parent = nil
			end
		end)
	end
end

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == CONFIG.ToggleKey and UserInputService:GetFocusedTextBox() == nil then
		setEnabled(not enabled)
	end
end)

-- start immediately
setEnabled(true)
