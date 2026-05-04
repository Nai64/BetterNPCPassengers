# v2.7.7

### Changes
- Re-enabled slider drag transparency feature
- Removed idle fade feature entirely (was causing hover detection issues)
- Panel now becomes 70% transparent ONLY when dragging a slider knob
- Removed idle fade UI controls and ConVars
- Simplified Think function with no hover detection logic

### Technical Details
- The idle fade feature (panel becoming transparent when mouse not over it) was causing issues
- Slider drag transparency (panel becoming 70% transparent when dragging sliders) still works
- No hover detection or bounds checking needed anymore - just checks if slider knob is being dragged
