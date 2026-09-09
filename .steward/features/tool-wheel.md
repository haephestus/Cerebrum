# Feature: Tool Wheel

> Concepts-inspired concentric tool wheel for drawing controls.

> Phase: core feature
> Status: done
> Created: 2026-08-21

## Status
DONE — Phase 1 (shipped across multiple changelogs)

## Goals
- [x] Evolve ToolDialHub from fixed ring to concentric wheel with colour + tool control
- [x] User can draw in any colour with clear tool/colour readout
- [x] Movable and resizable

## Scope
- **In:** Fixed hub (centre disc, tool chips), constant-size colour wheel (rotatable), size ring, Copic-style 12x5 hue wheel, custom colour picker, resize via pinch/scroll, _DiscHitRegion for pointer passthrough
- **Out:** Customisable tool slots (Phase 4), brush/colour library (Phase 4), collapse/dock (Phase 5)

## Dependencies
- `radial_tool_dial.dart` — main implementation
- `editor_settings_store.dart` — persistence (settings.json, palette.json)
- `onSelectTool` broadcast — tool/colour follows across pages

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | Concentric restructure + colour + resize (DONE) |
| Phase 1 | Size ring + per-tool brush size (DONE) |
| Phase 1 | Copic wheel + hex labels + custom colours (DONE) |
| Phase 1 | Fixed hub + big rotating wheel v2 (DONE) |
| Phase 4 | Customisable slots + library |
| Phase 5 | Collapse/dock, spring animation, haptics |

## Notes
- Colour model: one pen + wheel (replaces 4 fixed-colour pens)
- Highlighter reuses picked colour with alpha; eraser is colourless
- Desktop resize: mouse-wheel scroll (no pinch on mouse)
- `onSelectTool` broadcasts to every page's ink notifier (PagedNoteController)
