extends Node
## Dumps the city map's ground on a 10 m grid (height + surface kind) for the world generator.
var world
var out := ""
const X0 := -1800.0
const Z0 := -3400.0
const NX := 460
const NZ := 480
func run() -> void:
	await get_tree().create_timer(1.0).timeout
	var sp: PhysicsDirectSpaceState3D = world.space
	var hb := PackedFloat32Array()
	hb.resize(NX * NZ)
	var kb := PackedByteArray()
	kb.resize(NX * NZ)
	for iz in NZ:
		for ix in NX:
			var x := X0 + ix * 10.0
			var z := Z0 + iz * 10.0
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 420, z), Vector3(x, -60, z))
			q.collision_mask = 1
			var h := sp.intersect_ray(q)
			var k := iz * NX + ix
			if h.is_empty() or not h.collider.has_meta("surface"):
				hb[k] = -9999.0
				kb[k] = 0
			else:
				hb[k] = h.position.y
				var s := str(h.collider.get_meta("surface"))
				kb[k] = 1 if s.contains("road") else (3 if s.contains("ocean") or s.contains("water") else 2)
	var f := FileAccess.open(out + ".h", FileAccess.WRITE)
	f.store_buffer(hb.to_byte_array())
	f.close()
	var f2 := FileAccess.open(out + ".k", FileAccess.WRITE)
	f2.store_buffer(kb)
	f2.close()
	var f3 := FileAccess.open(out + ".route", FileAccess.WRITE)
	for p in world.route:
		f3.store_line("%f %f %f" % [p.x, p.y, p.z])
	for k in world.bases:
		f3.store_line("BASE %s %f %f %f" % [k, world.bases[k].pos.x, world.bases[k].pos.y, world.bases[k].pos.z])
	f3.store_line("BANK %f %f %f" % [world.bank.global_position.x, world.bank.global_position.y, world.bank.global_position.z])
	f3.close()
	print("dump done")
	get_tree().quit()
