## Lightmap UV2 for the plant's static meshes (R9: one asset set; the bake: builder/bake/). The content build
## (headless) gives every mesh that never moves a second UV set laid out by Godot's own unwrapper (xatlas), sized by
## a texel in metres, and marks its node static for LightmapGI; the bake itself needs a GPU and runs after the build
## (builder/bake/bake_plugin.gd, build.sh `bake`). Meshes that stand in a cell more than once stay instanced
## (MultiMesh): LightmapGI does not bake MultiMeshes, they are lit by the bake's probes, as are the moving pieces.
extends RefCounted

## Metres per lightmap texel. The bake carries what the sun's real-time shadows don't: the sky's light and its
## occlusion, and light bounced off the ground and walls (decision 0054 §R9 lighting). A quarter metre resolves the
## dark under a pipe rack or inside a hall and the contact shade at a foot; the sun's own sharp shadows stay
## real-time on every tier.
const TEXEL := 0.25
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
