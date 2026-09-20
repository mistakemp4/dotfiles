// @anim duration-ms 200; curve "ease-out-quad"
// niri example: crop when growing, crossfade otherwise.
vec4 resize_color(vec3 coords_curr_geo, vec3 size_curr_geo) {
    vec3 coords_next_geo = niri_curr_geo_to_next_geo * coords_curr_geo;

    vec3 coords_crop = niri_geo_to_tex_next * coords_next_geo;
    vec3 coords_stretch = niri_geo_to_tex_next * coords_curr_geo;
    vec3 coords_stretch_prev = niri_geo_to_tex_prev * coords_curr_geo;

    bool can_crop_by_x = niri_curr_geo_to_next_geo[0][0] <= 1.0;
    bool can_crop_by_y = niri_curr_geo_to_next_geo[1][1] <= 1.0;
    bool crop = can_crop_by_x && can_crop_by_y;

    vec4 color;
    if (crop) {
        if (coords_curr_geo.x < 0.0 || 1.0 < coords_curr_geo.x ||
                coords_curr_geo.y < 0.0 || 1.0 < coords_curr_geo.y) {
            color = vec4(0.0);
        } else {
            color = texture2D(niri_tex_next, coords_crop.st);
        }
    } else {
        color = texture2D(niri_tex_next, coords_stretch.st);
        vec4 color_prev = texture2D(niri_tex_prev, coords_stretch_prev.st);
        color = mix(color_prev, color, niri_clamped_progress);
    }
    return color;
}
