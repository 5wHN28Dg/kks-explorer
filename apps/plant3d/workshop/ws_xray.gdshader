// The Workshop's see-through (docs/plant3d/WORKSHOP.md §7.1, `ws_xray`): unshaded, blended, writing no depth. From
// K2 the guided assembly's ghost (the next step's part drawn in place); from K3 the X-ray too, edge-weighted, in
// another colour. A little more opaque where the surface turns away from the eye, so the ghost's outline reads.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 colour : source_color = vec3(0.35, 0.75, 1.0);
uniform float alpha = 0.35;
uniform float edge = 0.45;   // how much the outline adds

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = colour;
	ALPHA = clamp(alpha + edge * (1.0 - facing), 0.0, 1.0) * step(0.001, alpha);
}
