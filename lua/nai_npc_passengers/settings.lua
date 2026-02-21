NaiPassengers = NaiPassengers or {}

NaiPassengers.cv_max_dist = CreateConVar("nai_npc_max_attach_dist", "500", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Maximum distance to attach NPC")
NaiPassengers.cv_detach_delay = CreateConVar("nai_npc_detach_delay", "0.5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Delay before detaching")
NaiPassengers.cv_ai_delay = CreateConVar("nai_npc_ai_delay", "2", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Delay before restoring AI")
NaiPassengers.cv_cooldown = CreateConVar("nai_npc_cooldown", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Cooldown between attachments")
NaiPassengers.cv_multiple = CreateConVar("nai_npc_allow_multiple", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Allow multiple passengers")
NaiPassengers.cv_exit_mode = CreateConVar("nai_npc_exit_mode", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Exit behavior: 0=leave when player exits, 1=leave when attacked, 2=never leave")
NaiPassengers.cv_hide_in_tanks = CreateConVar("nai_npc_hide_in_tanks", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Hide NPCs inside enclosed vehicles like tanks")

-- Auto-join settings
NaiPassengers.cv_auto_join = CreateConVar("nai_npc_auto_join", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Friendly NPCs automatically join vehicles")
NaiPassengers.cv_auto_join_range = CreateConVar("nai_npc_auto_join_range", "500", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Range to find NPCs for auto-join")
NaiPassengers.cv_auto_join_max = CreateConVar("nai_npc_auto_join_max", "4", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Max NPCs to auto-join per vehicle")
NaiPassengers.cv_auto_join_squad_only = CreateConVar("nai_npc_auto_join_squad_only", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Only squad members auto-join (requires squad name)")

-- NPC Speech settings
NaiPassengers.cv_speech_enabled = CreateConVar("nai_npc_speech_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable NPC speech while in vehicles")

-- UI & Interface Settings (client-side)
if CLIENT then
    NaiPassengers.cv_ui_sounds_enabled = CreateClientConVar("nai_npc_ui_sounds_enabled", "1", true, false, "Enable UI sound effects")
    NaiPassengers.cv_ui_sounds_volume = CreateClientConVar("nai_npc_ui_sounds_volume", "1", true, false, "UI sounds volume multiplier")
    NaiPassengers.cv_ui_hover_enabled = CreateClientConVar("nai_npc_ui_hover_enabled", "1", true, false, "Enable hover sounds")
    NaiPassengers.cv_ui_click_enabled = CreateClientConVar("nai_npc_ui_click_enabled", "1", true, false, "Enable click sounds")
    NaiPassengers.cv_context_make_passenger = CreateClientConVar("nai_npc_context_make_passenger", "1", true, false, "Show 'Make Passenger' in context menu")
    NaiPassengers.cv_context_make_passenger_for_vehicle = CreateClientConVar("nai_npc_context_make_passenger_vehicle", "1", true, false, "Show 'Make Passenger For Vehicle' in context menu")
    NaiPassengers.cv_context_detach_passenger = CreateClientConVar("nai_npc_context_detach", "1", true, false, "Show 'Detach Passenger' in context menu")
    NaiPassengers.cv_ui_show_welcome = CreateClientConVar("nai_npc_ui_show_welcome", "1", true, false, "Show welcome screen on updates")
    NaiPassengers.cv_ui_panel_width = CreateClientConVar("nai_npc_ui_panel_width", "950", true, false, "Settings panel width")
    NaiPassengers.cv_ui_panel_height = CreateClientConVar("nai_npc_ui_panel_height", "700", true, false, "Settings panel height")
    NaiPassengers.cv_ui_animations = CreateClientConVar("nai_npc_ui_animations", "1", true, false, "Enable UI animations")
    NaiPassengers.cv_ui_tooltips = CreateClientConVar("nai_npc_ui_tooltips", "1", true, false, "Show tooltips in UI")
end
NaiPassengers.cv_speech_volume = CreateConVar("nai_npc_speech_volume", "75", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPC speech volume (0-100)")
NaiPassengers.cv_speech_crash_enabled = CreateConVar("nai_npc_speech_crash", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs react to crashes with pain sounds")
NaiPassengers.cv_speech_crash_threshold = CreateConVar("nai_npc_speech_crash_threshold", "400", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Deceleration required to trigger crash sounds")
NaiPassengers.cv_speech_crash_cooldown = CreateConVar("nai_npc_speech_crash_cooldown", "1.5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Cooldown between crash sounds per NPC")
NaiPassengers.cv_speech_idle_enabled = CreateConVar("nai_npc_speech_idle", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs occasionally chatter while riding")
NaiPassengers.cv_speech_idle_chance = CreateConVar("nai_npc_speech_idle_chance", "0.3", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Chance per check for idle chatter (0-1)")
NaiPassengers.cv_speech_idle_interval = CreateConVar("nai_npc_speech_idle_interval", "15", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Minimum seconds between idle chatter")
NaiPassengers.cv_speech_board_enabled = CreateConVar("nai_npc_speech_board", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs speak when boarding/exiting")
NaiPassengers.cv_speech_pitch_variation = CreateConVar("nai_npc_speech_pitch_var", "5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Random pitch variation (+/- this value)")

-- Animation and behavior settings
NaiPassengers.cv_head_look = CreateConVar("nai_npc_head_look", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable realistic head/eye looking behavior")
NaiPassengers.cv_head_smooth = CreateConVar("nai_npc_head_smooth", "0.4", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Head movement smoothing (lower = snappier)")
NaiPassengers.cv_blink_enabled = CreateConVar("nai_npc_blink", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable NPC blinking animation")
NaiPassengers.cv_breathing = CreateConVar("nai_npc_breathing", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable subtle breathing animation")
NaiPassengers.cv_walk_timeout = CreateConVar("nai_npc_walk_timeout", "5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Seconds before NPC gives up walking to vehicle")

-- Advanced realism settings
NaiPassengers.cv_body_sway = CreateConVar("nai_npc_body_sway", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs lean with vehicle movement (turns, accel, brake)")
NaiPassengers.cv_body_sway_amount = CreateConVar("nai_npc_body_sway_amount", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Body sway intensity multiplier")
NaiPassengers.cv_threat_awareness = CreateConVar("nai_npc_threat_awareness", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs look toward nearby enemies")
NaiPassengers.cv_threat_range = CreateConVar("nai_npc_threat_range", "1500", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Range to detect threats for head tracking")
NaiPassengers.cv_combat_alert = CreateConVar("nai_npc_combat_alert", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs become alert when enemies are near")
NaiPassengers.cv_fear_reactions = CreateConVar("nai_npc_fear_reactions", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs react to dangerous driving (high speed, near misses)")
NaiPassengers.cv_fear_speed_threshold = CreateConVar("nai_npc_fear_speed", "800", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Speed at which NPCs start getting nervous")
NaiPassengers.cv_drowsiness = CreateConVar("nai_npc_drowsiness", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs get drowsy on long calm rides")
NaiPassengers.cv_drowsy_time = CreateConVar("nai_npc_drowsy_time", "60", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Seconds of calm riding before drowsiness kicks in")
NaiPassengers.cv_ambient_sounds = CreateConVar("nai_npc_ambient_sounds", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Occasional ambient sounds (coughs, sighs, hums)")
NaiPassengers.cv_ambient_interval = CreateConVar("nai_npc_ambient_interval", "30", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Average seconds between ambient sounds")
NaiPassengers.cv_passenger_interaction = CreateConVar("nai_npc_passenger_interaction", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Multiple passengers look at and chat with each other")

-- Gesture animations
NaiPassengers.cv_talking_gestures = CreateConVar("nai_npc_talking_gestures", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs play random talking/hand gesture animations")
NaiPassengers.cv_gesture_chance = CreateConVar("nai_npc_gesture_chance", "15", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Percent chance per interval to play a gesture")
NaiPassengers.cv_gesture_interval = CreateConVar("nai_npc_gesture_interval", "8", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Seconds between gesture checks")
NaiPassengers.cv_crash_flinch = CreateConVar("nai_npc_crash_flinch", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs flinch and brace when vehicle crashes")
NaiPassengers.cv_crash_threshold = CreateConVar("nai_npc_crash_threshold", "400", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Velocity change needed to trigger crash reaction")

-- Debug mode
NaiPassengers.cv_debug_mode = CreateConVar("nai_npc_debug_mode", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable debug test buttons in settings panel")

-- HUD Settings
NaiPassengers.cv_hud_enabled = CreateConVar("nai_npc_hud_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable passenger status HUD")
NaiPassengers.cv_hud_position = CreateConVar("nai_npc_hud_position", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "HUD position: 0=Top Left, 1=Top Right, 2=Bottom Left, 3=Bottom Right")
NaiPassengers.cv_hud_scale = CreateConVar("nai_npc_hud_scale", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "HUD scale multiplier")
NaiPassengers.cv_hud_opacity = CreateConVar("nai_npc_hud_opacity", "0.85", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "HUD background opacity (0-1)")
NaiPassengers.cv_hud_show_calm = CreateConVar("nai_npc_hud_show_calm", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Show passengers with calm status")
NaiPassengers.cv_hud_only_in_vehicle = CreateConVar("nai_npc_hud_only_vehicle", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Only show HUD when player is in a vehicle")

-- HUD Emotion Thresholds
NaiPassengers.cv_hud_alert_threshold = CreateConVar("nai_npc_hud_alert_threshold", "0.3", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Alert level threshold to show alert status (0-1)")
NaiPassengers.cv_hud_fear_threshold = CreateConVar("nai_npc_hud_fear_threshold", "0.5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Fear level threshold to show scared status (0-1)")
NaiPassengers.cv_hud_drowsy_threshold = CreateConVar("nai_npc_hud_drowsy_threshold", "0.7", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Calm time ratio to show drowsy status (0-1)")

-- Emotion Action Settings (what passengers do when experiencing each emotion)
-- Action values: 0=Do Nothing, 1=Exit Vehicle, 2=Play Sound, 3=Duck/Crouch, 4=Look Around, 5=Cover Face, 6=Fall Asleep
NaiPassengers.cv_action_calm = CreateConVar("nai_npc_action_calm", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Action when passenger is calm")
NaiPassengers.cv_action_alert = CreateConVar("nai_npc_action_alert", "4", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Action when passenger is alert")
NaiPassengers.cv_action_scared = CreateConVar("nai_npc_action_scared", "2", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Action when passenger is scared")
NaiPassengers.cv_action_drowsy = CreateConVar("nai_npc_action_drowsy", "6", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Action when passenger is drowsy")

-- Position offset settings
NaiPassengers.cv_height_offset = CreateConVar("nai_npc_height_offset", "-3", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Additional vertical offset for passengers")
NaiPassengers.cv_forward_offset = CreateConVar("nai_npc_forward_offset", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Additional forward offset for passengers")
NaiPassengers.cv_right_offset = CreateConVar("nai_npc_right_offset", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Additional right offset for passengers")
NaiPassengers.cv_yaw_offset = CreateConVar("nai_npc_yaw_offset", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Additional yaw offset for passengers")
NaiPassengers.cv_pitch_offset = CreateConVar("nai_npc_pitch_offset", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Additional pitch offset for passengers")
NaiPassengers.cv_roll_offset = CreateConVar("nai_npc_roll_offset", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Additional roll offset for passengers")

-- NPC Driver settings
NaiPassengers.cv_driver_enabled = CreateConVar("nai_npc_driver_enabled", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Allow NPCs to drive vehicles")
NaiPassengers.cv_driver_behavior = CreateConVar("nai_npc_driver_behavior", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Driving behavior: 0=Random Cruise, 1=Follow Player, 2=Patrol, 3=Flee, 4=Stay Parked")
NaiPassengers.cv_driver_obey_traffic = CreateConVar("nai_npc_driver_obey_traffic", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs follow speed limits and traffic signals")
NaiPassengers.cv_driver_avoid_collisions = CreateConVar("nai_npc_driver_avoid_collisions", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs avoid hitting obstacles and vehicles")
NaiPassengers.cv_driver_honk = CreateConVar("nai_npc_driver_honk", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs use horn when frustrated")
NaiPassengers.cv_driver_speed = CreateConVar("nai_npc_driver_speed", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Driving speed multiplier")
NaiPassengers.cv_driver_skill = CreateConVar("nai_npc_driver_skill", "50", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Driver skill level (0-100)")
NaiPassengers.cv_driver_aggression = CreateConVar("nai_npc_driver_aggression", "30", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Driving aggression (0-100)")
NaiPassengers.cv_driver_wander_dist = CreateConVar("nai_npc_driver_wander_dist", "2000", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Wander distance for random cruise")
NaiPassengers.cv_driver_recalculate = CreateConVar("nai_npc_driver_recalculate", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Dynamic rerouting enabled")
NaiPassengers.cv_driver_reverse = CreateConVar("nai_npc_driver_reverse", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Allow reversing when stuck")
NaiPassengers.cv_driver_brake_distance = CreateConVar("nai_npc_driver_brake_distance", "200", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Distance to start braking")
NaiPassengers.cv_driver_auto_park = CreateConVar("nai_npc_driver_auto_park", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Auto park at destination")
NaiPassengers.cv_driver_exit_on_arrival = CreateConVar("nai_npc_driver_exit_on_arrival", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Exit vehicle on arrival")
NaiPassengers.cv_driver_stop_distance = CreateConVar("nai_npc_driver_stop_distance", "50", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Stop precision distance")
NaiPassengers.cv_driver_debug = CreateConVar("nai_npc_driver_debug", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Show driver debug info")
NaiPassengers.cv_driver_allow_all_npcs = CreateConVar("nai_npc_driver_allow_all_npcs", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Allow all NPC types to drive")
NaiPassengers.cv_driver_smooth_steering = CreateConVar("nai_npc_driver_smooth_steering", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Use smooth steering")

-- Keybind settings (client-side only, stored as key codes)
if CLIENT then
    NaiPassengers.cv_key_attach = CreateClientConVar("nai_npc_key_attach", "0", true, false, "Keybind: Attach nearest NPC")
    NaiPassengers.cv_key_detach_all = CreateClientConVar("nai_npc_key_detach_all", "0", true, false, "Keybind: Detach all passengers")
    NaiPassengers.cv_key_toggle_autojoin = CreateClientConVar("nai_npc_key_toggle_autojoin", "0", true, false, "Keybind: Toggle auto-join")
    NaiPassengers.cv_key_menu = CreateClientConVar("nai_npc_key_menu", "0", true, false, "Keybind: Open settings menu")
    NaiPassengers.cv_key_quick_attach = CreateClientConVar("nai_npc_key_quick_attach", "0", true, false, "Keybind: Quick attach mode")
    NaiPassengers.cv_key_exit_all = CreateClientConVar("nai_npc_key_exit_all", "0", true, false, "Keybind: NPCs exit vehicle")
    NaiPassengers.cv_key_hold_fire = CreateClientConVar("nai_npc_key_hold_fire", "0", true, false, "Keybind: NPCs hold fire")
    NaiPassengers.cv_key_open_fire = CreateClientConVar("nai_npc_key_open_fire", "0", true, false, "Keybind: NPCs open fire")
    NaiPassengers.cv_key_cycle_view = CreateClientConVar("nai_npc_key_cycle_view", "0", true, false, "Keybind: Cycle passenger view")
    NaiPassengers.cv_key_test_gesture = CreateClientConVar("nai_npc_key_test_gesture", "0", true, false, "Keybind: Test random gesture")
    NaiPassengers.cv_key_reset_all = CreateClientConVar("nai_npc_key_reset_all", "0", true, false, "Keybind: Reset all NPCs")
    NaiPassengers.cv_key_debug_hud = CreateClientConVar("nai_npc_key_debug_hud", "0", true, false, "Keybind: Toggle debug HUD")
end