-- Better NPC Passengers - Russian Localization
-- TRANSLATORS: Replace the English text after each language.Add() with Russian translations
-- This is a template - fill in the Russian translations

-- Addon name
language.Add("npcpassengers.name", "Better NPC Passengers") -- TODO: Translate
language.Add("npcpassengers.settings", "Settings") -- TODO: Translate

-- Navigation / Tab names
language.Add("npcpassengers.nav.general", "General") -- TODO: Translate
language.Add("npcpassengers.nav.autojoin", "Auto-Join") -- TODO: Translate
language.Add("npcpassengers.nav.passengers", "Passengers") -- TODO: Translate
language.Add("npcpassengers.nav.position", "Position") -- TODO: Translate
language.Add("npcpassengers.nav.behaviour", "Behaviour") -- TODO: Translate
language.Add("npcpassengers.nav.keybinds", "Keybinds") -- TODO: Translate
language.Add("npcpassengers.nav.hud", "HUD") -- TODO: Translate
language.Add("npcpassengers.nav.driver", "Driver") -- TODO: Translate
language.Add("npcpassengers.nav.help", "Help") -- TODO: Translate

-- General Settings
language.Add("npcpassengers.general.header", "General Settings") -- TODO: Translate
language.Add("npcpassengers.allow_multiple", "Allow Multiple Passengers") -- TODO: Translate
language.Add("npcpassengers.allow_multiple.help", "Let multiple NPCs ride in the same vehicle.") -- TODO: Translate
language.Add("npcpassengers.exit_behavior", "Exit Behavior") -- TODO: Translate
language.Add("npcpassengers.exit_behavior.help", "When should NPC passengers exit the vehicle?") -- TODO: Translate
language.Add("npcpassengers.exit_mode.leave_player", "Leave when player exits") -- TODO: Translate
language.Add("npcpassengers.exit_mode.leave_attack", "Leave when vehicle is attacked") -- TODO: Translate
language.Add("npcpassengers.exit_mode.never", "Never leave automatically") -- TODO: Translate

-- Timing Settings
language.Add("npcpassengers.timing.header", "Timing") -- TODO: Translate
language.Add("npcpassengers.max_attach_dist", "Max Attach Distance") -- TODO: Translate
language.Add("npcpassengers.max_attach_dist.help", "Maximum distance (units) to attach NPC to vehicle.") -- TODO: Translate
language.Add("npcpassengers.detach_delay", "Detach Delay") -- TODO: Translate
language.Add("npcpassengers.detach_delay.help", "Seconds to wait before detaching after player leaves.") -- TODO: Translate
language.Add("npcpassengers.ai_delay", "AI Restore Delay") -- TODO: Translate
language.Add("npcpassengers.ai_delay.help", "Seconds to wait before restoring NPC AI after detaching.") -- TODO: Translate
language.Add("npcpassengers.cooldown", "Cooldown Time") -- TODO: Translate
language.Add("npcpassengers.cooldown.help", "Cooldown between attaching NPCs to same vehicle.") -- TODO: Translate
language.Add("npcpassengers.passenger_limit", "Passenger Limit") -- TODO: Translate
language.Add("npcpassengers.passenger_limit.help", "Max NPCs allowed in vehicle.") -- TODO: Translate

-- Auto-Join Settings
language.Add("npcpassengers.autojoin.header", "Auto-Join (Squad Behavior)") -- TODO: Translate
language.Add("npcpassengers.autojoin.desc", "Friendly NPCs will automatically board your vehicle when you enter it - just like squad mechanics in Half-Life 2!") -- TODO: Translate
language.Add("npcpassengers.autojoin.enable", "Enable Auto-Join") -- TODO: Translate
language.Add("npcpassengers.autojoin.enable.help", "Nearby friendly NPCs will automatically join when you enter a vehicle.") -- TODO: Translate
language.Add("npcpassengers.autojoin.range", "Auto-Join Range") -- TODO: Translate
language.Add("npcpassengers.autojoin.range.help", "Maximum distance to find NPCs for auto-joining.") -- TODO: Translate
language.Add("npcpassengers.autojoin.max", "Max Auto-Join NPCs") -- TODO: Translate
language.Add("npcpassengers.autojoin.max.help", "Maximum number of NPCs that can auto-join at once.") -- TODO: Translate
language.Add("npcpassengers.autojoin.squad_only", "Squad Members Only") -- TODO: Translate
language.Add("npcpassengers.autojoin.squad_only.help", "Only NPCs with a squad name will auto-join (for HL2-style squads).") -- TODO: Translate

