// The Workshop's lit material (docs/plant3d/WORKSHOP.md §7.1, `ws_lit`): the plant's weathered material (the same
// include, so a component looks as it does in the plant) with what the Workshop adds: a discard by the cut planes
// (ws_cut.gdshaderinc: the cutaway's and the section's), the heat and pressure colour of a component from its legend
// (`ws_ramp`: the colour, and how much of it, set per instance by the bench's bindings), and the selection's glow
// (`ws_sel`). No weather: the Workshop stands indoors. The cut faces are ws_cap, its next pass on solid components.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#define WS_LIT
#include "res://workshop/ws_cut.gdshaderinc"
instance uniform vec4 ws_ramp = vec4(0.0);
instance uniform float ws_sel = 0.0;
#include "res://kit/weathered.gdshaderinc"
