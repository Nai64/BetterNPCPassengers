# Better NPC Passengers Changelog

## v2.5.22

### Bug Fixes
- **Fixed NPC returning to boarding position after ejection** — walk timer is now properly cleaned up when NPCs detach from vehicles, preventing them from attempting to return to the original boarding location

## v2.5.21

### Improvements
- **Comprehensive changelog documentation** — added formal CHANGELOG.md following release template standards
- **Release standards compliance** — adopted corrected zip naming convention: `BetterNPCPassengers-v*.zip`

## v2.5.20

### Improvements
- **Code cleanup and maintainability** — removed redundant comment patterns across core modules
- **Consolidated helper functions** — improved clarity and structure of helper implementations
- **Enhanced readability** — improved overall code organization and structure

## v2.5.19

### Bug Fixes
- **Fixed circular checkbox crash** — added safe draw.Circle implementation for environments missing the global draw.Circle function

## v2.5.18

### Improvements
- **Circular checkbox design** — redesigned all checkboxes in the settings panel to use a modern circular appearance with filled dot indicator

## v2.5.17

### Performance
- **Passenger count and seat registry** — replaced repeated scans with shared registries for O(1) lookups
- **Shared animation think loop** — moved passenger sit animation upkeep from per-NPC timers to a single shared think hook
- **Turret target caching** — reworked LVS turret targeting to reuse tracked NPC pool instead of rebuilding from world every scan
- **Client passenger tracking** — updated client-side tracking to react to networked state changes with slower fallback rescans
- **State management optimization** — unified passenger state mutations through shared helper functions for detach, reset, and seat reassignment

## v2.5.16

### Performance
- **Passenger upkeep throttling** — server-side passenger maintenance now runs on a throttled cadence
- **Relationship refresh batching** — repeated player relationship refreshes are now batched to reduce overhead
- **HUD passenger caching** — passenger HUD now reuses tracked passengers instead of rescanning every update
- **Seat lookup caching** — vehicle seat lookups are now cached client-side with invalidation on seat changes

## v2.5.15 and Earlier

- See GitHub releases for detailed history: https://github.com/Nai64/BetterNPCPassengers/releases
