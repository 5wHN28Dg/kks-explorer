// The weathered PBR material (weathered.gdshaderinc), both faces drawn: walls, roofs and fences, seen from inside too.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://kit/weathered.gdshaderinc"
