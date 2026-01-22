--[[
    Ultimate Zombie Kill Script - Mobile Optimized & No-Equip
    Created by Ernie Bot (nâng cấp bởi AI)
    
    Features:
    - Mobile-First UI: Giao diện nhỏ gọn, dễ thao tác bằng một tay.
    - No-Equip System: Sử dụng vũ khí trực tiếp từ Backpack mà không cần cầm, cực nhanh.
    - Max Power: Tự động ưu tiên vũ khí AOE (lựu đạn, rocket) và bắn liên tục.
    - Auto-Detect Remotes: Tự động tìm các remote event phổ biến.
    - Highly Configurable: Dễ dàng tùy chỉnh tốc độ và hành vi.
--]]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

--// Player Variables
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--// Configuration (TÙY CHỈNH TẠI ĐÂY)
local CONFIG = {
    ATTACK_INTERVAL = 0.05, -- Thời gian giữa mỗi đợt tấn công (càng nhỏ càng nhanh, nhưng có thể bị kick)
    AUTO_FIND_REMOTES = true, -- Tự động tìm remote events
    PRIORITIZE_AOE = true, -- Ưu tiên dùng lựu đạn/rocket trước
    AOE_WEAPON_NAMES = {"grenade", "rpg", "rocket", "c4"}, -- Tên các vũ khí AOE (viết thường)
    KILL_ALL_IN_ONE_SHOT = false, -- Thử bắn tất cả zombie trong 1 lần (chỉ cho súng thường)
    BACKGROUND_TRANSPARENCY = 0.5, -- Độ trong suốt của nền UI
    BUTTON_SIZE = 60, -- Kích thước nút bấm chính (pixel)
}

--// Remote Events Cache
local Remotes = {
    Gunshot = nil,
    Grenade = nil,
    Rocket = nil,
    Melee = nil,
}

--// State
local isEnabled = false
local isDragging = false
local dragStart
local frameStartPos
local lastAttackTime = 0

--// Create Mobile-First ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "UltimateZombieKillUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

--// Main Toggle Button (Floating Action Button style)
local MainButton = Instance.new("TextButton")
MainButton.Name = "MainButton"
MainButton.Size = UDim2.new(0, CONFIG.BUTTON_SIZE, 0, CONFIG.BUTTON_SIZE)
MainButton.Position = UDim2.new(1, -CONFIG.BUTTON_SIZE - 20, 0.5, -CONFIG.BUTTON_SIZE / 2) -- Góc phải, giữa màn hình
MainButton.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
MainButton.BorderSizePixel = 0
MainButton.Font = Enum.Font.GothamBold
MainButton.Text = "OFF"
MainButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MainButton.TextSize = 14
MainButton.Parent = ScreenGui

local MainButtonCorner = Instance.new("UICorner")
MainButtonCorner.CornerRadius = UDim.new(1, 0) -- Bo tròn hoàn toàn thành hình tròn
MainButtonCorner.Parent = MainButton

local MainButtonStroke = Instance.new("UIStroke")
MainButtonStroke.Color = Color3.fromRGB(255, 255, 255)
MainButtonStroke.Thickness = 2
MainButtonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
MainButtonStroke.Parent = MainButton

--// Status Indicator (Small dot)
local StatusDot = Instance.new("Frame")
StatusDot.Name = "StatusDot"
StatusDot.Size = UDim2.new(0, 10, 0, 10)
StatusDot.Position = UDim2.new(1, -5, 0, 5)
StatusDot.BackgroundColor3 = Color3.fromRGB(100, 100, 100) -- Grey when off
StatusDot.BorderSizePixel = 0
StatusDot.Parent = MainButton

local StatusDotCorner = Instance.new("UICorner")
StatusDotCorner.CornerRadius = UDim.new(1, 0)
StatusDotCorner.Parent = StatusDot

--// Functions
local function findRemotes()
    if not CONFIG.AUTO_FIND_REMOTES then return end
    
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:FindFirstChild("RemoteEvents") or ReplicatedStorage:FindFirstChild("Network")
    if not remotesFolder then
        warn("Could not find Remotes folder!")
        return
    end
    
    for _, remote in ipairs(remotesFolder:GetChildren()) do
        local name = remote.Name:lower()
        if name:find("gunshot") or name:find("fire") then
            Remotes.Gunshot = remote
        elseif name:find("grenade") or name:find("explosive") then
            Remotes.Grenade = remote
        elseif name:find("rocket") or name:find("rpg") then
            Remotes.Rocket = remote
        end
    end
    
    print("Remotes found:", Remotes.Gunshot, Remotes.Grenade, Remotes.Rocket)
end

local function getAliveZombies()
    local zombies = {}
    local aliveZombiesFolder = workspace:FindFirstChild("AliveZombies") or workspace:FindFirstChild("Zombies")
    if aliveZombiesFolder then
        for _, zombie in ipairs(aliveZombiesFolder:GetChildren()) do
            if zombie:IsA("Model") and zombie.PrimaryPart and zombie:FindFirstChild("Humanoid") and zombie.Humanoid.Health > 0 then
                table.insert(zombies, zombie)
            end
        end
    end
    return zombies
