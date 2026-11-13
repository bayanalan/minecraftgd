## AtlasBuilder — collects block texture layers into one Texture2DArray (16x16 tiles, mipmapped) and
## animates `.png.mcmeta` textures by re-uploading single layers at 20 Hz (no chunk remesh needed).
## Contract: layer_for(name) -> int (allocates + loads image lazily), tex_class(layer) -> 0 opaque/1 cutout/2 translucent,
## build() -> Texture2DArray, tick(game_ticks) updates animated layers.
## Invariants: layer 0 = "missing" checker; main-thread only.
class_name AtlasBuilder
extends RefCounted

const TILE := 16

var image_source: Callable   # func(tex_name) -> Image or null
var mcmeta_source: Callable  # func(tex_name) -> Dictionary or null
var layers: Dictionary = {}  # name -> layer
var names := PackedStringArray()
var images: Array = []        # first frames
var classes := PackedByteArray()
var anims: Array = []         # {layer, frames:Image list, seq:[frame idx], times:[ticks], interp, total}
var texture: Texture2DArray
## Native-resolution copies of square textures wider than TILE (26.x: straw_bed 64 px with quarter-pixel UVs, shelves /
## dried ghast tentacles / shelf mushrooms 32 px). images keep 16-px versions for CPU users (icons, map colours); the
## GPU array uses the largest size and enlarges 16-px layers by exact pixel copies (mip level 2 of an enlarged layer is
## the original, so 16-px blocks sample identically).
var hires: Dictionary = {}
var layer_px := TILE
var missing: Array = []


func _init(img_src: Callable, meta_src: Callable) -> void:
	image_source = img_src
	mcmeta_source = meta_src
	_add("missing", _checker())


static func _checker() -> Image:
	var im := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var on := ((x >> 3) + (y >> 3)) % 2 == 0
			im.set_pixel(x, y, Color(0.97, 0.0, 0.97) if on else Color(0, 0, 0))
	return im


func _add(name: String, img: Image) -> int:
	var l := names.size()
	names.append(name)
	layers[name] = l
	images.append(img)
	classes.append(_classify(img))
	return l


static func _classify(img: Image) -> int:
	var c := 0
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a8
			if a == 0:
				c = maxi(c, 1)
			elif a < 250:
				return 2
	return c


func layer_for(name: String) -> int:
	if layers.has(name):
		return layers[name]
	var img: Image = image_source.call(name)
	if img == null:
		missing.append(name)
		layers[name] = 0
		return 0
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var frames: Array = []
	var hi: Image = img.duplicate() if w == h and w > TILE else null
	if h > w and h % w == 0:
		for i in h / w:
			frames.append(img.get_region(Rect2i(0, i * w, w, w)))
	else:
		frames.append(img)
	# animated textures keep their frames at native resolution (water_flow / lava_flow are 32 px: Java shows a 16 px
	# window of them per block; downscaled to 16 px, flowing water had half the texel density of everything else)
	var native_px: int = (frames[0] as Image).get_width() if frames.size() > 1 and (frames[0] as Image).get_width() > TILE else TILE
	for i in frames.size():
		var f: Image = frames[i]
		if f.get_width() != native_px:
			f.resize(native_px, native_px, Image.INTERPOLATE_NEAREST)
	var base: Image = frames[0]
	if native_px != TILE:
		base = (frames[0] as Image).duplicate()
		base.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
	var l := _add(name, base)
	if hi != null and frames.size() == 1:
		hires[l] = hi
	elif native_px != TILE:
		hires[l] = frames[0]
	if frames.size() > 1:
		var meta = mcmeta_source.call(name)
		var a: Dictionary = meta.get("animation", {}) if meta is Dictionary and meta.get("animation") is Dictionary else {}
		var ft := int(a.get("frametime", 1))
		var seq: Array = []
		var times: Array = []
		if a.get("frames") is Array:
			for fr in a["frames"]:
				if fr is Dictionary:
					seq.append(int(fr.get("index", 0)))
					times.append(int(fr.get("time", ft)))
				else:
					seq.append(int(fr))
					times.append(ft)
		else:
			for i in frames.size():
				seq.append(i)
				times.append(ft)
		var total := 0
		for t in times:
			total += maxi(1, int(t))
		anims.append({"layer": l, "frames": frames, "seq": seq, "times": times, "interp": bool(a.get("interpolate", false)), "total": total, "last": -1})
	return l


