// @anim duration-ms 340; curve "linear"
// swirls inward and vanishes.
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;
    float e = p * p;

    float scale = max(1.0 - e, 0.002);
    vec2 c = (coords_geo.xy - vec2(0.5)) * size_geo.xy;

    float d = length(c) / max(length(size_geo.xy) * 0.5, 1.0);
    float a = e * 2.6 * (0.35 + d);
    mat2 rot = mat2(cos(a), -sin(a), sin(a), cos(a));
    c = (rot * c) / scale;

    vec3 g = vec3(c / max(size_geo.xy, vec2(1.0)) + vec2(0.5), 1.0);
    if (g.x < 0.0 || g.x > 1.0 || g.y < 0.0 || g.y > 1.0)
        return vec4(0.0);

    vec3 ct = niri_geo_to_tex * g;
    return texture2D(niri_tex, ct.st) * (1.0 - smoothstep(0.65, 1.0, p));
}
