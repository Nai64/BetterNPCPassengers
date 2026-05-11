# Better NPC Passengers - Localization Guide

## Overview

The addon now supports multi-language localization! This guide explains how to contribute translations.

## Current Status

- ✅ Localization infrastructure implemented
- ✅ English translation complete (base language)
- ✅ Russian and Chinese templates created (need translation)
- 🔄 UI strings partially localized (General tab complete)
- 🔄 Chat messages, HUD, and other strings need localization

## File Structure

```
resource/localization/
├── english.lua      # Complete English translations (base)
├── russian.lua      # Russian template (needs translation)
└── chinese.lua      # Chinese template (needs translation)
```

## How to Translate

### 1. Choose a Language

Pick from the templates or create a new language file (e.g., `spanish.lua`, `french.lua`).

### 2. Translate the Strings

Open the template file and replace the English text after each `language.Add()` with your translation:

```lua
-- Before
language.Add("npcpassengers.name", "Better NPC Passengers") -- TODO: Translate

-- After (Russian example)
language.Add("npcpassengers.name", "Лучшие NPC Пассажиры")
```

### 3. Add Language Detection

In `lua/nai_npc_passengers/ui.lua`, add your language to the `LoadLocalization()` function:

```lua
elseif lang == "spanish" or lang == "es" then
    include("resource/localization/spanish.lua")
```

### 4. Test Your Translation

1. Set GMod to your language: Options → Language → [Your Language]
2. Load the addon
3. Open the settings panel
4. Verify strings are translated correctly

## Translation Guidelines

### Be Concise
- UI labels should be short (fits in buttons/headers)
- Help text can be longer but keep it clear

### Context Matters
- "Exit" can mean "leave vehicle" or "close menu" - check context
- Technical terms (HUD, NPC, ConVar) may not need translation

### Consistency
- Use the same terminology throughout
- Follow existing GMod translations where possible

### Character Limits
- Button labels: ~20 characters max
- Section headers: ~30 characters max
- Help text: No strict limit, but keep it reasonable

## Language Codes

GMod uses these language codes:
- `english` / `en`
- `russian` / `ru`
- `schinese` / `tchinese` / `zh` (Simplified/Traditional Chinese)
- `spanish` / `es`
- `french` / `fr`
- `german` / `de`
- `italian` / `it`
- `portuguese` / `pt`
- `polish` / `pl`
- `korean` / `ko`
- `japanese` / `ja`

## Contributing

1. Fork the repository
2. Create your translation file
3. Test it thoroughly
4. Submit a pull request with:
   - The translation file
   - Updated `ui.lua` with language detection
   - Your name/credit in the file header

## Priority Strings

Focus on these first for maximum impact:

1. **Navigation tabs** (General, Auto-Join, etc.)
2. **Section headers** (General Settings, Timing, etc.)
3. **Important buttons** (Enable, Disable, Attach, Detach)
4. **Error messages** (No vehicle, Vehicle full, etc.)
5. **Chat messages** (Auto-Join: ON/OFF, etc.)

Lower priority:
- FAQ text (can stay English for now)
- Help tooltips (nice to have, not critical)
- Debug messages (English is fine)

## Need Help?

- Join our Discord: [Link]
- Open an issue on GitHub
- Check existing translations for reference

## Credits

Translations will be credited in:
- The localization file header
- GitHub contributors list
- Workshop description (for major languages)

Thank you for helping make Better NPC Passengers accessible to more players! 🌍
