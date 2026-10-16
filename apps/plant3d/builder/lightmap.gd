## Lightmap UV2 for the plant's static meshes (R9: one asset set; the bake: builder/bake/). The content build
## (headless) gives every mesh that never moves a second UV set laid out by Godot's own unwrapper (xatlas), sized by
## a texel in metres, and marks its node static for LightmapGI; the bake itself needs a GPU and runs after the build
## (builder/bake/bake_plugin.gd, build.sh `bake`). Meshes that stand in a cell more than once stay instanced
## (MultiMesh): LightmapGI does not bake MultiMeshes, they are lit by the bake's probes, as are the moving pieces.
extends RefCounted

## Metres per lightmap texel. The bake carries what the sun's real-time shadows don't: the sky's light and its
## occlusion, light bounced off the ground and walls, the halls' lamps, and the sun's shadow beyond the real-time
## distance (decision 0057). A third of a metre resolves the dark under a pipe rack or inside a hall and the shade at
## a foot; the sun's own sharp shadows stay real-time on every tier. 0.25 m made 12.6 M texels; 0.33 m about 7 M,
## 28 MB as RGBE9995.
const TEXEL := 0.33
## The ground: one big slab, lit almost evenly except near what stands on it.
const GROUND_TEXEL := 0.5

## Arrays (one triangle surface) to a mesh with UV2 for the lightmap, LODs again when `lods` (an `identify` piece
## keeps every triangle, PLANT3D.md §10). Null when the unwrapper fails (the caller keeps the mesh without UV2).
static func unwrap(arrays: Array, texel: float, lods: bool) -> Mesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if am.lightmap_unwrap(Transform3D.IDENTITY, texel) != OK:
		return null
	var hint := am.lightmap_size_hint
	var tris := (am.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	if not lods or tris < 64:
		return am
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, am.surface_get_arrays(0))
	im.generate_lods(25.0, 60.0, [])
	im.set_lightmap_size_hint(hint)
	var m := im.get_mesh()
	m.lightmap_size_hint = hint
	return m

## A node whose mesh the bake lights (UV2 present) or, without UV2, one the probes light.
static func mark(gi: GeometryInstance3D, baked: bool) -> void:
	gi.gi_mode = GeometryInstance3D.GI_MODE_STATIC if baked else GeometryInstance3D.GI_MODE_DYNAMIC

## The arrays with every triangle again, facing the other way (normals and tangents turned): a wall seen from both
## sides, each side with its own lightmap texels.
static func with_back_faces(arr: Array) -> Array:
	var out := arr.duplicate()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n0 := v.size()
	var vv := v.duplicate()
	vv.append_array(v)
	out[Mesh.ARRAY_VERTEX] = vv
	if arr[Mesh.ARRAY_NORMAL] != null:
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var n2 := nn.duplicate()
		for x in nn:
			n2.append(-x)
		out[Mesh.ARRAY_NORMAL] = n2
	if arr[Mesh.ARRAY_TANGENT] != null:
		var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		var t2 := t.duplicate()
		for i in range(0, t.size(), 4):
			t2.append_array([-t[i], -t[i + 1], -t[i + 2], t[i + 3]])
		out[Mesh.ARRAY_TANGENT] = t2
	for k in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
		if arr[k] != null:
			var a = arr[k].duplicate()
			a.append_array(arr[k])
			out[k] = a
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var i2 := idx.duplicate()
	for i in range(0, idx.size(), 3):
		i2.append_array([idx[i] + n0, idx[i + 2] + n0, idx[i + 1] + n0])
	out[Mesh.ARRAY_INDEX] = i2
	return out

## The arrays with white vertex colours where they have none: the structures' meshes then share the kit's vertex
## format (colour, tangents, UV, UV2), so the weathered shader needs one pipeline per pass for both, not two (every
## pipeline is compiled on a phone's first start: decision 0057).
static func white(arr: Array) -> Array:
	if arr[Mesh.ARRAY_COLOR] != null:
		return arr
	var out := arr.duplicate()
	var c := PackedColorArray()
	c.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	c.fill(Color(1, 1, 1, 1))
	out[Mesh.ARRAY_COLOR] = c
	return out
