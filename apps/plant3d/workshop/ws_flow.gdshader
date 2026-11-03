// The Workshop's flow particles (docs/plant3d/WORKSHOP.md §7.1, `ws_flow`): one MultiMesh of small quads per flow path,
// each quad placed along the path in the vertex shader. The path is its points (at most 8, the Workshop's world) and
// their running lengths; `phase` (metres along the path, advanced by the app from the bench model's flow: negative
// flow runs it backwards, so the particles go the way the fluid goes); `density` how many of the quads show (0-1);
// `colour` the legend's colour of the value it reads; `strength` how bright.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 pts[8];
uniform float cum[8];           // the running length at each point (cum[0] = 0)
uniform int npts = 2;
uniform float phase = 0.0;
uniform float density = 1.0;
uniform float count = 32.0;     // the MultiMesh's instances
uniform float size = 0.004;     // a quad's half size, metres
uniform vec3 colour : source_color = vec3(0.4, 0.7, 1.0);
uniform float strength = 1.0;

varying float vis;

void vertex() {
	float total = cum[max(npts - 1, 1)];
	float k = float(INSTANCE_ID);
	vis = step(k + 0.5, count * density);
	float s = mod(k / count * total + phase, max(total, 1e-6));
	vec3 at = pts[0];
	for (int i = 1; i < 8; i++) {
		if (i < npts && s >= cum[i - 1] && s <= cum[i]) {
			float f = (s - cum[i - 1]) / max(cum[i] - cum[i - 1], 1e-6);
			at = mix(pts[i - 1], pts[i], f);
		}
	}
	vec3 c = (VIEW_MATRIX * MODEL_MATRIX * vec4(at, 1.0)).xyz;
	VERTEX = c + vec3(VERTEX.xy * size * 2.0 * vis, 0.0);
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float a = (1.0 - smoothstep(0.4, 1.0, length(d))) * vis * strength;
	ALBEDO = colour * a;
	ALPHA = a;
}
