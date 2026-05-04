# v2.7.8

### Changes
- Added custom font selection feature
- Added "Change Font" dropdown menu with known font names (Metropolis, Bebas Neue, Share Tech)
- Added text entry field for manual font name input
- Dropdown and text entry only show when "Use Default Font" is unchecked
- Font changes apply immediately to the UI
- Added sample fonts: bebasneue.ttf and sharetech.ttf
- Fixed GetConVarStringSafe error in font dropdown
- Fixed custom font loading by copying fonts to global resource/fonts folder on addon load
- Fixed font system to use actual font names instead of filenames
- Fixed welcome panel "don't show again" to actually never show again (removed version check)
- Optimized font system with caching to reduce unnecessary file operations

### Technical Details
- Added ConVar `nai_npc_ui_custom_font` in settings.lua
- Created `InstallAddonFonts()` function to copy fonts from addon folder to global resource/fonts/ on load
- Created `GetAvailableFonts()` function that returns known font names instead of scanning filenames
- Modified `GetUIFontName()` to check custom font ConVar before defaulting to "Metropolis"
- Font dropdown and text entry added in Interface tab
- Text entry syncs with dropdown selection
- GMod's surface.CreateFont requires actual font names (e.g., "Bebas Neue") not filenames
- Removed version check from welcome panel logic so "don't show again" persists across updates
- Added caching to InstallAddonFonts to prevent repeated file copy operations
- Added caching to GetAvailableFonts to avoid repeated file existence checks
