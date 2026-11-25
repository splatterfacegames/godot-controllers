# godot-controllers: design

An input management and normalization layer for Godot 4.7, designed from
first principles on Godot's own APIs: `Input`, `InputEventJoypad*`, joy
GUID/name/info and the engine's SDL-backed gamepad mapping. No other input
library's code, data or controller tables were used.

## Layers

```
OS / SDL ──► Godot Input ──► CtlDevice ──► per-player processing ──► actions ──► queries
               │ events        (raw canonical     (deadzones, curves,     (button/axis/2D,
               └─► latches      state, per tick)    thresholds)             edges, holds)
```

### Devices

`core/ctl_device.gd` builds a snapshot of raw canonical state once per tick.

* `CtlJoypadDevice` represents one Godot joy id. It polls
  `Input.is_joy_button_pressed`/`get_joy_axis` and latches button presses
  from events.
* `CtlKbmDevice` is the shared keyboard + mouse (id -1). Its state is
  built from events, using physical keycodes. Mouse motion and wheel
  accumulate between ticks.
* `CtlVirtualDevice` is scripted or recorded input (ids from 1000). It
  emulates any family and is always labelled.

Each poll also produces `rising`, the sources newly pressed this tick, as
binding dictionaries. It drives activity tracking ("last used device"),
press-to-join and rebind capture.

### Canonical layout (`core/ctl_layout.gd`)

Godot 4.5+ (SDL3) reports gamepad buttons by **position**, so the
canonical layout is positional:

