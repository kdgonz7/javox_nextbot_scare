---@diagnostic disable: undefined-field, inject-field
local DETECTION_RANGE = 5000
local HEALTH_THRESHOLD = 100000
local DETECTION_INTERVAL = 0.5
local FOV_ANGLE = 90
local SCARY_HINT_RADIUS = 3000
local DEBUG_MODE = false

-- ConVar
local scareEnabled = CreateClientConVar("javox_nextbot_scare_enabled", "1", true, false,
    "Enables/disables the JaVox nextbot scare system")
local scaredOnShot = CreateClientConVar("javox_scared_on_shot", "1", true, false,
    "Scare when shooting at dangerous nextbots")
local scaryHintEnabled = CreateClientConVar("javox_scary_hint_enabled", "1", true, false,
    "Show scary hints when dangerous nextbots are nearby but not visible")

local playerViewAngles = Angle(0, 0, 0)
local playerViewOrigin = Vector(0, 0, 1180)
local detectionTimerName = "JaVoxNextbotDetectionTimer"
local scaryHintTimerName = "JaVoxScaryHintTimer"


-- Helper functions
local function IsGenericNextbot(ent)
    if not IsValid(ent) then return false end

    if ent.IsNextBot and ent:IsNextBot() then
        if DEBUG_MODE then
            print(string.format("[JaVox] Found entity marked as NextBot: %s", ent:GetClass()))
        end
        return true
    end

    return false
end

local function IsDangerousNextbot(ent)
    if not IsValid(ent) then return false end
    if not IsGenericNextbot(ent) then return false end

    local health = ent:Health() or 0
    local maxHealth = ent.GetMaxHealth and ent:GetMaxHealth() or health

    return health >= HEALTH_THRESHOLD or maxHealth >= HEALTH_THRESHOLD
end

local function IsInLineOfSight(ent)
    if not IsValid(ent) then return false end

    local ply = LocalPlayer()
    if not IsValid(ply) then return false end

    local trace = util.QuickTrace(
        playerViewOrigin,
        ent:WorldSpaceCenter() - playerViewOrigin,
        ply
    )

    return trace.Entity == ent
end

