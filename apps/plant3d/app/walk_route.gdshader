// The walking directions' chevrons (app/walk_route.gd): unshaded orange, a little see-through. Each vertex carries
// its metres along the way in UV.x; those outside the window [from, to] collapse to a point, so walking on moves the
// window instead of rebuilding the mesh.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float from = 0.0;
uniform float to = 1e9;
uniform float alpha = 0.85;

void vertex() {
	if (UV.x < from || UV.x > to) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = vec3(1.0, 0.318, 0.01);   // the arrows' orange (1, 0.6, 0.1) in linear light
	ALPHA = alpha;
}
