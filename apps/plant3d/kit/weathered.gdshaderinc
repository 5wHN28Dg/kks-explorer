// The plant's textured materials (included by weathered.gdshader and, with GRATING, weathered_grating.gdshader) (kit/materials.gd): a CC0 PBR set (albedo, normal, roughness, tiled in metres
// along UV1) and the weathering a plant in service shows, from where a surface stands in the world (R9, R9a):
//   grime    darker, browner blotches; heaviest in the splash zone near the ground and under overhangs
//   streaks  run-off down vertical faces (rust-brown on steel, dark on concrete and paint)
//   dust     pale dust on surfaces that face up
//   rust     rust patches on steel and in paint damage
//   wear     paint worn to bare metal where hands and feet go (vertex colour alpha: the piece's exposure, 1 for
//            handrails, ladders, handwheels; 0 for a part that is never touched)
//   wet      darker and glossier ground and walls near water (the cooling tower's basin): the box `wet_zone`
// All from one tileable noise texture made by the build (builder/weather.gd), sampled in world space on the face's
// main plane (one sample per scale): the same asset set serves every tier, the phone reads two noise samples fewer
// (`detail` = 0 drops the streaks' and wear's own samples).
// Gratings (GRATING, their own shader: only they discard pixels, so every other surface keeps early depth): open bar grating drawn from UV1 (30 mm bars, 100 mm cross rods), see-through near, and its
// mean colour where the bars get smaller than a pixel (no shimmer at a distance).

uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness_scale = 1.0;
uniform float metallic = 0.0;
uniform vec2 uv_scale = vec2(1.0);
uniform bool use_albedo = false;
uniform bool use_normal = false;
uniform bool use_rough = false;
uniform bool use_vertex_colour = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform float grime = 0.4;
uniform float streaks = 0.4;
uniform float dust = 0.3;
uniform float rust = 0.0;
uniform float wear = 0.0;
uniform vec4 wet_zone = vec4(0.0);    // a box round water: centre x, z (Godot's axes), half sizes along x and z
uniform float wet = 0.0;              // how wet at the box's edge and inside (0: no zone)
const float WET_FALLOFF = 9.0;        // metres beyond the box over which the ground dries
uniform float detail = 1.0;   // the tier: 1 every sample, 0 the phone's
uniform float joint_spacing = 0.0;    // concrete yards: joints this many metres apart (0: none)
uniform vec4 line_box = vec4(0.0);    // a road's centre line: a box round the plant (centre x, z; half sizes), dashed

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// the face's main plane in world space (one sample, not three)
vec2 plane(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y >= a.x && a.y >= a.z) return p.xz;
	if (a.x >= a.z) return p.zy;
	return p.xy;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 base = tint.rgb;
	if (use_albedo) base *= texture(albedo_tex, uv).rgb;
	if (use_vertex_colour) base *= srgb_to_linear(COLOR.rgb);   // the kit's colours are sRGB (kit/materials.gd)
	float rough = roughness_scale;
	if (use_rough) rough *= texture(rough_tex, uv).r;
	float metal = metallic;
	float exposure = use_vertex_colour ? COLOR.a : 1.0;

	vec2 pl = plane(wpos, wnrm);
	vec4 n_lo = texture(noise_tex, pl * 0.045);        // blotches a few metres across
	vec4 n_hi = texture(noise_tex, pl * 0.55 + 0.37);  // spots under a metre
	float up = wnrm.y;
	float vert = 1.0 - abs(up);
	float splash = 1.0 - smoothstep(0.0, 1.6, wpos.y); // the splash zone above the ground (and below it, in pits)

	// grime: darker and browner, under overhangs (faces looking down) and near the ground
	float g = grime * clamp(smoothstep(0.35, 0.8, n_lo.r) * 0.6 + splash * (0.4 + 0.6 * n_hi.g) + max(-up, 0.0) * 0.5, 0.0, 1.0);
	base = mix(base, base * vec3(0.62, 0.57, 0.50), g);

	// streaks: run-off down vertical faces, stretched along the height
	float s = 0.0;
	if (detail > 0.5) {
		float h = (abs(wnrm.x) > abs(wnrm.z)) ? wpos.z : wpos.x;
		float sn = texture(noise_tex, vec2(h * 0.9, wpos.y * 0.035)).b;
		s = streaks * vert * smoothstep(0.52, 0.78, sn) * (0.4 + 0.6 * n_lo.g);
		vec3 run = mix(vec3(0.42, 0.36, 0.30), vec3(0.45, 0.24, 0.12), clamp(rust * 2.0, 0.0, 1.0));
		base = mix(base, base * run * 1.6, s);
	}

	// rust: patches where the noise peaks, rough and not metallic
	float r = rust * smoothstep(0.66, 0.82, n_hi.r * 0.6 + n_lo.b * 0.5 + s * 0.3);
	base = mix(base, vec3(0.30, 0.14, 0.06) * (0.7 + 0.6 * n_hi.a), r);
	rough = mix(rough, 0.95, r);
	metal = mix(metal, 0.0, r);

	// paint wear to bare steel where hands and feet go (more on top faces)
	if (detail > 0.5 && wear > 0.0) {
		float wn = texture(noise_tex, pl * 3.1 + 0.11).a;
		float w = wear * exposure * smoothstep(0.70, 0.86, wn + max(up, 0.0) * 0.12);
		base = mix(base, vec3(0.36, 0.36, 0.35), w);
		metal = mix(metal, 0.8, w);
		rough = mix(rough, 0.45, w);
	}

	// a yard's joints and a road's dashed centre line (on what faces up)
	if (joint_spacing > 0.0 && up > 0.7) {
		vec2 jg = abs(fract(wpos.xz / joint_spacing + 0.5) - 0.5) * joint_spacing;
		float jw = 0.006 + fwidth(wpos.x) * 0.7;
		float j = 1.0 - smoothstep(jw, jw * 2.0, min(jg.x, jg.y));
		base *= mix(1.0, 0.5, j);
	}
	if (line_box.z > 0.0 && up > 0.7) {
		vec2 q = abs(wpos.xz - line_box.xy) - line_box.zw;
		float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		float along = (q.x > q.y) ? wpos.z : wpos.x;
		float lw = 0.06 + fwidth(dist);
		float l = (1.0 - smoothstep(lw, lw * 1.5, abs(dist))) * step(0.5, fract(along / 6.0));
		base = mix(base, vec3(0.80, 0.78, 0.70), l * 0.85);
		rough = mix(rough, 0.7, l);
	}

	// dust on what faces up
	float d = dust * smoothstep(0.55, 0.95, up) * (0.45 + 0.55 * n_hi.b);
	base = mix(base, vec3(0.62, 0.57, 0.49), d);
	rough = mix(rough, 1.0, d);

	// wet near water: darker, glossy; the ground and the foot of the walls
	if (wet > 0.0) {
		vec2 q = max(abs(wpos.xz - wet_zone.xy) - wet_zone.zw, vec2(0.0));
		float wz = wet * (1.0 - smoothstep(0.0, WET_FALLOFF, length(q))) * clamp(0.35 + n_lo.a * 0.9, 0.0, 1.0);
		wz *= 1.0 - smoothstep(0.0, 2.5, wpos.y);
		base *= mix(1.0, 0.5, wz);
		rough = mix(rough, 0.1, wz);
	}

#ifdef GRATING
	{
		// open bar grating: bearing bars every 30 mm along U, cross rods every 100 mm along V (UV1 in metres)
		vec2 m = UV;
		vec2 fw = fwidth(m);
		float bar = smoothstep(0.0, fw.x * 1.5, 0.004 - abs(fract(m.x / 0.03 + 0.5) - 0.5) * 0.03);
		float rod = smoothstep(0.0, fw.y * 1.5, 0.003 - abs(fract(m.y / 0.1 + 0.5) - 0.5) * 0.1);
		float solid = max(bar, rod);
		float far_ = smoothstep(0.004, 0.012, max(fw.x, fw.y));   // bars under a pixel: the mean
		ALPHA = mix(solid, 1.0, far_);
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		base *= mix(1.0, 0.45, far_);   // seen from afar, a grating is mostly the dark below it
	}
#endif

	ALBEDO = base;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metal;
	if (use_normal) NORMAL_MAP = texture(normal_tex, uv).rgb;
}