## Connected textures (QoL option): 16 variants of a framed texture (glass) with the 1-px frame removed on the
## connected edges (bit 1 top, 2 right, 4 bottom, 8 left); removed frame pixels take the texture's interior colour (clear
## for glass, the tint for stained glass). Returns the first variant layer (variant = first + mask).
func ctm_variants(base: int) -> int:
	var src: Image = images[base]
	var w := src.get_width()
	var h := src.get_height()
	var counts := {}
	var best := 0
	var best_n := -1
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var k := src.get_pixel(x, y).to_rgba32()
			counts[k] = int(counts.get(k, 0)) + 1
			if int(counts[k]) > best_n:
				best_n = int(counts[k])
				best = k
	var interior := Color.hex(best)
	var first := names.size()
	for mask in 16:
		var im: Image = src.duplicate()
		for y in h:
			for x in w:
				var top := y == 0
				var bottom := y == h - 1
				var left := x == 0
				var right := x == w - 1
				if not (top or bottom or left or right):
					continue
				var keep := (top and (mask & 1) == 0) or (right and (mask & 2) == 0) or (bottom and (mask & 4) == 0) or (left and (mask & 8) == 0)
				if not keep:
					im.set_pixel(x, y, interior)
		_add(names[base] + "#ctm%d" % mask, im)
	return first


## Mip chain like Java's block atlas: textures drawn with the plain cutout render type (plants, flowers, crops, rails
## ...) sample only their base level in Java, so their mips are nearest-sampled copies (no black-fringe darkening at a
## distance); cutout_mipped ones (leaves, grass block overlay, bars, panes) and translucent ones get their transparent
## texels' colour from their neighbours first (Java MipmapGenerator never averages a transparent texel's colour in).
func _mipped(img: Image, layer: int) -> Image:
	var cls := tex_class(layer)
	var nm := names[layer] if layer < names.size() else ""
	if cls == 1 and not (nm.contains("_leaves") or nm.contains("grass_block") or nm.contains("iron_bars") or nm.contains("pane")):
		var data := img.get_data()
		var w := img.get_width()
		var h := img.get_height()
		var lvl := img.duplicate()
		while w > 1 or h > 1:
			w = maxi(1, w >> 1)
			h = maxi(1, h >> 1)
			lvl.resize(w, h, Image.INTERPOLATE_NEAREST)
			data.append_array(lvl.get_data())
		return Image.create_from_data(img.get_width(), img.get_height(), true, img.get_format(), data)
	if cls != 0:
		img.fix_alpha_edges()
	img.generate_mipmaps()
	return img


func tex_class(layer: int) -> int:
	return classes[layer] if layer < classes.size() else 0


func build() -> Texture2DArray:
	layer_px = TILE
	for k in hires:
		layer_px = maxi(layer_px, (hires[k] as Image).get_width())
	layer_px = mini(layer_px, 64)
	var imgs: Array[Image] = []
	for i in images.size():
		var c: Image = ((hires[i] if hires.has(i) else images[i]) as Image).duplicate()
		if c.get_width() != layer_px:
			c.resize(layer_px, layer_px, Image.INTERPOLATE_NEAREST)
		imgs.append(_mipped(c, i))
	texture = Texture2DArray.new()
	texture.create_from_images(imgs)
	return texture


## Advance animations; game_ticks is the absolute 20 Hz tick counter.
func tick(game_ticks: int) -> void:
	if texture == null:
		return
	for a in anims:
		var t: int = game_ticks % int(a["total"])
		var acc := 0
		var idx := 0
		var seq: Array = a["seq"]
		var times: Array = a["times"]
		for i in seq.size():
			var d := maxi(1, int(times[i]))
			if t < acc + d:
				idx = i
				break
			acc += d
		var key := idx
		var frac := 0.0
		if a["interp"]:
			frac = float(t - acc) / float(maxi(1, int(times[idx])))
			key = idx * 64 + int(frac * 16.0)
		if key == int(a["last"]):
			continue
		a["last"] = key
		# blended + mipmapped frame images are cached per key (same frac for a key: t is an integer tick)
		var cache: Dictionary = a.get("cache", {})
		var up: Image = cache.get(key)
		if up == null:
			var frames: Array = a["frames"]
			var cur: Image = frames[clampi(int(seq[idx]), 0, frames.size() - 1)]
			var out: Image = cur
			if a["interp"]:
				var nxt: Image = frames[clampi(int(seq[(idx + 1) % seq.size()]), 0, frames.size() - 1)]
				out = cur.duplicate()
				for y in cur.get_height():
					for x in cur.get_width():
						out.set_pixel(x, y, cur.get_pixel(x, y).lerp(nxt.get_pixel(x, y), frac))
			up = out.duplicate()
			if up.get_width() != layer_px:
				up.resize(layer_px, layer_px, Image.INTERPOLATE_NEAREST)
			up = _mipped(up, int(a["layer"]))
			cache[key] = up
			a["cache"] = cache
		texture.update_layer(up, int(a["layer"]))
