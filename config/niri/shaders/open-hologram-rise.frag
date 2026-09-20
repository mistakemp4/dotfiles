// @anim duration-ms 470; curve "ease-out-cubic"
// scanline wipe up, chromatic split converging, glowing wipe edge.
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;

    vec3 c = vec3(coords_geo.x, coords_geo.y + (1.0 - p) * 0.05, 1.0);

    float split = (1.0 - p) * 0.010;
    vec3 tr = niri_geo_to_tex * vec3(c.x + split, c.y, 1.0);
    vec3 tg = niri_geo_to_tex * c;
    vec3 tb = niri_geo_to_tex * vec3(c.x - split, c.y, 1.0);
    vec4 sr = texture2D(niri_tex, tr.st);
    vec4 sg = texture2D(niri_tex, tg.st);
    vec4 sb = texture2D(niri_tex, tb.st);
    vec4 color = vec4(sr.r, sg.g, sb.b, sg.a);

    float wipe = 1.15 - p * 1.35;
    float reveal = smoothstep(wipe, wipe + 0.16, c.y);

    float scan = 0.86 + 0.14 * sin(c.y * size_geo.y * 0.55 - p * 26.0);
    scan = mix(scan, 1.0, p * p);

    color *= reveal * scan;

    float band = smoothstep(wipe, wipe + 0.03, c.y)
               * (1.0 - smoothstep(wipe + 0.03, wipe + 0.20, c.y));
    // shader area exceeds the window; mask added light to it
    float inside = step(0.0, c.x) * step(c.x, 1.0)
                 * step(0.0, c.y) * step(c.y, 1.0);
    float ga = band * inside * (1.0 - p) * 0.75;
    color += vec4(vec3(0.533, 0.404, 0.894) * ga, ga);

    return color * smoothstep(0.0, 0.18, p);
}
