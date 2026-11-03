// The Workshop's cut planes (docs/plant3d/WORKSHOP.md §7.1, §7.2), shared by ws_lit and ws_cap so a cut face's cap
// is discarded exactly where its solid is. Planes in the Workshop's world (the machine stands at its origin): a point
// is cut by the cutaway when it lies on the positive side of its first plane and, with two, of its second too (a
// quarter); by the section when it lies on the section plane's positive side. A component the cutaway passes by
// (`keep`) has ws_keep 1 on its instances; the section cuts everything.
uniform vec4 ws_plane0 = vec4(0.0, 1.0, 0.0, 1e9);   // normal, distance along it from the origin
uniform vec4 ws_plane1 = vec4(0.0, 1.0, 0.0, -1e9);  // (the second: a far negative distance when there is one plane)
uniform vec4 ws_plane2 = vec4(0.0, 1.0, 0.0, 1e9);   // the section
uniform float ws_cut_on = 0.0;
uniform float ws_sec_on = 0.0;
instance uniform float ws_keep = 0.0;

bool ws_cut(vec3 p) {
	bool away = ws_cut_on > 0.5 && ws_keep < 0.5 && dot(ws_plane0.xyz, p) > ws_plane0.w
		&& dot(ws_plane1.xyz, p) > ws_plane1.w;
	bool sec = ws_sec_on > 0.5 && dot(ws_plane2.xyz, p) > ws_plane2.w;
	return away || sec;
}
