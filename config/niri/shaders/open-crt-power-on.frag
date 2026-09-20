// @anim duration-ms 440; curve "linear"
// hot dot -> line -> full picture. inverse of crt-collapse.
vec4 open_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;

    float hgrow = smoothstep(0.0, 0.30, p);
    float vgrow = smoothstep(0.28, 0.86, p);
    float sx = max(hgrow, 0.004);
    float sy = max(vgrow, 0.005);

    vec2 c = (coords_geo.xy - vec2(0.5)) / vec2(sx, sy) + vec2(0.5);
    if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0)
        return vec4(0.0);

    vec3 ct = niri_geo_to_tex * vec3(c, 1.0);
    vec4 color = texture2D(niri_tex, ct.st);

    float hot = 1.0 - smoothstep(0.22, 0.78, p);
    color.rgb = mix(color.rgb, vec3(0.88, 0.82, 1.0) * color.a, hot);

    float shimmer = 0.94 + 0.06 * sin(c.y * size_geo.y * 0.5 - p * 18.0);
    color *= mix(shimmer, 1.0, smoothstep(0.55, 1.0, p));

    return color * smoothstep(0.0, 0.07, p);
}
