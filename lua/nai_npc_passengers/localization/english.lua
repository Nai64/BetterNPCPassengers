-- Better NPC Passengers - English Localization
-- This file contains all translatable strings for the addon

local L = language and language.GetPhrase or function(s) return s end

-- Addon name
language.Add("npcpassengers.name", "Better NPC Passengers")
language.Add("npcpassengers.settings", "Settings")

-- Navigation / Tab names
language.Add("npcpassengers.nav.general", "General")
language.Add("npcpassengers.nav.autojoin", "Auto-Join")
language.Add("npcpassengers.nav.passengers", "Passengers")
language.Add("npcpassengers.nav.position", "Position")
language.Add("npcpassengers.nav.behaviour", "Behaviour")
language.Add("npcpassengers.nav.keybinds", "Keybinds")
language.Add("npcpassengers.nav.hud", "HUD")
language.Add("npcpassengers.nav.driver", "Driver")
language.Add("npcpassengers.nav.help", "Help")

-- General Settings
language.Add("npcpassengers.general.header", "General Settings")
language.Add("npcpassengers.allow_multiple", "Allow Multiple Passengers")
language.Add("npcpassengers.allow_multiple.help", "Let multiple NPCs ride in the same vehicle.")
language.Add("npcpassengers.exit_behavior", "Exit Behavior")
language.Add("npcpassengers.exit_behavior.help", "When should NPC passengers exit the vehicle?")
language.Add("npcpassengers.exit_mode.leave_player", "Leave when player exits")
language.Add("npcpassengers.exit_mode.leave_attack", "Leave when vehicle is attacked")
language.Add("npcpassengers.exit_mode.never", "Never leave automatically")

-- Timing Settings
language.Add("npcpassengers.timing.header", "Timing")
language.Add("npcpassengers.max_attach_dist", "Max Attach Distance")
language.Add("npcpassengers.max_attach_dist.help", "Maximum distance (units) to attach NPC to vehicle.")
language.Add("npcpassengers.detach_delay", "Detach Delay")
language.Add("npcpassengers.detach_delay.help", "Seconds to wait before detaching after player leaves.")
language.Add("npcpassengers.ai_delay", "AI Restore Delay")
language.Add("npcpassengers.ai_delay.help", "Seconds to wait before restoring NPC AI after detaching.")
language.Add("npcpassengers.cooldown", "Cooldown Time")
language.Add("npcpassengers.cooldown.help", "Cooldown between attaching NPCs to same vehicle.")
language.Add("npcpassengers.passenger_limit", "Passenger Limit")
language.Add("npcpassengers.passenger_limit.help", "Max NPCs allowed in vehicle.")

-- Auto-Join Settings
language.Add("npcpassengers.autojoin.header", "Auto-Join (Squad Behavior)")
language.Add("npcpassengers.autojoin.desc", "Friendly NPCs will automatically board your vehicle when you enter it - just like squad mechanics in Half-Life 2!")
language.Add("npcpassengers.autojoin.enable", "Enable Auto-Join")
language.Add("npcpassengers.autojoin.enable.help", "Nearby friendly NPCs will automatically join when you enter a vehicle.")
language.Add("npcpassengers.autojoin.range", "Auto-Join Range")
language.Add("npcpassengers.autojoin.range.help", "Maximum distance to find NPCs for auto-joining.")
language.Add("npcpassengers.autojoin.max", "Max Auto-Join NPCs")
language.Add("npcpassengers.autojoin.max.help", "Maximum number of NPCs that can auto-join at once.")
language.Add("npcpassengers.autojoin.squad_only", "Squad Members Only")
language.Add("npcpassengers.autojoin.squad_only.help", "Only NPCs with a squad name will auto-join (for HL2-style squads).")

