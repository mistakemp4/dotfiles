// @anim duration-ms 360; curve "linear"
// CRT power-off: squash to a line, flash, snap out.
vec4 close_color(vec3 coords_geo, vec3 size_geo) {
    float p = niri_clamped_progress;

    float vsquash = 1.0 - smoothstep(0.0, 0.55, p);
    float hsquash = 1.0 - smoothstep(0.55, 0.88, p);
    float sy = max(vsquash, 0.005);
    float sx = max(hsquash, 0.003);

    vec2 c = (coords_geo.xy - vec2(0.5)) / vec2(sx, sy) + vec2(0.5);
    if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0)
        return vec4(0.0);

    vec3 ct = niri_geo_to_tex * vec3(c, 1.0);
    vec4 color = texture2D(niri_tex, ct.st);

    float hot = smoothstep(0.3, 0.8, p);
    color.rgb = mix(color.rgb, vec3(0.88, 0.82, 1.0) * color.a, hot);

    return color * (1.0 - smoothstep(0.82, 1.0, p));
}
