// The Workshop's cut faces (docs/plant3d/WORKSHOP.md §7.2, `ws_cap`): ws_lit's next pass on a solid (closed) component.
// It draws the component's back faces, discarded by the same planes: where the eye looks through a cut into a solid it
// sees those inner faces, here drawn flat in the material's colour, darker, with a hatch, so the cut reads as a filled
// face (the material's colour: its tint, its texture's mean and its vertex colour). Where nothing is cut the back faces lie behind the front ones and the depth test hides them.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;
#include "res://workshop/ws_cut.gdshaderinc"
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_vertex_colour = false;
uniform bool use_albedo = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (ws_cut(wpos)) {
		discard;
	}
	vec3 c = tint.rgb;
	if (use_albedo) {
		c *= textureLod(albedo_tex, vec2(0.5), 12.0).rgb;   // the texture's mean colour (its smallest mipmap)
	}
	if (use_vertex_colour) {
		vec3 s = COLOR.rgb;
		c *= mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(0.04045, s));
	}
	float hatch = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) / (6.0 * max(1.0, VIEWPORT_SIZE.y / 1080.0))));
	ALBEDO = c * mix(0.38, 0.55, hatch);
}