-- Position Settings
language.Add("npcpassengers.position.header", "Position Offsets") -- TODO: Translate
language.Add("npcpassengers.position.desc", "Fine-tune NPC positioning in vehicles. Use these to fix floating or clipping issues.") -- TODO: Translate
language.Add("npcpassengers.height_offset", "Height Offset") -- TODO: Translate
language.Add("npcpassengers.forward_offset", "Forward Offset") -- TODO: Translate
language.Add("npcpassengers.right_offset", "Right Offset") -- TODO: Translate
language.Add("npcpassengers.angle.header", "Angle Offsets") -- TODO: Translate
language.Add("npcpassengers.angle.desc", "Adjust NPC rotation in vehicles.") -- TODO: Translate
language.Add("npcpassengers.yaw_offset", "Yaw (Rotation)") -- TODO: Translate
language.Add("npcpassengers.pitch_offset", "Pitch (Tilt Forward)") -- TODO: Translate
language.Add("npcpassengers.roll_offset", "Roll (Tilt Sideways)") -- TODO: Translate

-- Behaviour Settings
language.Add("npcpassengers.behaviour.header", "NPC Speech (Advanced)") -- TODO: Translate
language.Add("npcpassengers.behaviour.desc", "Configure how NPCs vocalize while riding in vehicles. HL2-style citizen voices!") -- TODO: Translate
language.Add("npcpassengers.speech_enable", "Enable NPC Speech") -- TODO: Translate
language.Add("npcpassengers.speech_enable.help", "Master toggle for all NPC speech. Disable to silence passengers completely.") -- TODO: Translate
language.Add("npcpassengers.speech_volume", "Speech Volume") -- TODO: Translate
language.Add("npcpassengers.speech_volume.help", "How loud NPC voices are (0 = silent, 100 = full volume).") -- TODO: Translate
language.Add("npcpassengers.pitch_variation", "Pitch Variation (+/-)") -- TODO: Translate
language.Add("npcpassengers.pitch_variation.help", "Random pitch variation for more natural voices. 0 = monotone, higher = more variety.") -- TODO: Translate
language.Add("npcpassengers.crash.header", "Crash Reactions") -- TODO: Translate
language.Add("npcpassengers.crash_enable", "Enable Crash Sounds") -- TODO: Translate
language.Add("npcpassengers.crash_enable.help", "NPCs grunt/yelp when vehicle decelerates sharply (crashes, hard braking).") -- TODO: Translate
language.Add("npcpassengers.crash_threshold", "Crash Sensitivity") -- TODO: Translate
language.Add("npcpassengers.crash_threshold.help", "Deceleration needed to trigger crash sounds. Lower = more sensitive.") -- TODO: Translate
language.Add("npcpassengers.crash_cooldown", "Crash Sound Cooldown") -- TODO: Translate
language.Add("npcpassengers.crash_cooldown.help", "Minimum seconds between crash sounds per NPC.") -- TODO: Translate

-- Keybinds
language.Add("npcpassengers.keybinds.header", "Keybinds") -- TODO: Translate
language.Add("npcpassengers.keybinds.desc", "Configure keyboard shortcuts for quick actions.") -- TODO: Translate
language.Add("npcpassengers.keybind.attach", "Attach Nearest NPC") -- TODO: Translate
language.Add("npcpassengers.keybind.attach.help", "Attach the nearest friendly NPC to your vehicle.") -- TODO: Translate
language.Add("npcpassengers.keybind.detach_all", "Detach All NPCs") -- TODO: Translate
language.Add("npcpassengers.keybind.detach_all.help", "Remove all passengers from your vehicle.") -- TODO: Translate
language.Add("npcpassengers.keybind.toggle_autojoin", "Toggle Auto-Join") -- TODO: Translate
language.Add("npcpassengers.keybind.toggle_autojoin.help", "Quickly enable/disable auto-join.") -- TODO: Translate
language.Add("npcpassengers.keybind.menu", "Open Settings Menu") -- TODO: Translate
language.Add("npcpassengers.keybind.menu.help", "Open the settings panel.") -- TODO: Translate
language.Add("npcpassengers.keybind.exit_all", "Exit All Passengers") -- TODO: Translate
language.Add("npcpassengers.keybind.exit_all.help", "Make all passengers leave the vehicle.") -- TODO: Translate
language.Add("npcpassengers.keybind.toggle_hud", "Toggle HUD") -- TODO: Translate
language.Add("npcpassengers.keybind.toggle_hud.help", "Show/hide the passenger HUD.") -- TODO: Translate

