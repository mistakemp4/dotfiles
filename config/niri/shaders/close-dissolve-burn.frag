// @anim duration-ms 420; curve "ease-out-quad"
// burns away along a noise front with an ember edge.
float nsh_hash21(vec2 v) {
    return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453);
}
float nsh_noise(vec2 v) {
    vec2 i = floor(v);
    vec2 f = fract(v);
    f = f * f * (3.0 - 2.0 * f);
    float a = nsh_hash21(i);
    float b = nsh_hash21(i + vec2(1.0, 0.0));
    float c = nsh_hash21(i + vec2(0.0, 1.0));
    float d = nsh_hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;

    vec3 ct = niri_geo_to_tex * coords_geo;
    vec4 color = texture2D(niri_tex, ct.st);

    float n = nsh_noise(coords_geo.xy * vec2(13.0, 8.0) + niri_random_seed * 23.0);
    n = n * 0.72 + (1.0 - coords_geo.y) * 0.28;   // burns bottom-up

    float t = p * 1.3;
    float intact = smoothstep(t - 0.07, t, n);
    float edge = intact * (1.0 - smoothstep(t, t + 0.11, n));

    color *= intact;

    // shader area exceeds the window; mask added light to it
    float inside = step(0.0, coords_geo.x) * step(coords_geo.x, 1.0)
                 * step(0.0, coords_geo.y) * step(coords_geo.y, 1.0);
    float ea = edge * inside * 0.95 * (1.0 - smoothstep(0.85, 1.0, p));
    color += vec4(vec3(0.671, 0.361, 0.839) * ea, ea);

    return color;
}
