# v2.7.8

### Changes
- Added custom font selection feature
- Fonts are auto-detected from resource/fonts/ folder
- Added "Change Font" dropdown menu in Interface tab
- Dropdown only shows when "Use Default Font" is unchecked
- Font changes apply immediately to the UI
- Added sample fonts: bebasneue.ttf and sharetech.ttf
- Fixed GetConVarStringSafe error in font dropdown
- Fixed custom font loading by copying fonts to global resource/fonts folder on addon load

### Technical Details
- Added ConVar `nai_npc_ui_custom_font` in settings.lua
- Created `InstallAddonFonts()` function to copy fonts from addon folder to global resource/fonts/ on load
- Created `GetAvailableFonts()` function in ui.lua that scans global resource/fonts/*.ttf
- Modified `GetUIFontName()` to check custom font ConVar before defaulting to "Metropolis"
- Font dropdown added in Interface tab (lines 3980-4037 in ui.lua)
- Fixed ConVar access to use GetConVar(name):GetString() with fallback instead of non-existent GetConVarStringSafe
- GMod's surface.CreateFont requires fonts to be in global resource/fonts/, so fonts are copied there on addon load
