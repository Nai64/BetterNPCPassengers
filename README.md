*Better NPC Passengers*

<div align="center">

[![Version](https://img.shields.io/badge/version-v2.4-blue?style=for-the-badge)](https://github.com/naidev5/BetterNPCPassengers-gmod/releases)
[![GMod](https://img.shields.io/badge/Garry's%20Mod-Addon-black?style=for-the-badge&logo=steam)](https://store.steampowered.com/app/4000/Garrys_Mod/)
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
- [Features](#-features)
- [Quick Start](#-quick-start)
- [Settings](#️-settings)
- [Common Issues](#-common-issues)
- [Changelog](#-changelog)

---

## 🔍 Overview

Ever wanted to bring your Combine soldier friend along for a road trip? Or maybe evacuate Citizens in your LVS helicopter? Now you can!

This addon allows NPCs to enter vehicles as passengers, complete with **lifelike animations**, **dynamic head tracking**, **emotional reactions**, and **multi-passenger support**.

| Feature | Description |
|---|---|
| 🧠 Passenger States | CALM / ALERT / SCARED / DROWSY / DEAD with real-time HUD |
| 💥 Crash Damage | High-speed impacts injure passengers with scaled severity |
| 🪦 Dead Body Management | Hold `R` near a body to remove it — red glow + skull indicator |
| 🤝 Auto-Join | Squad-like behavior — nearby NPCs automatically board your vehicle |
| 🌀 Advanced Physics | Body sway in turns, crash flinch, drowsy head nods |
| 🖥️ Modern UI | Polished settings panel with gradients, animations, and tooltips |
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

Open the settings panel via **`F7`** or **Spawnmenu → Utilities → NPC Passengers**.

All settings are saved per-client or per-server as appropriate. A debug mode is available for server administrators.

---

## 🔧 Common Issues

| Problem | Solution |
|---|---|
| NPC floating above seat | Use the Position Offset controls in the settings panel (`F7`) to correct alignment for that vehicle model |
| NPC keeps dying in crashes | Increase the crash damage threshold in settings, or reduce crash damage scaling |
| Dead body cannot be removed | Move closer to the vehicle and hold `R` for the full duration |
| Auto-Join not triggering | Verify search range and max passenger count in the Auto-Join tab; ensure NPCs are friendly to the player |
| Passengers not boarding a specific vehicle | Check whether the vehicle class or model matches an entry in `nai_npc_deny_classes` or `nai_npc_deny_models` |

---

## 📝 Changelog

<details>
<summary><b>v2.4 — March 2026</b></summary>

**Performance**
- **Seat Discovery Cache** — Vehicle seat layout is now cached per vehicle and only rebuilt when the vehicle's children change. Eliminates repeated seat traversal and sort on every boarding query.
- **Animation Timer Throttling** — Per-passenger maintenance work (enemy tracking, relationship updates, head look, transform sync) is now gated by independent time intervals instead of running on every tick. Significantly reduces per-NPC CPU cost at higher passenger counts.
- **Client Entity Tracking** — The body-sway hook no longer scans all entities every frame. Passengers are tracked in a dedicated table and refreshed once per second, removing the per-frame `ents.GetAll()` call entirely.

**Quality of Life**
- **Vehicle Filtering** — Added server-side allow and deny lists for vehicle classes and models with CSV wildcard pattern support.
- **Boarding Retry Cooldown** — NPCs that fail to board repeatedly now enter a cooldown period instead of looping indefinitely. Attempt limit and cooldown duration are configurable.
- **Squad-Only Auto-Join** — Auto-Join can now be restricted to the player's active squad (`nai_npc_auto_join_squad_only`).
- **Global Enable Toggle** — Added `nai_npc_enabled` convar to disable all addon functionality server-side without uninstalling.

**Bug Fixes**
- Fixed an early-return defect in vehicle seat collection that caused boarding to silently fail on the first attempt when the vehicle cache was cold.

**Code**
- Removed Nai Base API dependency. All internal identifiers previously prefixed with `Nai` or `NaiPassengers` have been renamed to `NPCPassengers`. Saved ConVar names (`nai_npc_*`) are unchanged to preserve existing user configurations.

</details>

---

<div align="center">

*Enjoy the ride! Please report any bugs or compatibility issues in the comments.*

[![YouTube](https://img.shields.io/badge/YouTube-%40naidev5-FF0000?style=flat-square&logo=youtube&logoColor=white)](https://youtube.com/@naidev5)
[![Discord](https://img.shields.io/badge/Discord-Community-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/RYbnePuvZE)

</div>