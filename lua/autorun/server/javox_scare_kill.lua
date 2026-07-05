local ScaryHealthThreshold = CreateConVar("scary_health_threshold", "10000", { FCVAR_ARCHIVE },
    "Health threshold for Scary() function.")
local TeammateRadius = CreateConVar("scary_teammate_radius", "650", { FCVAR_ARCHIVE }, "Radius to check for teammates.")
local ScaryEnabled = CreateConVar("scary_enabled", "1", { FCVAR_ARCHIVE }, "Enables or disables the Scary() function.")

local function Scary(attacker)
    if ! IsValid(attacker) then return false end
    if ! ScaryEnabled:GetBool() then return false end
    local threshold = ScaryHealthThreshold:GetInt()
    if attacker:Health() >= threshold then return true end
    return false
end

hook.Add("OnNPCKilled", "CheckOnTeammates", function(ent, attacker, inflictor)
    if ! Scary(attacker) then return end
    if attacker == ent then return end
    if ! JaVox then return end

    local radius = TeammateRadius:GetFloat()
    local players_inRadius = ents.FindInSphere(ent:GetPos(), radius)

    for _, ply in pairs(players_inRadius) do
        if ! ply:IsPlayer() or ! ply:Alive() then continue end
        if (ent:Disposition(ply) == D_LI or ent:Disposition(ply) == D_NU) then
            JaVox.Director:emitActionFromPlayer(ply, "self.scared.teammate_down")
        end
    end
end)