-- HUD Settings
language.Add("npcpassengers.hud.header", "HUD Settings") -- TODO: Translate
language.Add("npcpassengers.hud.enable", "Enable HUD") -- TODO: Translate
language.Add("npcpassengers.hud.enable.help", "Show passenger status overlay on screen.") -- TODO: Translate
language.Add("npcpassengers.hud.position", "HUD Position") -- TODO: Translate
language.Add("npcpassengers.hud.position.help", "Where the HUD appears on screen.") -- TODO: Translate
language.Add("npcpassengers.hud.position.topleft", "Top Left") -- TODO: Translate
language.Add("npcpassengers.hud.position.topright", "Top Right") -- TODO: Translate
language.Add("npcpassengers.hud.position.bottomleft", "Bottom Left") -- TODO: Translate
language.Add("npcpassengers.hud.position.bottomright", "Bottom Right") -- TODO: Translate
language.Add("npcpassengers.hud.scale", "HUD Scale") -- TODO: Translate
language.Add("npcpassengers.hud.scale.help", "Size multiplier for the HUD.") -- TODO: Translate
language.Add("npcpassengers.hud.opacity", "HUD Opacity") -- TODO: Translate
language.Add("npcpassengers.hud.opacity.help", "Background transparency (0 = invisible, 1 = solid).") -- TODO: Translate

-- Driver Settings
language.Add("npcpassengers.driver.header", "NPC Driver") -- TODO: Translate
language.Add("npcpassengers.driver.desc", "Allow NPCs to drive vehicles for you.") -- TODO: Translate
language.Add("npcpassengers.driver.enable", "Enable NPC Drivers") -- TODO: Translate
language.Add("npcpassengers.driver.enable.help", "Allow NPCs to take control of vehicles.") -- TODO: Translate
language.Add("npcpassengers.driver.behavior", "Driving Behavior") -- TODO: Translate
language.Add("npcpassengers.driver.behavior.help", "How the NPC drives the vehicle.") -- TODO: Translate
language.Add("npcpassengers.driver.behavior.cruise", "Random Cruise") -- TODO: Translate
language.Add("npcpassengers.driver.behavior.follow", "Follow Player") -- TODO: Translate
language.Add("npcpassengers.driver.behavior.patrol", "Patrol") -- TODO: Translate
language.Add("npcpassengers.driver.behavior.flee", "Flee") -- TODO: Translate
language.Add("npcpassengers.driver.behavior.parked", "Stay Parked") -- TODO: Translate

-- Help / FAQ
language.Add("npcpassengers.help.header", "Frequently Asked Questions") -- TODO: Translate
language.Add("npcpassengers.help.desc", "Quick answers to common questions and troubleshooting.") -- TODO: Translate
language.Add("npcpassengers.help.still_need", "Still Need Help?") -- TODO: Translate
language.Add("npcpassengers.help.community", "Join our Discord community for support!") -- TODO: Translate

-- Status messages
language.Add("npcpassengers.status.calm", "CALM") -- TODO: Translate
language.Add("npcpassengers.status.alert", "ALERT") -- TODO: Translate
language.Add("npcpassengers.status.scared", "SCARED") -- TODO: Translate
language.Add("npcpassengers.status.drowsy", "DROWSY") -- TODO: Translate
language.Add("npcpassengers.status.dead", "DEAD") -- TODO: Translate
language.Add("npcpassengers.status.calm.desc", "Relaxed, no threats nearby") -- TODO: Translate
language.Add("npcpassengers.status.alert.desc", "Enemy detected, NPC is tracking threats") -- TODO: Translate
language.Add("npcpassengers.status.scared.desc", "Dangerous driving (high speed, crashes)") -- TODO: Translate
language.Add("npcpassengers.status.drowsy.desc", "Long calm ride, NPC is getting sleepy") -- TODO: Translate
language.Add("npcpassengers.status.dead.desc", "Health reached zero") -- TODO: Translate

-- Chat messages
language.Add("npcpassengers.chat.autojoin_on", "Auto-Join: ON") -- TODO: Translate
language.Add("npcpassengers.chat.autojoin_off", "Auto-Join: OFF") -- TODO: Translate
language.Add("npcpassengers.chat.hud_on", "HUD: ON") -- TODO: Translate
language.Add("npcpassengers.chat.hud_off", "HUD: OFF") -- TODO: Translate
language.Add("npcpassengers.chat.prefix", "[Better NPC Passengers]") -- TODO: Translate

-- Error messages
language.Add("npcpassengers.error.no_vehicle", "No vehicle nearby") -- TODO: Translate
language.Add("npcpassengers.error.no_npc", "No NPC nearby") -- TODO: Translate
language.Add("npcpassengers.error.vehicle_full", "Vehicle is full") -- TODO: Translate
language.Add("npcpassengers.error.too_far", "NPC too far from vehicle") -- TODO: Translate

print("[Better NPC Passengers] Russian localization template loaded - needs translation!")
