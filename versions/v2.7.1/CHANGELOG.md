# v2.7.1

## Features
- Add UI panel opacity customization
  - Panel fades when mouse is not over it (configurable)
  - Idle panel opacity slider (0-100%, default 30%)
  - Scrollbar auto-hide when not scrolling/hovering
  - Panel becomes 70% transparent when dragging scrollbar

## UI Controls
- Added "Fade Panel When Idle" checkbox in Interface settings
- Added "Idle Panel Opacity (%)" slider in Interface settings
- Added "Auto-Hide Scrollbar" checkbox in Interface settings

## Bug Fixes
- Fixed scrollbar auto-hide error (removed IsDown() call that doesn't exist)
- Fixed Lua goto scope error by using nested if-else statements
- Fixed duplicate Think function overwriting idle fade logic
