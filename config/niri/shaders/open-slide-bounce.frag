// @anim spring damping-ratio=0.62 stiffness=650 epsilon=0.0001
// rides up from below, overshoots on a spring.
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float off = (1.0 - niri_progress) * 0.30;
    vec3 g = vec3(coords_geo.x, coords_geo.y + off, 1.0);
    vec3 ct = niri_geo_to_tex * g;
    return texture2D(niri_tex, ct.st) * niri_clamped_progress;
}
