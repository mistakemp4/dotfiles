// @anim duration-ms 355; curve "linear"
// slices tear sideways, RGB splits, rows drop out.
float nsh_hash11(float n) {
    return fract(sin(n * 91.3458) * 47453.5453);
}

vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;

    float rows = 20.0;
    float row = floor(coords_geo.y * rows);
    float r = nsh_hash11(row + floor(p * 8.0) * 13.0 + niri_random_seed * 77.0);
    float shove = (r - 0.5) * p * 0.5;

    float x = coords_geo.x + shove;
    if (x < 0.0 || x > 1.0)
        return vec4(0.0);

    float split = p * 0.03 * (0.4 + r);
    vec3 tr = niri_geo_to_tex * vec3(x + split, coords_geo.y, 1.0);
    vec3 tg = niri_geo_to_tex * vec3(x, coords_geo.y, 1.0);
    vec3 tb = niri_geo_to_tex * vec3(x - split, coords_geo.y, 1.0);
    vec4 sr = texture2D(niri_tex, tr.st);
    vec4 sg = texture2D(niri_tex, tg.st);
    vec4 sb = texture2D(niri_tex, tb.st);
    vec4 color = vec4(sr.r, sg.g, sb.b, sg.a);

    if (nsh_hash11(row * 3.7 + niri_random_seed * 31.0) < p * 0.55)
        color = vec4(0.0);

    return color * (1.0 - smoothstep(0.5, 1.0, p));
}
