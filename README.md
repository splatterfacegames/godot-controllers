# godot-controllers

Input management and normalization for Godot 4.7+, for local
multiplayer games played with Xbox, PlayStation, Nintendo and generic
pads, and with keyboard and mouse.

* **One canonical pad layout.** Face buttons by position, triggers as
  0..1 axes, sticks as 2D values. Device families are detected from the
  USB vendor id and the name, and Nintendo's swapped A/B is handled with
  a per-game "confirm follows position or label" setting.
* **Players and devices.** N players, with auto-assign or press-to-join.
  Keyboard and mouse is a device of its own. After a hotplug, a pad that
  reconnects goes back to its player.
* **Actions in map categories.** Button, axis and 2D actions grouped in
  categories (gameplay, menu, ...) that each player switches on and off.
  Defaults are per device family. Runtime rebinding handles conflicts
  (swap, replace, reject or allow), and bindings are saved per player
  and per family.
* **Signal processing.** Radial, axial and hybrid stick deadzones (inner
  and outer), response curves, trigger thresholds with hysteresis,
  digital-to-axis and axis-to-button conversion.
* **Frame-accurate queries.** Press, release, hold, double-tap, repeat
  and long-press. Taps shorter than one tick are latched. Input can tick
  in `_physics_process`, `_process`, or a manual tick for games that
  simulate at their original rate.
* **Live glyphs.** Prompts follow each player's last used device, using
  Kenney's Input Prompts (CC0) with procedural fallbacks.
* **Rumble per player.** Gyro, accelerometer and light-bar support where
  Godot exposes them.
* **Virtual devices and a recorder.** Labelled virtual devices and a
  recorder let automated tests and demo drivers inject input through the
  same pipeline.

See [docs/DESIGN.md](docs/DESIGN.md) for the model and the full API
surface.

## Install

Copy `addons/controllers` into your project and enable **Controllers** in
Project Settings → Plugins. That registers the `Controllers` autoload.
You can also add `addons/controllers/core/ctl_input.gd` as a node
yourself.

## Quick start

```gdscript
func _ready() -> void:
	Controllers.declare_action(&"jump", CtlAction.Type.BUTTON, &"gameplay", "Jump", {
		"kbm": [{"key": KEY_SPACE}],
		"gamepad": [{"pad": &"face_south"}],
	})
	Controllers.declare_action(&"move", CtlAction.Type.AXIS_2D, &"gameplay", "Move", {
		"kbm": [{"key": KEY_A, "to": "x-"}, {"key": KEY_D, "to": "x+"},
		        {"key": KEY_W, "to": "y-"}, {"key": KEY_S, "to": "y+"}],
		"gamepad": [{"pad": &"stick_l"}, {"pad": &"dpad"}],
	})
	Controllers.declare_action(&"accept", CtlAction.Type.BUTTON, &"menu", "Confirm", {
		"kbm": [{"key": KEY_ENTER}],
		"gamepad": [{"pad": &"confirm"}],   # south, or "A" on Nintendo with confirm_follows = &"label"
	})

func _physics_process(delta: float) -> void:
	var p := Controllers.player(0)
	velocity = p.get_vector(&"move") * 200.0
	if p.is_just_pressed(&"jump"):
		jump()
	if p.is_just_pressed(&"jump") and p.is_double_tapped(&"jump"):
		double_jump()
```

Show a prompt that follows the player's device:

```gdscript
var prompt := CtlPrompt.new()
prompt.action = &"jump"
prompt.caption = "Jump"
add_child(prompt)
```

Rebind:

```gdscript
Controllers.begin_rebind(0, &"jump")          # captures the next input on player 0's current device kind
Controllers.rebind_finished.connect(func(player, action, binding, family): ...)
```

Drive it from a test or a recorded journey:

```gdscript
var bot := Controllers.add_virtual_device(&"playstation", "journey driver")
Controllers.assign_device(0, bot)
bot.tap(&"face_south")
bot.set_stick(&"stick_l", Vector2(1, 0))
```

## Demo

Run the project (`demo/demo.tscn`). It shows:

* Press-to-join for up to 4 players.
* Each player's devices and live family.
* Glyph prompts that switch when a player picks up another device.
* Stick deadzone visualisers: the grey dot is the raw input and the
  yellow dot is what the game reads.
* Inner and outer deadzone, mode and curve controls.
* Rebinding and rumble.
* A scripted, labelled bot player.

## Tested hardware

| Device | Status |
| --- | --- |
| Keyboard & mouse (Windows 11) | Assignment and glyphs shown in the demo. Live key/mouse presses not yet exercised by a person |
| Virtual devices (all families) | Exercised by a headless smoke run (edges, latching, thresholds, deadzones, rebinding/swap, Nintendo confirm modes, hotplug reservations, record/replay) |
| Xbox controller | **Not yet tested on hardware.** No pad was connected while this release was made |
| DualSense / PlayStation | **Untested.** Detection and labels follow from the Sony vendor id and SDL's positional mapping |
| Switch 2 Pro Controller / Joy-Con 2 | **Untested.** In particular: whether the platform reports Nintendo face buttons by position (assumed, per SDL3), how a single sideways Joy-Con maps, and which `misc_*`/`paddle_*` the extra buttons (C, GL/GR) arrive on |
| Gyro, light bar | Wired to Godot 4.7's APIs, **untested on hardware** |

Please open an issue with `Input.get_joy_name/guid/info` output if your
pad is detected wrongly.

## Art and licence

Code: MIT (see `LICENSE`).

Glyph textures: **Kenney "Input Prompts" 1.5a** by Kenney (www.kenney.nl),
CC0. The 128 px PNGs for Xbox Series, PlayStation, Nintendo Switch 2,
generic and keyboard & mouse live in `addons/controllers/glyphs/kenney/`,
with Kenney's `License.txt`. `CtlGlyphTheme` maps controls to those files.
Anything the pack doesn't cover (for example the PlayStation home button,
or face buttons on generic pads) falls back to the procedural `CtlGlyph`
drawing. Set `Controllers.glyph_theme = ""` to draw everything
procedurally, or point it at your own folder that uses the same file names.
