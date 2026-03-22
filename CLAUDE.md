# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Aseprite Palette Manager — a set of Lua scripts for Aseprite that support a **value-first pixel art workflow** (draw in near-gray, then colorize). Designed for **Indexed Color Mode** where palette edits update all pixels instantly.

## Scripts

- **PaletteManager.lua** — Main dialog for palette generation: pick up to 8 target hues, generate organized ramps with markers, import hues from existing palettes.
- **PM_Toolbar.lua** — Compact floating panel with saturation slider and Colorize/Desaturate buttons.
- **PM_Toggle.lua** — No-UI hotkey script that detects palette state via average ramp saturation and toggles between gray (S=5%) and color (S=70%).

## Architecture

All three scripts share the same palette layout convention:
- **Index 0**: transparent (mask), **Index 1**: black (outlines), **Indices 2–N**: gray ramp (V from `currentValues`, S=0%)
- Starting at index `2 + #currentValues`, colors are organized in groups: 1 vivid marker (S=100%) + N value steps
- Value steps are configurable via UI (bright/dark/steps sliders + presets: Full, Dark, Pastel, Custom). Computed by `computeValues(bright, dark, steps)`. Default: Full preset = `{100, 88, 75, 62, 50, 37, 25, 12}`
- PM_Toggle and PM_Toolbar are **fully marker-driven**: they scan from index 0, track the current marker hue, and only modify colors that follow a marker. Gray ramp and fixed colors are never touched because they appear before the first marker.

Key shared constants:
- `WORK_SATURATION` (5) — near-gray saturation for drawing
- `MARKER_SATURATION` (100) — exact saturation of marker colors (same across all scripts)
- `currentValues` (PaletteManager only) — computed value steps array, replaces old `DEFAULT_VALUES` constant
- `fixedColors` and `rampSize` are computed on the fly from `#currentValues` (no longer constants)
- PM_Toggle and PM_Toolbar no longer use `FIXED_COLORS` — they rely on marker detection instead

## Development

No build system or tests — these are standalone Lua scripts run directly by Aseprite's scripting engine. To test, copy `.lua` files to Aseprite's scripts folder (`File > Scripts > Open Scripts Folder`) and run from `File > Scripts`.

Scripts use the [Aseprite Lua API](https://www.aseprite.org/api/) — `app`, `Dialog`, `Color`, `Sprite`, `Palette` are provided by Aseprite's runtime.
