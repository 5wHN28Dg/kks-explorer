// The plant's textured materials (weathered.gdshader includes it) (kit/materials.gd): a CC0 PBR set (albedo, normal, roughness, tiled in metres
// along UV1) and the weathering a plant in service shows, from where a surface stands in the world (R9, R9a):
//   grime    dirt in the splash zone near the ground and under overhangs, faint patches elsewhere (large blotches
//            read as camouflage: second realism pass)
//   streaks  run-off down vertical faces (rust-brown on steel, dark on concrete and paint); on walls that know their
//            top edge (`top_edge`: the panel's top in the vertex colour, builder/plant_builder.gd) the streaks hang
//            from that edge, under a coping, a roof's eaves or an opening's sill
//   dust     pale dust on surfaces that face up
//   rust     rust patches on steel and in paint damage
//   wear     paint worn to bare metal where hands and feet go (vertex colour alpha: the piece's exposure, 1 for
//            handrails, ladders, handwheels; 0 for a part that is never touched)
//   wet      darker and glossier ground and walls near water (the cooling tower's basin): the box `wet_zone`
// All from one tileable noise texture made by the build (builder/weather.gd), sampled in world space on the face's
// main plane (one sample per scale): the same asset set serves every tier, the phone reads one noise sample fewer
// (`detail` = 0 drops the wear's own sample). The ground's ruts break and its track wanders by arithmetic noise (no
// sample), the same on every tier: the phone's were unbroken and straight while they took two samples (polish pass).
// Corrugated sheet (`sheet_width`): the set's normal map gives the ribs; the sheets are drawn from UV1, each a little
// different in tone and gloss, with the lap between them, faded out where a sheet is under a few pixels.
// Pipe cladding (`lap_length`): aluminium sheets lapped every lap_length along the pipe (UV1.y) with the seam along it.
// The ground (`macro`): large patches of darker and paler ground, compacted bands with tyre ruts beside the road
// (`line_box`) and along a track (`track`).
// Floors: glazed tiles (`tile_size`) with grout, and bare concrete's cracks, scuffs and tyre marks (`cracks`), no
// texture read of their own.
// Gratings (`grating`): an open bar grating drawn from UV1 (30 mm bars, 100 mm cross rods), its gaps dark, and its
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
const float TILE_SHEEN = 0.7;         // a tiled floor's sheen at a grazing view, as a share of its colour
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);   // lamps' light (as Godot's standard material's)
uniform float emission_energy = 0.0;
uniform float detail = 1.0;   // the tier: 1 every sample, 0 the phone's
uniform float grating = 0.0;          // 1: an open bar grating (drawn)
uniform float joint_spacing = 0.0;    // concrete yards: joints this many metres apart (0: none)
uniform vec4 line_box = vec4(0.0);    // a road's centre line: a box round the plant (centre x, z; half sizes), dashed
uniform float road_line = 1.0;        // 1: draw the centre line (the road); 0: the box only places the ruts (the ground)
uniform float top_edge = 0.0;         // 1: the vertex colour carries the face's top (r: quarter metres, g: the fraction)
uniform float sheet_width = 0.0;      // corrugated sheets this wide (m) along UV1.x (0: none)
uniform float lap_length = 0.0;       // cladding sheets this long (m) along UV1.y (0: none)
uniform float macro = 0.0;            // the ground's large-scale variation and ruts (0: none)
uniform vec4 track = vec4(0.0);       // a track's axis: a point (x, z) and a unit direction (x, z); zero: none
uniform float tile_size = 0.0;        // a tiled floor: square tiles this wide (m) in world x, z, grout between (0: none)
uniform float tile_bond = 0.0;        // 1: block paving, bricks twice as long as wide (`tile_size`) laid in half bond
uniform float tile_tone = 0.06;       // how much one tile's tone differs from the next (glazed tiles little, pavers more)
uniform float tile_gloss = 1.0;       // the tiles' sheen at a grazing view (0: none, as concrete pavers)
uniform float cracks = 0.0;           // a bare concrete floor's cracks, scuffs and tyre marks (0: none)

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

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