| Control | Notes |
| --- | --- |
| `face_south` `face_east` `face_west` `face_north` | by position, never by label |
| `shoulder_l` `shoulder_r` | |
| `trigger_l` `trigger_r` | analog 0..1 |
| `stick_l` `stick_r` | 2D; components `stick_l_x` etc. (Y down positive, Godot's convention) |
| `stick_l_press` `stick_r_press` | |
| `dpad_up/down/left/right`, `dpad` | `dpad` is a 2D pseudo-control |
| `start` `select` `home` | |
| `misc` | Share / Mic / Capture, depending on the pad |
| `touchpad` | click |
| `paddle_1..4`, `misc_2..6` | when the platform reports them |
| `confirm` `cancel` | pseudo-controls resolved per family |

### Families

`xbox`, `playstation`, `nintendo`, `generic` and `kbm`. Detection order:

1. USB vendor id from `get_joy_info()` (`vendor_id`), or decoded from the
   SDL GUID. Bytes 4-5 are the vendor and 8-9 the product, little-endian,
   with bytes 6-7 and 10-11 zero. Microsoft 0x045E, Sony 0x054C,
   Nintendo 0x057E.
2. Conservative name matching.
3. Otherwise `generic`. A generic XInput identity is never assumed to be
   an Xbox pad.

`Controllers.set_family_override(device, family)` covers anything
mis-detected.

### Confirm and cancel (Nintendo A/B)

Nintendo pads put **B** at the south position and **A** at the east.
Bind menu actions to `confirm` / `cancel` and choose per game:

* `confirm_follows = &"position"` (default). Confirm is the south button
  on every pad: "A" on Xbox, "Cross" on PlayStation, "B" on Nintendo.
  Glyphs show whatever is printed on the button.
* `confirm_follows = &"label"`. Confirm is the button labelled **A**,
  which is east on Nintendo and south elsewhere.

## Players, devices, joining

* `CtlPlayer` holds devices, enabled categories, binding overrides per
  family, stick and trigger settings, `rumble_scale` and per-action state.
* `join_mode`:
  * `AUTO`: each new pad fills the lowest player without a pad, and
    keyboard+mouse goes to `kbm_player`.
  * `PRESS`: an unassigned device pressing one of the `join_bindings`
    while `join_open` claims the lowest free player. The join press is
    suppressed so it doesn't also act.
  * `MANUAL`: the game calls `assign_device` itself.
* Hotplug: a disconnected pad leaves a **reservation** on its player
  (GUID + name + serial when reported). The next matching device to
  connect is given back to that player (`device_reconnected`), even
  under a new joy id. Exact signature matches win over GUID+name
  matches. Its held inputs release on the next tick.

## Actions, maps, bindings

```gdscript
Controllers.declare_action(&"move", CtlAction.Type.AXIS_2D, &"gameplay", "Move", {
	"kbm": [{"key": KEY_A, "to": "x-"}, {"key": KEY_D, "to": "x+"},
	        {"key": KEY_W, "to": "y-"}, {"key": KEY_S, "to": "y+"}],
	"gamepad": [{"pad": &"stick_l"}, {"pad": &"dpad"}],
})
```

* Types are `BUTTON`, `AXIS` (-1..1) and `AXIS_2D`.
* Categories are switched per player with `set_category_enabled`.
  Enabling a category suppresses its actions that are currently held
  until they are released, so the confirm press that closed a menu
  doesn't also jump.
* Binding dictionaries:

  | Binding | Meaning |
  | --- | --- |
  | `{"pad": c}` | canonical control |
  | `{"key": physical_keycode}` | keyboard key |
  | `{"mouse": button}` | mouse button |
  | `{"mouse_axis": &"x"/&"y"/&"wheel"}` | mouse movement or wheel |

  Modifiers:

  | Modifier | Effect |
  | --- | --- |
  | `"to"` | target component |
  | `"half": ±1` | read one half of an axis (axis to button) |
  | `"invert"` | flip the value |
  | `"scale"` | multiply the value |
* Defaults are keyed by `kbm`, `gamepad` (all pads), and optionally
  `xbox` / `playstation` / `nintendo` / `generic`, which override
  `gamepad` for that family.
* Rebinding: `begin_rebind(player, action, slot, {kind, to, policy, timeout})`.
  * It waits until the player's devices are all neutral, so the press
    that opened the prompt is never captured.
  * It then captures the next rising source and shapes it to the
    action: a stick moved for an AXIS_2D action binds the whole stick,
    and a d-pad direction binds `dpad`.
  * Esc cancels.
  * Conflicts are checked within the same player and family, across
    categories that can be active together (a category always conflicts
    with itself; widen this with `add_conflict_group`). Policies:
    * `swap` (default): the other action takes the old binding.
    * `replace`: the binding is removed from the other action.
    * `reject`: emits `rebind_conflict` and changes nothing.
    * `allow`: both actions keep the binding.
* Persistence uses a ConfigFile at `storage_path`. Each player's
  `profile_key` keys their overrides (per family), stick and trigger
  settings and rumble scale.

## Signal processing (per player)

* **Sticks.** Processed as a 2D pair before any component is read.
  * `mode` is `radial`, `axial`, or `hybrid` (radial plus a snap zone
    that makes cardinal directions easy).
  * `inner` and `outer` deadzones are rescaled so output starts at 0 at
    `inner` and reaches 1 at `outer`.
  * `curve` is `linear`, `power` (with `exponent`) or `custom` (a
    `Curve`). `invert_x` and `invert_y` are also available.
* **Triggers.** `inner`/`outer`, curve, and the `press`/`release`
  hysteresis used whenever a trigger drives a BUTTON action.
* **Digital to axis.** Each key or button adds ±1 to its component.
  Digital-only 2D input is normalised, so diagonals have length 1.
  Mouse axes are scaled by `mouse_scale`. Set `clamp_output = false` for
  mouse-look actions.
* **Axis to button.** Per-action `press_threshold` and
  `release_threshold` hysteresis.

## Ticks and edges

* `tick_mode` is one of:
  * `PHYSICS` (default): runs at physics priority -1000, so game nodes
    see fresh state in their own `_physics_process`.
  * `PROCESS`
  * `MANUAL`: call `Controllers.tick(dt)` at the top of your own
    fixed-rate step, for example a 50 Hz original tick inside a 60 Hz
    loop.
* Presses are **latched** between ticks. A tap shorter than one tick
  yields exactly one `is_just_pressed` tick and one `is_just_released`
  tick. A release followed by a re-press inside the same tick is seen
  as a continuous hold (documented limit).
* Queries:
  * `is_pressed`, `is_just_pressed`, `is_just_released`
  * `get_value`, `get_vector`
  * `held_time`, `held_ticks`
  * `is_double_tapped` (true on the second press within
    `double_tap_window`)
  * `is_repeated` (menu auto-repeat: `repeat_delay`, then every
    `repeat_interval`)
  * `is_long_pressed` (once, at `long_press`)
  * `action_device`

## Glyphs

* `Controllers.glyphs(player, action)` returns descriptors
  (`{text, icon, style, icon_only, icon_text, family, control}`) for the
  player's last used device family.
* `glyphs_changed(player_index)` fires when that family changes, when
  bindings change and when `confirm_follows` changes.
* Each descriptor also carries `texture` (a res:// path) when the glyph
  theme has an image for it. The default theme is Kenney's Input Prompts
  (CC0, bundled under `glyphs/kenney/`, 128 px), selected with
  `Controllers.glyph_theme`.
* `CtlGlyph` draws the texture, or falls back to its procedural icon
  (`""` disables textures). `CtlPrompt` is a self-updating widget.

## Output

* `player.rumble(weak, strong, seconds)` calls `Input.start_joy_vibration`
  on each of the player's pads, scaled by `rumble_scale`.
* Virtual devices log rumble to `rumble_log`.
* All rumble stops on focus loss.

## Extended features (`core/ctl_features.gd`)

* Real, on Godot 4.7 APIs:
  * motion sensors: `set_motion_enabled`, `gyroscope`, `accelerometer`,
    `gravity`, calibration
  * the light bar: `set_light`
  * `supports(device, feature)` asks the engine.
* Not supported (no Godot API, never faked): DualSense adaptive triggers,
  Nintendo HD rumble, Xbox impulse-trigger motors and audio haptics.
  `supports()` returns false and the setters return `ERR_UNAVAILABLE`.

## Testability

* `Controllers.add_virtual_device(family, label)` adds a virtual device.
  Assign it like a pad; it supports `press`/`release`/`tap`, `set_axis`,
  `set_stick`, `key_down`/`key_tap`, `mouse_move` and `play(frames)`.
  Every injection is appended to `injection_log` with its tick and label.
* `Controllers.automation_labels()` lists the labels of virtual devices
  that are currently assigned. Show them in capture overlays.
* `CtlRecorder` records any device's state changes per tick and replays
  them into a virtual device. It saves and loads JSON
  (`godot-controllers.recording/1`).
* `simulate_joy_connection(id, connected)` exercises hotplug paths
  without hardware.
