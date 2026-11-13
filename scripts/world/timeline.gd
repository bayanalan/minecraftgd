class_name Timeline
extends RefCounted
## Java 26.3 timelines (data/minecraft/timeline/*.json, attached to a dimension through its `timelines` tag): keyframed
## environment-attribute tracks over a repeating period of the dimension clock. day.json drives the sky / fog / cloud
## colour multipliers, sky light colour and factor, star brightness, sunrise-sunset colour and the sun / moon / star
## angles; moon.json the moon phase. Keyframes interpolate linearly (colours per ARGB channel) unless the track's ease
## is "constant" (step) or {"cubic_bezier": [x1, y1, x2, y2]}; non-numeric values (strings, booleans) step.
## modify(base, track, ticks) applies the track's modifier: multiply, maximum, minimum, or, and; none = override.

var period := 24000.0
var tracks: Dictionary = {}   # attribute id -> {"mod": String, "ease": Variant, "keys": Array of [ticks, value]}


static func load_id(id: String) -> Timeline:
	var path := "data/minecraft/timeline/%s.json" % id.trim_prefix("minecraft:")
	var j = Res.read_json(path)
	if not (j is Dictionary):
		return null
	var t := Timeline.new()
	t.period = maxf(1.0, float(j.get("period_ticks", 24000.0)))
	var trs = j.get("tracks", {})
	if trs is Dictionary:
		for name in trs:
			var tr = trs[name]
			if not (tr is Dictionary):
				continue
			var keys: Array = []
			for kf in tr.get("keyframes", []):
				if kf is Dictionary and kf.has("ticks"):
					keys.append([float(kf["ticks"]), _parse(kf.get("value"))])
			# stable by ticks: equal ticks keep file order (a jump, e.g. the sun angle 360 -> 0 at noon)
			var idx: Array = range(keys.size())
			idx.sort_custom(func(a, b): return keys[a][0] < keys[b][0] or (keys[a][0] == keys[b][0] and a < b))
			var sorted: Array = []
			for i in idx:
				sorted.append(keys[i])
			t.tracks[str(name)] = {"mod": str(tr.get("modifier", "")), "ease": tr.get("ease", null), "keys": sorted}
	return t


## Timelines of a dimension: its `timelines` field (a tag "#ns:name" or a list of ids).
static func for_dimension(dim_type: Dictionary) -> Array:
	var out: Array = []
	var ref = dim_type.get("timelines", null)
	var ids: Array = []
	if ref is String and str(ref).begins_with("#"):
		var tag = Res.read_json("data/minecraft/tags/timeline/%s.json" % str(ref).substr(1).trim_prefix("minecraft:"))
		if tag is Dictionary:
			for v in tag.get("values", []):
				ids.append(str(v.get("id", "")) if v is Dictionary else str(v))
	elif ref is Array:
		for v in ref:
			ids.append(str(v))
	elif ref is String:
		ids.append(str(ref))
	for id in ids:
		var t := load_id(id)
		if t != null:
			out.append(t)
	return out


static func _parse(v) -> Variant:
	if v is String and str(v).begins_with("#"):
		var h := str(v).substr(1)
		if h.length() == 6:
			return Color8(h.substr(0, 2).hex_to_int(), h.substr(2, 2).hex_to_int(), h.substr(4, 2).hex_to_int(), 255)
		if h.length() == 8:   # ARGB
			return Color8(h.substr(2, 2).hex_to_int(), h.substr(4, 2).hex_to_int(), h.substr(6, 2).hex_to_int(), h.substr(0, 2).hex_to_int())
	if v is int:
		return float(v)
	return v


## CSS-style cubic bezier easing from (0,0) to (1,1): solve x(s) = f, return y(s).
static func _bezier(c: Array, f: float) -> float:
	var x1 := float(c[0])
	var y1 := float(c[1])
	var x2 := float(c[2])
	var y2 := float(c[3])
	var lo := 0.0
	var hi := 1.0
	var s := f
	for i in 24:
		s = (lo + hi) * 0.5
		var x := 3.0 * (1.0 - s) * (1.0 - s) * s * x1 + 3.0 * (1.0 - s) * s * s * x2 + s * s * s
		if x < f:
			lo = s
		else:
			hi = s
	return 3.0 * (1.0 - s) * (1.0 - s) * s * y1 + 3.0 * (1.0 - s) * s * s * y2 + s * s * s


static func _lerp_v(a, b, f: float) -> Variant:
	if a is float and b is float:
		return lerpf(a, b, f)
	if a is Color and b is Color:
		return (a as Color).lerp(b, f)
	return a if f < 1.0 else b


func has(track: String) -> bool:
	return tracks.has(track)


## Track value at `ticks` (clock time), or null without that track.
func sample(track: String, ticks: float) -> Variant:
	var tr = tracks.get(track)
	if tr == null:
		return null
	var keys: Array = tr["keys"]
	var n := keys.size()
	if n == 0:
		return null
	if n == 1:
		return keys[0][1]
	var t := fposmod(ticks, period)
	var i := -1
	for k in n:
		if float(keys[k][0]) <= t:
			i = k
	var a: Array
	var b: Array
	var ta: float
	var tb: float
	if i == -1:
		a = keys[n - 1]
		b = keys[0]
		ta = float(a[0]) - period
		tb = float(b[0])
	elif i == n - 1:
		a = keys[n - 1]
		b = keys[0]
		ta = float(a[0])
		tb = float(b[0]) + period
	else:
		a = keys[i]
		b = keys[i + 1]
		ta = float(a[0])
		tb = float(b[0])
	var f := 0.0 if tb <= ta else clampf((t - ta) / (tb - ta), 0.0, 1.0)
	var ease = tr["ease"]
	if ease is String and ease == "constant":
		f = 0.0
	elif ease is Dictionary and ease.has("cubic_bezier"):
		f = _bezier(ease["cubic_bezier"], f)
	return _lerp_v(a[1], b[1], f)


## Applies this timeline's track to a base value (Java modifier semantics).
func modify(base, track: String, ticks: float) -> Variant:
	var v = sample(track, ticks)
	if v == null:
		return base
	match str(tracks[track]["mod"]):
		"multiply":
			if base is Color and v is Color:
				return Color((base as Color).r * v.r, base.g * v.g, base.b * v.b, base.a * v.a)
			if base is float and v is float:
				return base * v
		"maximum":
			if base is float and v is float:
				return maxf(base, v)
		"minimum":
			if base is float and v is float:
				return minf(base, v)
		"or":
			return bool(base) or bool(v)
		"and":
			return bool(base) and bool(v)
	return v