// smooth 1D value noise in [0, 1] (no texture read: the same on every tier)
float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash1(i), hash1(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// ruts: two wheel tracks either side of an axis at distance d across it (metres), broken where the noise says
float ruts(float d, float along, float fw) {
	float r = 0.0;
	for (int i = 0; i < 2; i++) {
		float c = i == 0 ? -0.9 : 0.9;
		float w = 0.22 + fw;
		r = max(r, 1.0 - smoothstep(w * 0.5, w, abs(d - c)));
	}
	return r;
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
	vec4 n_lo = texture(noise_tex, pl * 0.045);        // patches a few metres across
	vec4 n_hi = texture(noise_tex, pl * 0.55 + 0.37);  // spots under a metre
	float up = wnrm.y;
	float vert = 1.0 - abs(up);
	float splash = 1.0 - smoothstep(0.0, 1.2 + 0.8 * n_hi.g, wpos.y); // the splash zone above the ground, ragged

	// corrugated sheets: each sheet its own tone and gloss, the laps between them
	if (sheet_width > 0.0) {
		float sx = UV.x / sheet_width;
		float hs = hash1(floor(sx));
		base *= 0.92 + 0.16 * hs;
		rough = mix(rough, rough * (0.8 + 0.4 * hs), 0.8);
		float fw = fwidth(sx);
		float lap = 1.0 - smoothstep(0.012, 0.012 + fw * 1.5, abs(fract(sx + 0.5) - 0.5));
		base *= 1.0 - 0.35 * lap * (1.0 - smoothstep(0.03, 0.12, fw));
	}
	// pipe cladding: sheets lapped along the pipe, the seam along it
	if (lap_length > 0.0) {
		float sy = UV.y / lap_length;
		float hs = hash1(floor(sy) + 7.0);
		base *= 0.93 + 0.12 * hs;
		rough = mix(rough, 0.25 + 0.35 * hs, 0.5);
		float fw = fwidth(sy);
		float lap = 1.0 - smoothstep(0.01, 0.01 + fw * 1.5, abs(fract(sy + 0.5) - 0.5));
		base *= 1.0 - 0.45 * lap * (1.0 - smoothstep(0.05, 0.2, fw));
	}

	// grime: faint patches, the splash zone near the ground, the undersides
	float g = grime * clamp(smoothstep(0.45, 0.9, n_lo.r) * 0.2 + splash * (0.45 + 0.55 * n_hi.g) * (0.7 + 0.6 * n_lo.g) + max(-up, 0.0) * 0.5, 0.0, 1.0);
	base = mix(base, base * vec3(0.60, 0.57, 0.53), g);

	// streaks: run-off down vertical faces, in columns picked by a hash of the column (not a tiled noise: its 1.1 m
	// period read as boarding, adversarial review), gathered where the few-metre noise says: fine ones 0.18 m wide
	// and broad, fainter ones 0.75 m wide that still read from across a yard and on a phone's small screen (the fine
	// ones alone were hard to see there: polish pass). No texture read of their own, so the phone draws them too;
	// derivatives outside the branches.
	float h = (abs(wnrm.x) > abs(wnrm.z)) ? wpos.z : wpos.x;
	float hc = h / 0.18;
	float fwc = fwidth(hc);
	float k = floor(hc);
	float hb = h / 0.75 + 0.31;
	float fwb = fwidth(hb);
	float kb = floor(hb);
	float s = 0.0;
	if (vert > 0.5) {
		float colw = smoothstep(0.50, 0.80, hash1(k * 1.37 + 11.0) * (0.55 + 0.9 * n_lo.g));
		float shape = 1.0 - smoothstep(0.35, 1.0, abs(fract(hc) - 0.5) * 2.0);
		float col = mix(colw * shape, colw * 0.65, smoothstep(0.25, 0.8, fwc));   // under a pixel: their mean
		float bw = smoothstep(0.35, 0.75, hash1(kb * 3.17 + 2.0) * (0.6 + 0.8 * n_lo.g));
		float bshape = 1.0 - smoothstep(0.2, 1.0, abs(fract(hb) - 0.5) * 2.0);
		float broad = mix(bw * bshape, bw * 0.55, smoothstep(0.25, 0.8, fwb));
		if (top_edge > 0.5) {
			// hanging from the face's top edge, each column its own length
			float top = (round(COLOR.r * 255.0) + COLOR.g) * 0.25;
			float below = max(top - wpos.y, 0.0);
			// longer on a taller face (a 20 m hall's run down most of it, a fence's a hand or two)
			float len = (0.5 + 4.0 * hash1(k * 2.11 + 5.0)) * (1.0 + top * 0.12);
			float hang = 1.0 - smoothstep(0.0, len, below);
			float blen = (2.0 + 7.0 * hash1(kb * 1.93 + 8.0)) * (1.0 + top * 0.08);
			float bhang = 1.0 - smoothstep(0.0, blen, below);
			s = streaks * max(col * hang, broad * bhang * 0.75) + streaks * (1.0 - smoothstep(0.0, 0.3, below)) * 0.45;
		} else {
			s = streaks * max(col, broad * 0.6) * (0.4 + 0.6 * n_hi.g);
		}
		s = clamp(s * vert, 0.0, 1.0);
		vec3 run = mix(vec3(0.42, 0.40, 0.37), vec3(0.45, 0.26, 0.14), clamp(rust * 2.0, 0.0, 1.0));
		base = mix(base, base * run * 1.25, s);
	}

	// rust: small spots, more where water runs, gathered in patches of a few metres (the spots' own noise repeats
	// every 1.8 m)
	float r = rust * smoothstep(0.74, 0.88, n_hi.r * 0.75 + n_hi.a * 0.25 + s * 0.35) * smoothstep(0.30, 0.60, n_lo.b);
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

	float fwp = length(fwidth(wpos.xz));   // outside the branch below: derivatives in uniform control flow
	// the ground: large patches, compacted bands and ruts beside the road and along a track
	if (macro > 0.0 && up > 0.7) {
		vec4 m = texture(noise_tex, wpos.xz * 0.0021 + 0.21);   // soft patches of 50 to 200 m
		float dark = smoothstep(0.38, 0.75, m.g);
		float pale = 1.0 - smoothstep(0.25, 0.55, m.r);
		base = mix(base, base * vec3(0.84, 0.81, 0.78), dark * macro);
		base = mix(base, base * vec3(1.08, 1.06, 1.03), pale * macro * 0.8);
		rough = mix(rough, rough * 0.9, dark * macro);
		float compact = 0.0;
		float rut = 0.0;
		if (line_box.z > 0.0) {
			vec2 q = abs(wpos.xz - line_box.xy) - line_box.zw;
			float dist = abs(length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0));
			float along = (q.x > q.y) ? wpos.z : wpos.x;
			// the verge beside the road's edges: vehicles pull over there
			float off = dist - 5.6;
			compact = max(compact, 1.0 - smoothstep(1.2, 2.6, abs(off)));
			// broken: pulled over here and there, gaps of a few metres
			float br = smoothstep(0.35, 0.5, 0.65 * vnoise(along * 0.09) + 0.35 * vnoise(along * 0.37 + 3.7));
			rut = max(rut, ruts(off, along, fwp) * br);
		}
		if (dot(track.zw, track.zw) > 0.5) {
			vec2 o = wpos.xz - track.xy;
			float along = dot(o, track.zw);
			float across = dot(o, vec2(-track.w, track.z));
			if (along > 0.0) {
				// it wanders a few metres either way once clear of the gate
				float wob = (0.7 * vnoise(along * 0.017 + 1.3) + 0.3 * vnoise(along * 0.061 + 7.1) - 0.5) * 14.0 * smoothstep(15.0, 90.0, along);
				compact = max(compact, 1.0 - smoothstep(2.0, 3.5, abs(across - wob)));
				rut = max(rut, ruts(across - wob, along, fwp));
			}
		}
		// compacted: darker and smoother (the loose stones pressed in), the ruts darker still
		base = mix(base, base * vec3(0.80, 0.78, 0.76), compact * 0.85);
		rough = mix(rough, rough * 0.8, compact);
		base = mix(base, base * 0.62, rut * 0.8);
	}

	// a yard's joints and a road's dashed centre line (on what faces up)
	if (joint_spacing > 0.0 && up > 0.7) {
		vec2 jg = abs(fract(wpos.xz / joint_spacing + 0.5) - 0.5) * joint_spacing;
		float jw = 0.006 + length(fwidth(wpos.xz)) * 0.7;
		float j = 1.0 - smoothstep(jw, jw * 2.0, min(jg.x, jg.y));
		base *= mix(1.0, 0.5, j);
	}
	if (line_box.z > 0.0 && road_line > 0.5 && up > 0.7) {
		vec2 q = abs(wpos.xz - line_box.xy) - line_box.zw;
		float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		float along = (q.x > q.y) ? wpos.z : wpos.x;
		float lw = 0.06 + fwidth(dist);
		float l = (1.0 - smoothstep(lw, lw * 1.5, abs(dist))) * step(0.5, fract(along / 6.0));
		base = mix(base, vec3(0.80, 0.78, 0.70), l * 0.85);
		rough = mix(rough, 0.7, l);
	}

	// a tiled floor (a turbine hall's operating floor, a walkway): glazed tiles, each a little different in tone and
	// gloss, the grout between them darker and matt (faded out where the tiles get under a few pixels)
	// (derivatives outside the branches: uniform control flow)
	vec2 tq = wpos.xz / max(tile_size, 0.01);
	vec2 tw = fwidth(tq);
	// block paving: rows along world x, each brick 2 tiles long, every other row shifted half a brick (the derivatives
	// taken before the shift: it jumps at each row)
	tq.x = mix(tq.x, tq.x * 0.5 + 0.5 * floor(tq.y), tile_bond);
	tw.x *= mix(1.0, 0.5, tile_bond);
	float cv = n_lo.b * 0.7 + n_hi.r * 0.3;
	float cw = fwidth(cv);
	float sheen = 0.0;
	if (tile_size > 0.0 && up > 0.7) {
		vec2 tf = abs(fract(tq) - 0.5);
		float gw = 0.004 / tile_size;
		float grout = 1.0 - smoothstep(gw, gw + max(tw.x, tw.y) * 1.2, 0.5 - max(tf.x, tf.y));
		grout *= 1.0 - smoothstep(0.08, 0.3, max(tw.x, tw.y));
		float th = hash1(dot(mod(floor(tq), 64.0), vec2(1.0, 57.0)) + 3.0);   // small arguments: sin keeps its precision on a phone
		base *= 1.0 - tile_tone * 0.67 + tile_tone * th;
		rough = mix(rough * (0.8 + 0.5 * th), 0.8, grout);
		base = mix(base, base * 0.72, grout);
		sheen = (1.0 - grout) * (0.8 + 0.4 * th) * tile_gloss;
	}
	// a bare concrete floor: hairline cracks (the noise's contours, broken), dark scuffs and tyre marks
	if (cracks > 0.0 && up > 0.7) {
		float line_ = 1.0 - smoothstep(0.004, 0.004 + cw * 1.5, abs(cv - 0.5));
		line_ *= smoothstep(0.45, 0.6, n_lo.a) * (1.0 - smoothstep(0.02, 0.06, cw));
		float scuff = smoothstep(0.55, 0.85, n_lo.g) * (0.5 + 0.5 * n_hi.b);
		float lane = vnoise(wpos.x * 0.35 + wpos.z * 0.05) * vnoise(wpos.z * 0.6 + 2.0);
		base = mix(base, base * 0.78, cracks * scuff * 0.6);
		base = mix(base, base * 0.82, cracks * smoothstep(0.35, 0.6, lane) * 0.35);
		base = mix(base, base * 0.45, cracks * line_);
		rough = mix(rough, rough * 0.85, cracks * scuff);
	}

	// dust on what faces up (flat tops: a pipe's crown only, not its upper half)
	float d = dust * smoothstep(0.80, 0.98, up) * (0.45 + 0.55 * n_hi.b);
	base = mix(base, vec3(0.56, 0.54, 0.50), d);
	rough = mix(rough, 1.0, d);

	// wet near water: darker, glossy; the ground and the foot of the walls
	if (wet > 0.0) {
		vec2 q = max(abs(wpos.xz - wet_zone.xy) - wet_zone.zw, vec2(0.0));
		float wz = wet * (1.0 - smoothstep(0.0, WET_FALLOFF, length(q))) * clamp(0.35 + n_lo.a * 0.9, 0.0, 1.0);
		wz *= 1.0 - smoothstep(0.0, 2.5, wpos.y);
		base *= mix(1.0, 0.5, wz);
		rough = mix(rough, 0.1, wz);
	}

	if (grating > 0.5) {
		// bar grating drawn, not cut out (a discarding shader was 7 more pipelines on a phone's first start:
		// decision 0057): bearing bars every 30 mm along U, cross rods every 100 mm along V (UV1 in metres), the
		// gaps the dark below; where the bars get smaller than a pixel, their mean
		vec2 m = UV;
		vec2 fw = fwidth(m);
		float bar = smoothstep(0.0, fw.x * 1.5, 0.004 - abs(fract(m.x / 0.03 + 0.5) - 0.5) * 0.03);
		float rod = smoothstep(0.0, fw.y * 1.5, 0.003 - abs(fract(m.y / 0.1 + 0.5) - 0.5) * 0.1);
		float solid = max(bar, rod);
		float far_ = smoothstep(0.004, 0.012, max(fw.x, fw.y));
		float open_ = mix(1.0 - solid, 0.6, far_);
		base = mix(base, base * 0.08, open_);
		rough = mix(rough, 1.0, open_);
	}

	// glazed tiles mirror the lit hall the flatter one looks along them: a sheen of the floor's own colour, lit as the
	// floor is (in shade under a machine, none; as light, it would glow there and in the bake: review). A reflection
	// probe per hall cost the laptop 14 to 19 ms of GPU time and half a gigabyte of video memory (photo pass)
	ALBEDO = min(base * (1.0 + sheen * TILE_SHEEN * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0)), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metal;
	// a material with its colours in the vertices glows in them (a sign's white board and its blue symbol)
	EMISSION = emission.rgb * emission_energy * (use_vertex_colour ? srgb_to_linear(COLOR.rgb) : vec3(1.0));

	if (use_normal) NORMAL_MAP = texture(normal_tex, uv).rgb;
}
