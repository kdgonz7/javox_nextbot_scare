local DETECTION_RANGE = 5000
local HEALTH_THRESHOLD = 100000
local DETECTION_INTERVAL = 0.5
local FOV_ANGLE = 90
local DEBUG_MODE = false

local playerViewAngles = Angle(0, 0, 0)
local playerViewOrigin = Vector(0, 0, 1180)
local detectionTimerName = "JaVoxNextbotDetectionTimer"

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

local function CheckForDangerousNextbots()
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
        if IsGenericNextbot(ent) then
            local health = ent:Health() or 0
            local maxHealth = ent.GetMaxHealth and ent:GetMaxHealth() or health

            if health >= HEALTH_THRESHOLD or maxHealth >= HEALTH_THRESHOLD then
                local trace = util.QuickTrace(playerViewOrigin, ent:WorldSpaceCenter() - playerViewOrigin, ply)
                if trace.Entity ~= ent then continue end -- View is blocked by a wall or prop!

                foundDangerous = true
                dangerousCount = dangerousCount + 1
                table.insert(dangerousNextbots, {
                    class = ent:GetClass(),
                    health = health,
                    distance = playerViewOrigin:Distance(ent:GetPos())
                })

                if DEBUG_MODE then
                    print(string.format(
                        "[JaVox] DANGEROUS NEXTBOT DETECTED: %s | Health: %d | Distance: %.0f units",
                        ent:GetClass(),
                        health,
                        playerViewOrigin:Distance(ent:GetPos())
                    ))
                end
            end
        end
    end

    if foundDangerous then
        if DEBUG_MODE then
            print(string.format(
                "[JaVox] SCARE TRIGGERED: Found %d dangerous nextbot(s)",
                dangerousCount
            ))

            for i, nextbot in ipairs(dangerousNextbots) do
                print(string.format(
                    "  [%d] Class: %s, Health: %d, Distance: %.0f",
                    i, nextbot.class, nextbot.health, nextbot.distance
                ))
            end
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
end

local function InitializeDetection()
    timer.Remove(detectionTimerName)

    timer.Create(detectionTimerName, DETECTION_INTERVAL, 0, function()
        CheckForDangerousNextbots()
    end)

    if DEBUG_MODE then
        print("[JaVox] Detection system initialized")
        print(string.format("[JaVox] Configuration:"))
        print(string.format("  Detection Range: %d units", DETECTION_RANGE))
        print(string.format("  Health Threshold: %d HP", HEALTH_THRESHOLD))
        print(string.format("  Scan Interval: %.1f seconds", DETECTION_INTERVAL))
        print(string.format("  Field of View: %d degrees", FOV_ANGLE))
        print(string.format("  Watching for: Generic nextbots"))
    end
end

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

concommand.Add("javox_nextbot_check", function(ply)
    if IsValid(ply) and ply:IsPlayer() then
        CheckForDangerousNextbots()
        ply:ChatPrint("JaVox: Manually checking for dangerous nextbots...")
    else
        CheckForDangerousNextbots()
    end
end)

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
            local health = ent:Health() or 0
            local distance = playerViewOrigin:Distance(ent:GetPos())

            print(string.format(
                "  [%d] %s (Class: %s) | Health: %d | Distance: %.0f | Nextbot: %s",
                i,
                ent:GetName() ~= "" and ent:GetName() or "Unnamed",
                ent:GetClass(),
                health,
                distance,
                isNextbot and "YES" or "NO"
            ))
        end
    end
end)

hook.Add("OnReloaded", "JaVoxCleanupTimers", function()
    timer.Remove(detectionTimerName)
end)

print("JaVox Nextbot Scare Detection System loaded")