-- Position Settings
language.Add("npcpassengers.position.header", "Position Offsets")
language.Add("npcpassengers.position.desc", "Fine-tune NPC positioning in vehicles. Use these to fix floating or clipping issues.")
language.Add("npcpassengers.height_offset", "Height Offset")
language.Add("npcpassengers.forward_offset", "Forward Offset")
language.Add("npcpassengers.right_offset", "Right Offset")
language.Add("npcpassengers.angle.header", "Angle Offsets")
language.Add("npcpassengers.angle.desc", "Adjust NPC rotation in vehicles.")
language.Add("npcpassengers.yaw_offset", "Yaw (Rotation)")
language.Add("npcpassengers.pitch_offset", "Pitch (Tilt Forward)")
language.Add("npcpassengers.roll_offset", "Roll (Tilt Sideways)")

-- Behaviour Settings
language.Add("npcpassengers.behaviour.header", "NPC Speech (Advanced)")
language.Add("npcpassengers.behaviour.desc", "Configure how NPCs vocalize while riding in vehicles. HL2-style citizen voices!")
language.Add("npcpassengers.speech_enable", "Enable NPC Speech")
language.Add("npcpassengers.speech_enable.help", "Master toggle for all NPC speech. Disable to silence passengers completely.")
language.Add("npcpassengers.speech_volume", "Speech Volume")
language.Add("npcpassengers.speech_volume.help", "How loud NPC voices are (0 = silent, 100 = full volume).")
language.Add("npcpassengers.pitch_variation", "Pitch Variation (+/-)")
language.Add("npcpassengers.pitch_variation.help", "Random pitch variation for more natural voices. 0 = monotone, higher = more variety.")
language.Add("npcpassengers.crash.header", "Crash Reactions")
language.Add("npcpassengers.crash_enable", "Enable Crash Sounds")
language.Add("npcpassengers.crash_enable.help", "NPCs grunt/yelp when vehicle decelerates sharply (crashes, hard braking).")
language.Add("npcpassengers.crash_threshold", "Crash Sensitivity")
language.Add("npcpassengers.crash_threshold.help", "Deceleration needed to trigger crash sounds. Lower = more sensitive.")
language.Add("npcpassengers.crash_cooldown", "Crash Sound Cooldown")
language.Add("npcpassengers.crash_cooldown.help", "Minimum seconds between crash sounds per NPC.")

-- Keybinds
language.Add("npcpassengers.keybinds.header", "Keybinds")
language.Add("npcpassengers.keybinds.desc", "Configure keyboard shortcuts for quick actions.")
language.Add("npcpassengers.keybind.attach", "Attach Nearest NPC")
language.Add("npcpassengers.keybind.attach.help", "Attach the nearest friendly NPC to your vehicle.")
language.Add("npcpassengers.keybind.detach_all", "Detach All NPCs")
language.Add("npcpassengers.keybind.detach_all.help", "Remove all passengers from your vehicle.")
language.Add("npcpassengers.keybind.toggle_autojoin", "Toggle Auto-Join")
language.Add("npcpassengers.keybind.toggle_autojoin.help", "Quickly enable/disable auto-join.")
language.Add("npcpassengers.keybind.menu", "Open Settings Menu")
language.Add("npcpassengers.keybind.menu.help", "Open the settings panel.")
language.Add("npcpassengers.keybind.exit_all", "Exit All Passengers")
language.Add("npcpassengers.keybind.exit_all.help", "Make all passengers leave the vehicle.")
language.Add("npcpassengers.keybind.toggle_hud", "Toggle HUD")
language.Add("npcpassengers.keybind.toggle_hud.help", "Show/hide the passenger HUD.")

-- HUD Settings
language.Add("npcpassengers.hud.header", "HUD Settings")
language.Add("npcpassengers.hud.enable", "Enable HUD")
language.Add("npcpassengers.hud.enable.help", "Show passenger status overlay on screen.")
language.Add("npcpassengers.hud.position", "HUD Position")
language.Add("npcpassengers.hud.position.help", "Where the HUD appears on screen.")
language.Add("npcpassengers.hud.position.topleft", "Top Left")
language.Add("npcpassengers.hud.position.topright", "Top Right")
language.Add("npcpassengers.hud.position.bottomleft", "Bottom Left")
language.Add("npcpassengers.hud.position.bottomright", "Bottom Right")
language.Add("npcpassengers.hud.scale", "HUD Scale")
language.Add("npcpassengers.hud.scale.help", "Size multiplier for the HUD.")
language.Add("npcpassengers.hud.opacity", "HUD Opacity")
language.Add("npcpassengers.hud.opacity.help", "Background transparency (0 = invisible, 1 = solid).")

