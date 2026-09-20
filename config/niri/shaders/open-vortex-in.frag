// @anim duration-ms 300; curve "ease-out-cubic"
// spins and scales into place.
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    float e = 1.0 - pow(1.0 - p, 3.0);

    float scale = mix(0.42, 1.0, e);
    float angle = (1.0 - e) * 0.8;

    vec2 c = (coords_geo.xy - vec2(0.5)) * size_geo.xy;
    mat2 rot = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
    c = (rot * c) / scale;

    vec3 g = vec3(c / max(size_geo.xy, vec2(1.0)) + vec2(0.5), 1.0);
    vec3 ct = niri_geo_to_tex * g;
    return texture2D(niri_tex, ct.st) * smoothstep(0.0, 0.3, p);
}
