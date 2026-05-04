# Better NPC Passengers

<div align="center">


[![Version](https://img.shields.io/badge/version-v2.7.1-blue?style=for-the-badge)](https://github.com/Nai64/BetterNPCPassengers/releases)
[![GMod](https://img.shields.io/badge/Garry's%20Mod-Addon-black?style=for-the-badge&logo=steam)](https://store.steampowered.com/app/4000/Garrys_Mod/)
[![Workshop](https://img.shields.io/badge/Steam%20Workshop-Subscribe-1b2838?style=for-the-badge&logo=steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=3633546098)
[![Lua](https://img.shields.io/badge/Lua-5.1-2C2D72?style=for-the-badge&logo=lua)](https://www.lua.org/)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-Join-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/RYbnePuvZE)
[![YouTube](https://img.shields.io/badge/YouTube-Watch-FF0000?style=for-the-badge&logo=youtube&logoColor=white)](https://youtube.com/@naidev5)

*Board NPCs into vehicles with full animation, emotional state tracking, and multi-framework support.*

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Supported Vehicle Frameworks](#-supported-vehicle-frameworks)
- [Supported NPC Frameworks](#-supported-npc-frameworks)
- [Features](#-features)
- [Quick Start](#-quick-start)
- [Settings](#️-settings)
- [Common Issues](#-common-issues)

---

## 🔍 Overview

Ever wanted to bring your Combine soldier friend along for a road trip? Or maybe evacuate Citizens in your LVS helicopter? Now you can!

This addon allows NPCs to enter vehicles as passengers, complete with **lifelike animations**, **dynamic head tracking**, **emotional reactions**, and **multi-passenger support**.

| Feature | Description |
|---|---|
| 🧠 Passenger States | CALM / ALERT / SCARED / DROWSY / DEAD with real-time HUD |
| 💥 Crash Damage | High-speed impacts injure passengers with scaled severity |
| 💀 Vehicle Destruction | Passengers die with the vehicle when it explodes |
| 🚪 Smart Exit | NPCs no-collide with the vehicle on detach so they don't get stuck |
| 🪦 Dead Body Management | Hold `R` near a body to remove it — red glow + skull indicator |
| 🤝 Auto-Join | Squad-like behavior — nearby NPCs automatically board your vehicle |
| 🌀 Advanced Physics | Body sway in turns, crash flinch, drowsy head nods |
| 🖥️ Modern UI | Polished settings panel with fluid animations and tooltips |
| ❓ Help System | Built-in FAQ section with 17+ common questions answered |

---

## 🚗 Supported Vehicle Frameworks

| Framework | Passenger | NPC Driver | NPC Gunner |
|---|:---:|:---:|:---:|
| Simfphys (LUA Vehicles) | ✅ | ✅ | — |
| LVS Framework | ✅ | ✅ | ✅ |
| Glide Vehicles | ✅ | ✅ | — |
| SligWolf Vehicles | ✅ | — | — |
| Standard HL2 (Jeep, Jalopy, APC…) | ✅ | — | — |
| `prop_vehicle_prisoner_pod` | ✅ | — | — |

---

## 🤖 Supported NPC Frameworks

| Framework | Status |
|---|:---:|
| Standard HL2 NPCs (Combine, Citizens, Zombies, …) | ✅ |
| **VJ Base SNPCs** | ✅ (proper AI suspend / restore) |
| Custom NPCs using GMod's standard NPC base | ✅ |

> VJ Base support is implemented as a dedicated module (`vj_base.lua`) that hooks `VJ_IsBeingControlled`, `VJ_STATE_FREEZE`, and the `VJ_NPC_Class` faction system. NPC state is fully restored on detach.

---

## ✨ Features

<details>
<summary><b>🧠 Animation & Physical Response</b></summary>

- **Body Sway** — NPCs physically lean with the vehicle through turns, acceleration, and braking. Intensity is adjustable.
- **Crash Flinch** — High-speed deceleration triggers a flinch and bracing animation. Threshold is configurable.
- **Head Tracking** — NPCs track the driver, nearby threats, and points of interest. Movement smoothing is tunable.
- **Eye Movement** — Micro-glances independent of the head for natural-looking gaze behavior.
- **Blinking** — Automatic eyelid animation with randomized interval timing.
- **Breathing** — Subtle idle breathing cycle animation.
- **Talking Gestures** — Random hand and body gesture animations during idle conversation periods.

</details>

<details>
<summary><b>💬 Emotional State System</b></summary>

NPCs transition between **CALM**, **ALERT**, **SCARED**, **DROWSY**, and **DEAD** states based on live conditions:

- **Threat Awareness** — Detects enemies within a configurable range and shifts NPCs to ALERT. Head tracks the threat direction.
- **Fear Reactions** — High speed or erratic driving transitions NPCs toward SCARED.
- **Drowsiness** — Extended calm travel gradually makes NPCs drowsy with appropriate head-nod behavior.
- **Crash Damage** — High-speed impacts deal health damage to passengers. Severity scales with deceleration force.

</details>

<details>
<summary><b>💥 Vehicle Damage & Destruction</b></summary>

- **Crash Damage** — Speed-based health damage to passengers on heavy impacts.
- **Vehicle Explosion Death** — When a vehicle is destroyed by blast, fire, or lethal damage, all passengers die. Kill credit is preserved (the player who blew it up gets the kill).
- **Toggleable** — Disable per-server via `nai_npc_die_with_vehicle 0`.

</details>

<details>
<summary><b>🚪 Detach Behavior</b></summary>

- **No-Collide on Exit** — NPCs temporarily ignore vehicle collision after detaching, so they can walk away cleanly.
- **Auto-Eject Stuck NPCs** — If an NPC gets stuck inside the vehicle on exit, they're automatically pushed out or teleported above the vehicle.
- Both features are configurable in **Vehicle Settings** with a duration slider.

</details>

<details>
<summary><b>🔊 NPC Speech & Audio</b></summary>

- **Boarding Lines** — Context-aware lines when entering or exiting the vehicle.
- **Idle Chatter** — Occasional conversation during travel with configurable frequency and chance.
- **Passenger Interaction** — Multiple passengers will look at and talk to one another.
- **Crash Reactions** — Pain sounds and verbal responses on impact events.
- **Ambient Sounds** — Low-frequency sounds such as coughs, sighs, and hums with configurable interval.
- **Pitch Variation** — Random pitch offset per NPC for natural vocal differentiation.

</details>

<details>
<summary><b>📊 Passenger Status HUD</b></summary>

- Real-time state display per passenger (CALM / ALERT / SCARED / DROWSY / DEAD)
- Animated health bars per passenger
- Red glow and skull icon for dead passengers
- Fully configurable: position, scale, opacity, and threshold values

</details>

<details>
<summary><b>🤝 Auto-Join System</b></summary>

- Nearby friendly NPCs automatically board available seats when the player enters a vehicle.
- Configurable search range and maximum count per vehicle.
- **Squad-only mode** — only NPCs in the player's active squad will board.
- Can be toggled at any time via keybind or settings panel.

</details>

<details>
<summary><b>👥 Multi-Passenger & Boarding Logic</b></summary>

- Supports up to **8 passengers** per vehicle (configurable hard cap).
- Manual queuing via right-click context menu for targeting specific NPCs.
- Seat discovery is framework-aware — never assigns the driver seat or an occupied seat.
- Dead passengers do not count toward seat occupancy.
- Retry system with configurable attempt limit and cooldown on repeated boarding failures.

</details>

<details>
<summary><b>🎯 NPC Driver & Gunner</b></summary>

- Assign an NPC as the **driver** of a Simfphys / LVS / Glide vehicle. They navigate toward enemies using pathfinding.
- Air-vehicle support for LVS helicopters and planes.
- Assign an NPC to an **LVS turret seat** for autonomous fire support — with friendly-fire prevention, target leading, and a hold-fire toggle.

</details>

<details>
<summary><b>🚫 Vehicle Filtering</b></summary>

Server-side allow and deny lists for vehicle **classes** and **models** using comma-separated patterns with wildcard (`*`) support.

| ConVar | Purpose |
|---|---|
| `nai_npc_allow_classes` | Whitelist vehicle classes |
| `nai_npc_deny_classes` | Blacklist vehicle classes |
| `nai_npc_allow_models` | Whitelist vehicle models |
| `nai_npc_deny_models` | Blacklist vehicle models |

> Deny lists are evaluated before allow lists. An empty allow list permits all non-denied vehicles.

</details>

---

## 🎮 Quick Start

**Auto-Join (recommended)**
```
Press F7  →  navigate to the Auto-Join tab  →  enable Auto-Join  →  enter a vehicle
```
Nearby friendly NPCs will board automatically.

**Manual boarding**
```
Hold C  →  right-click an NPC  →  Make Passenger  →  enter a vehicle
```

**Remove a passenger** — Right-click the NPC → **Detach Passenger**

**Remove a dead body** — Approach the vehicle and hold `R`

---

## ⚙️ Settings

Open the settings panel via **`F7`** or **Spawnmenu → Utilities → Better NPC Passengers**.

All settings are saved per-client or per-server as appropriate. A debug mode is available for server administrators.

---

## 🐛 Common Issues

- **NPC floating above the seat** — Use Position Offset sliders in the settings panel.
- **NPC keeps dying in crashes** — Raise the crash damage threshold or lower the crash damage scaling.
- **Dead body cannot be removed** — Move closer to the vehicle and hold `R` for the full duration.
- **Auto-Join not triggering** — Check search range and max-passenger count in the Auto-Join tab. Ensure the NPCs are friendly to you.
- **Passengers not boarding a specific vehicle** — Check the deny ConVars: `nai_npc_deny_classes`, `nai_npc_deny_models`.
- **VJ NPCs acting weird as passengers** — Make sure you're on v2.7.0+ which has dedicated VJ Base support. Older versions only had partial compatibility.

---

<div align="center">

*Enjoy the ride! Please report any bugs or compatibility issues in the comments.*

[![YouTube](https://img.shields.io/badge/YouTube-%40naidev5-FF0000?style=flat-square&logo=youtube&logoColor=white)](https://youtube.com/@naidev5)
[![Discord](https://img.shields.io/badge/Discord-Community-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/RYbnePuvZE)

</div>
