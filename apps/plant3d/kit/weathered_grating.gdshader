// The weathered PBR material for open bar gratings (weathered.gdshaderinc): see-through, both faces drawn.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
#define GRATING
#include "res://kit/weathered.gdshaderinc"
