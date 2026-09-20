// @anim duration-ms 440; curve "ease-out-quad"
// assembles from chunky blocks that pop in at random.
float nsh_hash21(vec2 v) {
    return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;

    float px = mix(56.0, 1.0, smoothstep(0.0, 0.9, p));
    vec2 pix = vec2(px) / max(size_geo.xy, vec2(1.0));
    vec2 cell = floor(coords_geo.xy / pix);
    vec2 c = (cell + 0.5) * pix;

    vec3 ct = niri_geo_to_tex * vec3(c, 1.0);
    vec4 color = texture2D(niri_tex, ct.st);

    float r = nsh_hash21(cell + niri_random_seed * 57.0);
    float on = smoothstep(r, r + 0.15, p * 1.35);

    return color * on * smoothstep(0.0, 0.15, p);
}
