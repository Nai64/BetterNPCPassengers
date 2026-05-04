# v2.7.8

### Changes
- Added custom font selection feature
- Fonts are auto-detected from resource/fonts/ folder
- Added "Change Font" dropdown menu in Interface tab
- Dropdown only shows when "Use Default Font" is unchecked
- Font changes apply immediately to the UI
- Added sample fonts: bebasneue.ttf and sharetech.ttf

### Technical Details
- Added ConVar `nai_npc_ui_custom_font` in settings.lua
- Created `GetAvailableFonts()` function in ui.lua that scans resource/fonts/*.ttf
- Modified `GetUIFontName()` to check custom font ConVar before defaulting to "Metropolis"
- Font dropdown added in Interface tab (lines 3980-4037 in ui.lua)
