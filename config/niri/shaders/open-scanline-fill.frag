// @anim duration-ms 440; curve "linear"
// drawn in scanlines top-to-bottom, draw head glows.
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;

    vec3 ct = niri_geo_to_tex * coords_geo;
    vec4 color = texture2D(niri_tex, ct.st);

    float lines = max(size_geo.y / 3.0, 1.0);
    float row = floor(coords_geo.y * lines);
    float row_y = (row + 0.5) / lines;

    float head = p * 1.12;
    float drawn = step(row_y, head);

    float glow = drawn * (1.0 - smoothstep(0.0, 0.05, head - row_y));

    float scan = 0.80 + 0.20 * mod(row, 2.0);
    scan = mix(scan, 1.0, smoothstep(0.70, 1.0, p));

    color *= drawn * scan;

    // shader area exceeds the window; mask added light to it
    float inside = step(0.0, coords_geo.x) * step(coords_geo.x, 1.0)
                 * step(0.0, coords_geo.y) * step(coords_geo.y, 1.0);
    float ga = glow * inside * 0.8;
    color += vec4(vec3(0.85, 0.80, 1.0) * ga, ga);

    return color;
}
