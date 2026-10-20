## Lightmap UV2 for the plant's static meshes (R9: one asset set; the bake: builder/bake/). The content build
## (headless) gives every mesh that never moves a second UV set laid out by Godot's own unwrapper (xatlas), sized by
## a texel in metres, and marks its node static for LightmapGI; the bake itself needs a GPU and runs after the build
## (builder/bake/bake_plugin.gd, build.sh `bake`). Meshes that stand in a cell more than once stay instanced
## (MultiMesh): LightmapGI does not bake MultiMeshes; they and the moving pieces take
## the environment's sky light (see mark).
extends RefCounted

## Metres per lightmap texel. The bake carries what the sun's real-time shadows don't: the sky's light and its
## occlusion, light bounced off the ground and walls, the halls' lamps, and the sun's shadow beyond the real-time
## distance (decision 0057). A third of a metre resolves the dark under a pipe rack or inside a hall and the shade at
## a foot; the sun's own sharp shadows stay real-time on every tier. 0.25 m made 12.6 M texels; 0.33 m about 7 M,
## 28 MB as RGBE9995.
const TEXEL := 0.33
## The ground: one big slab, lit almost evenly except near what stands on it.
const GROUND_TEXEL := 0.5
## Thin sheets (the fences, the gate: 5 to 8 cm): at the usual texel a texel spans both faces and the sheet baked as
## dark and brown blotches; this fine they bake clean (second realism pass). Left out of the bake instead, they cost
## the phone a pipeline of their own at the first frame (an unbaked static mesh).
const SHEET_TEXEL := 0.08

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

## A node whose mesh the bake lights (UV2 present) or, without UV2, one lit by the sky's ambient light. Not by the
## bake's probes: Godot gives a MultiMesh one probe sample for its whole 12 m cell, and in shade or inside a hall that
## sample left a blue motor, a red handwheel or an actuator almost black (2026-10-16 captures); their colours tell a
## trainee what they are (R9a).
static func mark(gi: GeometryInstance3D, baked: bool) -> void:
	gi.gi_mode = GeometryInstance3D.GI_MODE_STATIC if baked else GeometryInstance3D.GI_MODE_DISABLED

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