local function FindNextbotsInCone()
    local ply = LocalPlayer()
    if not IsValid(ply) then return {} end

    playerViewOrigin = ply:EyePos()
    playerViewAngles = ply:EyeAngles()

    local coneDir = playerViewAngles:Forward()
    local coneAngle = math.rad(FOV_ANGLE / 2)

    local entitiesInCone = ents.FindInCone(
        playerViewOrigin,
        coneDir,
        DETECTION_RANGE,
        math.cos(coneAngle)
    )

    if DEBUG_MODE and #entitiesInCone > 0 then
        print(string.format("[JaVox] Found %d entities in cone", #entitiesInCone))
    end

    return entitiesInCone
end

local function FindNextbotsInRadius(radius)
    local ply = LocalPlayer()
    if not IsValid(ply) then return {} end

    playerViewOrigin = ply:EyePos()
    local entitiesInRadius = {}

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        if playerViewOrigin:Distance(ent:GetPos()) <= radius then
            table.insert(entitiesInRadius, ent)
        end
    end

    return entitiesInRadius
end

-- Core detection function
local function CheckForDangerousNextbots()
    if not scareEnabled:GetBool() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    if DEBUG_MODE then
        print("[JaVox] Starting nextbot scan...")
    end

    local foundDangerous = false
    local dangerousCount = 0
    local dangerousNextbots = {}

    local entitiesInCone = FindNextbotsInCone()

    for _, ent in ipairs(entitiesInCone) do
        if not IsValid(ent) then continue end
        if IsDangerousNextbot(ent) then
            if not IsInLineOfSight(ent) then continue end

            foundDangerous = true
            dangerousCount = dangerousCount + 1

            table.insert(dangerousNextbots, {
                class = ent:GetClass(),
                health = ent:Health(),
                distance = playerViewOrigin:Distance(ent:GetPos()),
                entity = ent
            })

            if DEBUG_MODE then
                print(string.format(
                    "[JaVox] DANGEROUS NEXTBOT DETECTED: %s | Health: %d | Distance: %.0f units",
                    ent:GetClass(),
                    ent:Health(),
                    playerViewOrigin:Distance(ent:GetPos())
                ))
            end
        end
    end

    if foundDangerous then
        if DEBUG_MODE then
            print(string.format(
                "[JaVox] SCARE TRIGGERED: Found %d dangerous nextbot(s)",
                dangerousCount
            ))
        end

        net.Start("JaVox_EmitAction")
        net.WriteString("self.scared")
        net.SendToServer()

        if DEBUG_MODE then
            print("[JaVox] Network message sent: JaVox_EmitAction -> 'self.scared'")
        end
    else
        if DEBUG_MODE and #entitiesInCone > 0 then
            print("[JaVox] Scan complete: No dangerous nextbots found in cone")
        end
    end

    -- Check for scary hints (nearby but not visible)
    CheckForScaryHints()
end

function CheckForScaryHints()
    if not scaryHintEnabled:GetBool() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local dangerousNearby = false
    local closestDistance = math.huge
    local closestNextbot = nil

    -- Check for dangerous nextbots in radius but not in view
    local entitiesInRadius = FindNextbotsInRadius(SCARY_HINT_RADIUS)

    for _, ent in ipairs(entitiesInRadius) do
        if IsValid(ent) and IsDangerousNextbot(ent) then
            local distance = playerViewOrigin:Distance(ent:GetPos())

            if not IsInLineOfSight(ent) then
                dangerousNearby = true
                if distance < closestDistance then
                    closestDistance = distance
                    closestNextbot = ent
                end
            end
        end
    end

    if dangerousNearby and closestNextbot then
        -- Send scary hint
        net.Start("JaVox_EmitAction")
        net.WriteString("scary-hint")
        net.SendToServer()

        if DEBUG_MODE then
            print(string.format(
                "[JaVox] Scary hint: Dangerous nextbot nearby but not visible (%s, %.0f units away)",
                closestNextbot:GetClass(),
                closestDistance
            ))
        end
    end
end

hook.Add("OnEntityCreated", "JaVoxTrackFriendlyEntities", function(ent)
    if not IsValid(ent) then return end
    if not ent:IsNPC() and not ent:IsNextBot() then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    if not IsValid(ent) then return end

    if ent.Disposition and ent:Disposition(ply) == D_LI then
        ent.JaVoxIsFriendly = true
    end
end)

local function InitializeDetection()
    timer.Remove(detectionTimerName)
    timer.Remove(scaryHintTimerName)

    if scareEnabled:GetBool() then
        timer.Create(detectionTimerName, DETECTION_INTERVAL, 0, function()
            CheckForDangerousNextbots()
        end)

        -- Scary hints check less frequently
        timer.Create(scaryHintTimerName, DETECTION_INTERVAL * 2, 0, function()
            CheckForScaryHints()
        end)
    end

    if DEBUG_MODE then
        print("[JaVox] Detection system initialized")
        print(string.format("[JaVox] Configuration:"))
        print(string.format("  Main System: %s", scareEnabled:GetBool() and "ENABLED" or "DISABLED"))
        print(string.format("  Detection Range: %d units", DETECTION_RANGE))
        print(string.format("  Health Threshold: %d HP", HEALTH_THRESHOLD))
        print(string.format("  Scan Interval: %.1f seconds", DETECTION_INTERVAL))
        print(string.format("  Field of View: %d degrees", FOV_ANGLE))
        print(string.format("  Scared on Shot: %s", scaredOnShot:GetBool() and "YES" or "NO"))
        print(string.format("  Scary Hints: %s", scaryHintEnabled:GetBool() and "YES" or "NO"))
    end
end

-- Initialization hooks
hook.Add("InitPostEntity", "JaVoxInitNextbotDetection", function()
    timer.Simple(2, function()
        InitializeDetection()
        print("[JaVox] System loaded and ready")
    end)
end)

hook.Add("OnReloaded", "JaVoxReloadNextbotDetection", function()
    InitializeDetection()
    print("[JaVox] System reloaded")
end)

-- [[[ CON COMMANDS ]]]
concommand.Add("javox_nextbot_debug", function(ply)
    DEBUG_MODE = not DEBUG_MODE
    local status = DEBUG_MODE and "ENABLED" or "DISABLED"

    if IsValid(ply) and ply:IsPlayer() then
        ply:ChatPrint("JaVox Debug Mode: " .. status)
    end

    print(string.format("[JaVox] Debug mode %s", status))

    if DEBUG_MODE then
        print("[JaVox] Debug information will now be printed to console")
        print("[JaVox] Use 'javox_nextbot_check' to manually scan")
    end
end)

concommand.Add("javox_nextbot_list", function(ply)
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local entitiesInCone = FindNextbotsInCone()

    print(string.format("[JaVox] Found %d entities in cone:", #entitiesInCone))

    for i, ent in ipairs(entitiesInCone) do
        if IsValid(ent) then
            local isNextbot = IsGenericNextbot(ent)
            local isDangerous = IsDangerousNextbot(ent)
            local health = ent:Health() or 0
            local distance = playerViewOrigin:Distance(ent:GetPos())
            local inSight = IsInLineOfSight(ent)

            print(string.format(
                "  [%d] %s (Class: %s) | Health: %d | Distance: %.0f | Nextbot: %s | Dangerous: %s | Visible: %s",
                i,
                ent:GetName() ~= "" and ent:GetName() or "Unnamed",
                ent:GetClass(),
                health,
                distance,
                isNextbot and "YES" or "NO",
                isDangerous and "YES" or "NO",
                inSight and "YES" or "NO"
            ))
        end
    end
end)

-- ConVar change handlers
cvars.AddChangeCallback("javox_nextbot_scare_enabled", function(convar, oldValue, newValue)
    InitializeDetection()
    print(string.format("[JaVox] Main system %s", tobool(newValue) and "ENABLED" or "DISABLED"))
end)

cvars.AddChangeCallback("javox_scared_on_shot", function(convar, oldValue, newValue)
    print(string.format("[JaVox] Scared on shot %s", tobool(newValue) and "ENABLED" or "DISABLED"))
end)

cvars.AddChangeCallback("javox_scary_hint_enabled", function(convar, oldValue, newValue)
    print(string.format("[JaVox] Scary hints %s", tobool(newValue) and "ENABLED" or "DISABLED"))
end)

-- Cleanup on reload
hook.Add("OnReloaded", "JaVoxCleanupTimers", function()
    timer.Remove(detectionTimerName)
    timer.Remove(scaryHintTimerName)
end)

print("JaVox Enhanced Nextbot Scare Detection System loaded")
