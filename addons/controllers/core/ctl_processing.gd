class_name CtlProcessing
extends RefCounted

## Analog signal processing. Pure static math; settings are plain
## Dictionaries so they persist and edit easily.
##
## Stick settings:
##   mode      &"radial" | &"axial" | &"hybrid"
##   inner     deadzone radius below which the stick reads zero
##   outer     magnitude at which the stick reads full scale
##   axial     (hybrid) per-axis snap zone, as a fraction of magnitude
##   curve     &"linear" | &"power" | &"custom"
##   exponent  for &"power" (>1 = finer control near centre)
##   custom    a Godot Curve resource, sampled on 0..1, for &"custom"
##   invert_x / invert_y
##
## Trigger settings: inner, outer, curve, exponent, custom, press, release
## (press/release are the axis->button hysteresis thresholds).

const STICK_DEFAULTS := {
	"mode": &"radial", "inner": 0.15, "outer": 0.95, "axial": 0.12,
	"curve": &"linear", "exponent": 2.0, "custom": null,
	"invert_x": false, "invert_y": false,
}

const TRIGGER_DEFAULTS := {
	"inner": 0.05, "outer": 0.97, "curve": &"linear", "exponent": 2.0, "custom": null,
	"press": 0.5, "release": 0.35,
}


static func with_defaults(s: Dictionary, defaults: Dictionary) -> Dictionary:
	var out := defaults.duplicate()
	for k in s:
		out[k] = s[k]
	return out


## 0..1 -> 0..1 response curve.
static func curve(t: float, s: Dictionary) -> float:
	t = clampf(t, 0.0, 1.0)
	match StringName(s.get("curve", &"linear")):
		&"power":
			return pow(t, maxf(0.05, float(s.get("exponent", 2.0))))
		&"custom":
			var c: Variant = s.get("custom")
			if c is Curve:
				return clampf((c as Curve).sample_baked(t), 0.0, 1.0)
	return t


## Remap a magnitude through inner/outer deadzones (0 at inner, 1 at outer).
static func deadzone_remap(m: float, inner: float, outer: float) -> float:
	if m <= inner:
		return 0.0
	if outer <= inner:
		return 1.0
	return clampf((m - inner) / (outer - inner), 0.0, 1.0)


## Process a raw stick vector (each component -1..1).
static func stick(raw: Vector2, settings: Dictionary) -> Vector2:
	var s := with_defaults(settings, STICK_DEFAULTS)
	var inner := float(s.inner)
	var outer := float(s.outer)
	var out := Vector2.ZERO
	match StringName(s.mode):
		&"axial":
			out = Vector2(
				signf(raw.x) * curve(deadzone_remap(absf(raw.x), inner, outer), s),
				signf(raw.y) * curve(deadzone_remap(absf(raw.y), inner, outer), s))
		_:
			var m := raw.length()
			if m > inner and m > 0.0:
				out = raw / m * curve(deadzone_remap(m, inner, outer), s)
			if StringName(s.mode) == &"hybrid" and out != Vector2.ZERO:
				# Snap near-cardinal input: a small orthogonal component
				# (relative to the deflection) is zeroed, then the full
				# magnitude moves onto the remaining axis.
				var mag := out.length()
				var snap := float(s.axial)
				var x := out.x if absf(raw.x) >= snap * m else 0.0
				var y := out.y if absf(raw.y) >= snap * m else 0.0
				var v := Vector2(x, y)
				out = v.normalized() * mag if v != Vector2.ZERO else Vector2.ZERO
	if s.invert_x:
		out.x = -out.x
	if s.invert_y:
		out.y = -out.y
	return out.limit_length(1.0)


## Process a raw trigger value (0..1).
static func trigger(raw: float, settings: Dictionary) -> float:
	var s := with_defaults(settings, TRIGGER_DEFAULTS)
	return curve(deadzone_remap(clampf(raw, 0.0, 1.0), float(s.inner), float(s.outer)), s)


## Hysteresis: next pressed state of an analog strength.
static func hysteresis(strength: float, was_pressed: bool, press: float, release: float) -> bool:
	return strength >= (release if was_pressed else press)
