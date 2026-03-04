NaiPassengers = NaiPassengers or {}

if SERVER then
    AddCSLuaFile("nai_npc_passengers/settings.lua")
    AddCSLuaFile("nai_npc_passengers/ui.lua")
end

include("nai_npc_passengers/settings.lua")
include("nai_npc_passengers/main.lua")
include("nai_npc_passengers/ui.lua")

if SERVER then
    include("nai_npc_passengers/lvs_turret.lua")
    include("nai_npc_passengers/lvs_driver.lua")
end
