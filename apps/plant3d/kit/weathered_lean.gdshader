// The weathered PBR material for the phone's tiers: the same, less the paint wear and the ground's ruts and track
// (weathered.gdshaderinc, LEAN).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#define LEAN
#include "res://kit/weathered.gdshaderinc"