end

local function getAllWeapons()
    local weapons = {}
    local backpack = LocalPlayer.Backpack
    local character = LocalPlayer.Character
    
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") then table.insert(weapons, item) end
    end
    
    -- Also check character for held tools, though we won't equip them
    if character then
        for _, item in ipairs(character:GetChildren()) do
            if item:IsA("Tool") and not table.find(weapons, item) then
                table.insert(weapons, item)
            end
        end
    end
    
    return weapons
end

local function attackWithWeapon(weapon, zombies)
    if not weapon or not weapon:IsA("Tool") then return end
    
    local weaponName = weapon.Name:lower()
    local args = {}
    
    -- Determine attack type and create arguments
    if CONFIG.PRIORITIZE_AOE and table.find(CONFIG.AOE_WEAPON_NAMES, function(aoeName) return weaponName:find(aoeName) end) then
        -- AOE Weapon (Grenade/Rocket)
        if Remotes.Grenade or Remotes.Rocket then
            local remote = Remotes.Grenade or Remotes.Rocket
            for _, zombie in ipairs(zombies) do
                if zombie and zombie.PrimaryPart then
                    local pos = zombie:GetPivot().Position
                    -- Most AoE remotes expect: weapon, position, ...other args
                    pcall(function()
                        remote:FireServer(weapon, Vector3.new(pos.X, pos.Y, pos.Z))
                    end)
                end
            end
        end
    else
        -- Regular Gun
        if Remotes.Gunshot then
            if CONFIG.KILL_ALL_IN_ONE_SHOT then
                -- Some games allow firing at multiple targets at once
                pcall(function()
                    Remotes.Gunshot:FireServer(weapon, zombies, false, Vector3.new(0,0,0))
                end)
            else
                -- Fire at each zombie individually for compatibility
                for _, zombie in ipairs(zombies) do
                    if zombie and zombie.PrimaryPart then
                        local pos = zombie:GetPivot().Position
                        pcall(function()
                            Remotes.Gunshot:FireServer(weapon, {zombie}, false, Vector3.new(pos.X, pos.Y, pos.Z))
                        end)
                    end
                end
            end
        end
    end
end

local function killAllZombies()
    if not isEnabled or os.clock() - lastAttackTime < CONFIG.ATTACK_INTERVAL then return end
    lastAttackTime = os.clock()
    
    local zombies = getAliveZombies()
    if #zombies == 0 then return end
    
    local weapons = getAllWeapons()
    if #weapons == 0 then return end
    
    -- Attack with all weapons
    for _, weapon in ipairs(weapons) do
        attackWithWeapon(weapon, zombies)
    end
end

--// UI Functions
local function updateUI()
    if isEnabled then
        MainButton.BackgroundColor3 = Color3.fromRGB(80, 255, 80) -- Green
        MainButton.Text = "ON"
        StatusDot.BackgroundColor3 = Color3.fromRGB(80, 255, 80)
    else
        MainButton.BackgroundColor3 = Color3.fromRGB(255, 80, 80) -- Red
        MainButton.Text = "OFF"
        StatusDot.BackgroundColor3 = Color3.fromRGB(100, 100, 100) -- Grey
    end
end

local function toggleScript()
    isEnabled = not isEnabled
    updateUI()
end

--// Input Handling for Mobile Drag & Tap
MainButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if isDragging then return end -- Don't trigger tap if dragging
        
        -- Simple tap to toggle
        task.delay(0.2, function()
            if not isDragging then
                toggleScript()
            end
        end)
        
        -- Dragging logic
        isDragging = true
        dragStart = input.Position
        frameStartPos = MainButton.Position
        
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                isDragging = false
            end
        end)
    end
end)

MainButton.InputChanged:Connect(function(input)
    if isDragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - dragStart
        local newX = frameStartPos.X.Scale * MainButton.Parent.AbsoluteSize.X + frameStartPos.X.Offset + delta.X
        local newY = frameStartPos.Y.Scale * MainButton.Parent.AbsoluteSize.Y + frameStartPos.Y.Offset + delta.Y
        
        -- Clamp position to screen bounds
        local screenSize = MainButton.Parent.AbsoluteSize
        newX = math.clamp(newX, 0, screenSize.X - CONFIG.BUTTON_SIZE)
        newY = math.clamp(newY, 0, screenSize.Y - CONFIG.BUTTON_SIZE)
        
        MainButton.Position = UDim2.new(0, newX, 0, newY)
    end
end)

--// Main Loop
task.spawn(function()
    findRemotes() -- Find remotes on start
    
    while task.wait() do
        if isEnabled then
            killAllZombies()
        end
    end
end)

--// Initialize
updateUI()
print("Ultimate Zombie Kill Script loaded! Tap the button to toggle, drag to move.")