-- Driver Settings
language.Add("npcpassengers.driver.header", "NPC Driver")
language.Add("npcpassengers.driver.desc", "Allow NPCs to drive vehicles for you.")
language.Add("npcpassengers.driver.enable", "Enable NPC Drivers")
language.Add("npcpassengers.driver.enable.help", "Allow NPCs to take control of vehicles.")
language.Add("npcpassengers.driver.behavior", "Driving Behavior")
language.Add("npcpassengers.driver.behavior.help", "How the NPC drives the vehicle.")
language.Add("npcpassengers.driver.behavior.cruise", "Random Cruise")
language.Add("npcpassengers.driver.behavior.follow", "Follow Player")
language.Add("npcpassengers.driver.behavior.patrol", "Patrol")
language.Add("npcpassengers.driver.behavior.flee", "Flee")
language.Add("npcpassengers.driver.behavior.parked", "Stay Parked")

-- Help / FAQ
language.Add("npcpassengers.help.header", "Frequently Asked Questions")
language.Add("npcpassengers.help.desc", "Quick answers to common questions and troubleshooting.")
language.Add("npcpassengers.help.still_need", "Still Need Help?")
language.Add("npcpassengers.help.community", "Join our Discord community for support!")

-- Additional navigation tabs
language.Add("npcpassengers.nav.tank", "Tank/LVS")
language.Add("npcpassengers.nav.debugging", "Debugging")
language.Add("npcpassengers.nav.driver", "NPC Driver")
language.Add("npcpassengers.nav.interface", "Interface")
language.Add("npcpassengers.nav.simulate", "Simulate")
language.Add("npcpassengers.nav.modules", "Modules")
language.Add("npcpassengers.nav.about", "About")
language.Add("npcpassengers.search.placeholder", "Search settings...")

-- Status messages
language.Add("npcpassengers.status.calm", "CALM")
language.Add("npcpassengers.status.alert", "ALERT")
language.Add("npcpassengers.status.scared", "SCARED")
language.Add("npcpassengers.status.drowsy", "DROWSY")
language.Add("npcpassengers.status.dead", "DEAD")
language.Add("npcpassengers.status.calm.desc", "Relaxed, no threats nearby")
language.Add("npcpassengers.status.alert.desc", "Enemy detected, NPC is tracking threats")
language.Add("npcpassengers.status.scared.desc", "Dangerous driving (high speed, crashes)")
language.Add("npcpassengers.status.drowsy.desc", "Long calm ride, NPC is getting sleepy")
language.Add("npcpassengers.status.dead.desc", "Health reached zero")

-- Chat messages
language.Add("npcpassengers.chat.autojoin_on", "Auto-Join: ON")
language.Add("npcpassengers.chat.autojoin_off", "Auto-Join: OFF")
language.Add("npcpassengers.chat.hud_on", "HUD: ON")
language.Add("npcpassengers.chat.hud_off", "HUD: OFF")
language.Add("npcpassengers.chat.prefix", "[Better NPC Passengers]")

-- Error messages
language.Add("npcpassengers.error.no_vehicle", "No vehicle nearby")
language.Add("npcpassengers.error.no_npc", "No NPC nearby")
language.Add("npcpassengers.error.vehicle_full", "Vehicle is full")
language.Add("npcpassengers.error.too_far", "NPC too far from vehicle")

-- UI tooltips
language.Add("npcpassengers.tooltip.changelang", "Change language")
language.Add("npcpassengers.tooltip.minimize", "Minimize panel")
language.Add("npcpassengers.tooltip.expand", "Expand panel")

print("[Better NPC Passengers] English localization loaded")
