extends SceneTree

const OUT := "res://scenes/Map1_City.tscn"

const WALKABLE := ["Ground", "Stroke", "Bridge", "Lapangan", "Character", "Motorcycle"]

var _used_cache: Dictionary = {}


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/Map1_City.tscn")
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame

	var added := _bake_nodes(root, root)

	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		print("FAIL pack: ", err)
		quit(1)
		return
	err = ResourceSaver.save(out, OUT)
	print("saved(%d) added=%d" % [err, added])
	root.queue_free()
	quit()


func _bake_nodes(scene_root: Node, node: Node) -> int:
	var added := 0
	for child in node.get_children():
		if child is Sprite2D:
			if _bake_one(scene_root, child):
				added += 1
		if child is Node2D:
			added += _bake_nodes(scene_root, child)
	return added


func _bake_one(scene_root: Node, sprite: Sprite2D) -> bool:
	for kw in WALKABLE:
		if sprite.name.contains(kw):
			return false
	if sprite.get_node_or_null(sprite.name + "_Collision"):
		return false
	var tex: Texture2D = sprite.texture
	if tex == null:
		return false
	var used := _used_rect(tex)
	var tex_size := tex.get_size()
	if used.size.x <= 0.0 or used.size.y <= 0.0:
		return false

	var body := StaticBody2D.new()
	body.name = sprite.name + "_Collision"

	var cs := CollisionShape2D.new()
	var shape: Shape2D
	var offset: Vector2

	if "Tree" in sprite.name or "Stump" in sprite.name:
		var w := used.size.x * 0.5
		var h := used.size.y * 0.35
		var rect := RectangleShape2D.new()
		rect.size = Vector2(w, h)
		shape = rect
		offset = Vector2(used.get_center().x - tex_size.x * 0.5, used.end.y - tex_size.y * 0.5 - h * 0.5)
	elif "Rock" in sprite.name:
		var r := minf(used.size.x, used.size.y) * 0.5 * 0.92
		var circle := CircleShape2D.new()
		circle.radius = r
		shape = circle
		offset = used.get_center() - tex_size * 0.5
	else:
		var inset := 0.12
		var w := used.size.x * (1.0 - inset)
		var h := used.size.y * (1.0 - inset)
		if "Fence" in sprite.name:
			w = used.size.x
			h = used.size.y * 0.9
		var rect := RectangleShape2D.new()
		rect.size = Vector2(w, h)
		shape = rect
		offset = used.get_center() - tex_size * 0.5

	cs.shape = shape
	cs.position = offset
	body.add_child(cs)
	sprite.add_child(body)
	body.owner = scene_root
	cs.owner = scene_root
	return true


func _used_rect(tex: Texture2D) -> Rect2:
	if _used_cache.has(tex):
		return _used_cache[tex]
	var img := tex.get_image()
	var rect := Rect2(0, 0, tex.get_width(), tex.get_height())
	if img:
		var used := img.get_used_rect()
		if used.size.x > 0.0 and used.size.y > 0.0:
			rect = used
	_used_cache[tex] = rect
	return rect