// The weather's particles (app/weather_view.gd, REALISM.md §5.4): rain streaks or blown sand in a box round the
// camera. Each particle starts somewhere in the box and moves with the wind; one that leaves the box comes back in at
// the other side (the box moves with the camera), so the emitter never empties or bunches. Hidden (alpha 0) under a
// roof by the roof map, the global parameters the weathered shader reads. The programme's one new shader pair:
// counted on the phone and compiled in the start's hidden frame (decision 0060).
shader_type particles;
render_mode disable_force, disable_velocity, keep_data;

global uniform vec4 wx_roof_rect;
global uniform sampler2D wx_roof : filter_nearest, repeat_disable;

uniform vec3 half_box = vec3(25.0, 10.0, 25.0);   // metres round the camera
uniform vec3 velocity = vec3(0.0, -8.0, 0.0);     // m/s, the wind's push included
uniform float spread = 0.15;                      // each particle's own speed differs by up to this share

float rnd(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return float((w >> 22u) ^ w) / 4294967295.0;
}

void start() {
	uint s = NUMBER * 1664525u + RANDOM_SEED;
	vec3 r = vec3(rnd(s), rnd(s), rnd(s)) * 2.0 - 1.0;
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = EMISSION_TRANSFORM[3].xyz + r * half_box;
	CUSTOM.x = 1.0 + spread * (rnd(s) * 2.0 - 1.0);
	CUSTOM.y = rnd(s);
	COLOR = vec4(1.0);
}

void process() {
	vec3 c = EMISSION_TRANSFORM[3].xyz;
	vec3 p = TRANSFORM[3].xyz + velocity * CUSTOM.x * DELTA - c;
	p = mod(p + half_box, 2.0 * half_box) - half_box;
	TRANSFORM[3].xyz = c + p;
	vec3 at = TRANSFORM[3].xyz;
	vec2 ru = (at.xz - wx_roof_rect.xy) / max(wx_roof_rect.zw, vec2(1e-3));
	float roof = textureLod(wx_roof, ru, 0.0).r * 63.75;
	bool in_map = wx_roof_rect.z > 0.0 && all(greaterThanEqual(ru, vec2(0.0))) && all(lessThan(ru, vec2(1.0)));
	bool under = in_map && roof > 0.0 && at.y < roof;
	COLOR.a = (under || at.y < -0.2) ? 0.0 : 1.0;
}
