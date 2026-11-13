extends SceneTree

func _init() -> void:
	print("NT exists ", ClassDB.class_exists("RecraftNative"))
	var n = ClassDB.instantiate("RecraftNative")
	print("NT version ", n.version())
	var r = n.selftest(PackedInt32Array([1, 2, 3, 40]), 5, 9)
	print("NT selftest ", r)
	quit()