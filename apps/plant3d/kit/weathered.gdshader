// The weathered PBR material (weathered.gdshaderinc says what it draws).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://kit/weathered.gdshaderinc"
