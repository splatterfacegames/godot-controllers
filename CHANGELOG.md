# Changelog

## 0.2.1 — 2026-11-27

- Synthetic events: `CtlInput.SYNTHETIC_DEVICE` (-78), `mark_synthetic()`,
  `is_ignored_event()` and `ignored_event_devices`. Tagged keyboard and
  mouse events (e.g. a pad-driven virtual cursor) are not keyboard/mouse
  activity. Upstreamed from Wages of War.
- Web: family detection reads USB ids from browser gamepad names. The
  Web build skips physical-key layout mapping. A web demo site was added.

## 0.2.0 — 2026-11-25

Glyph textures: bundles Kenney's Input Prompts 1.5a (CC0) for Xbox,
PlayStation, Nintendo (Switch 2), generic sticks and keyboard & mouse.
New `CtlGlyphTheme` and `Controllers.glyph_theme`. Glyph descriptors
gain `texture`, and `CtlGlyph` draws it, falling back to the procedural
icon.

## 0.1.0 — 2026-11-25

First release: canonical layout and family detection, joypad, keyboard+mouse
and virtual devices, players with auto, press-to-join and manual joining,
hotplug reservations, actions with map categories, per-family defaults,
rebinding with conflict policies, persistence, stick and trigger processing,
latched frame-accurate edges with physics, process and manual ticks, glyph
descriptors, CtlGlyph and CtlPrompt, per-player rumble, motion-sensor and
light hooks, honest stubs for unsupported haptics, a recorder, and the demo.
