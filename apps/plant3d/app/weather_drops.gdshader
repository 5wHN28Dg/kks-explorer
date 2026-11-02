// How the weather's particles are drawn (app/weather_particles.gdshader): a thin streak along the fall for rain, a
// small speck for sand, each facing the camera, faded near the camera and towards the box's edge. Unshaded, no
// shadows, no depth writes (decision 0060: one pipeline per pass; counted on the phone).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

uniform vec3 velocity = vec3(0.0, -8.0, 0.0);   // the particles' motion (the process shader's)
uniform float length_s = 0.04;                  // a streak's length: this many seconds of the motion (rain)
uniform float width = 0.01;                     // metres
uniform float min_length = 0.0;                 // metres: a speck's own size (sand)
uniform vec4 colour : source_color = vec4(0.75, 0.78, 0.82, 0.3);
uniform float far = 25.0;                       // metres: faded out by here

varying float fade;

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;   // the particle, in view space
	vec3 along = (VIEW_MATRIX * vec4(velocity, 0.0)).xyz * length_s;
	float len = max(length(along), min_length);
	vec3 axis = length(along) > 1e-4 ? normalize(along) : vec3(0.0, 1.0, 0.0);
	vec3 side = cross(axis, normalize(centre));
	side = length(side) > 1e-4 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	VERTEX = centre + side * VERTEX.x * width + axis * VERTEX.y * len;
	float d = length(centre);
	fade = COLOR.a * smoothstep(0.4, 1.5, d) * (1.0 - smoothstep(far * 0.6, far, d));
}

void fragment() {
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	float ends = 1.0 - abs(UV.y * 2.0 - 1.0);
	ALBEDO = colour.rgb;
	ALPHA = colour.a * fade * edge * smoothstep(0.0, 0.5, ends);
}
