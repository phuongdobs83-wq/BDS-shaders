override shadows: bool = true;
override shadow_strength: f32 = 0.72;
override ambient_floor: f32 = 0.42;
override sun_enabled: bool = true;

override water_reflections: bool = true;
override water_strength: f32 = 0.85;
override water_smooth: bool = true;
override water_distortion: f32 = 0.25;

override profile: u32 = 1u;

// --------------------------------------------
// SHADOWS
// --------------------------------------------

fn bds_shadow_visibility(position: vec3<f32>) -> f32 {
    if (!shadows || frame.has_shadow == 0u) {
        return 1.0;
    }

    let p = shadow_position(position);

    if (
        p.x < 0.0 || p.x > 1.0 ||
        p.y < 0.0 || p.y > 1.0 ||
        p.z < 0.0 || p.z > 1.0
    ) {
        return 1.0;
    }

    let bias = max(
        frame.shadow_center_texel * 0.65,
        0.00035
    );

    return textureSampleCompareLevel(
        shadow_map,
        shadow_sampler,
        p.xy,
        p.z - bias
    );
}

// --------------------------------------------
// MAIN MATERIAL
// --------------------------------------------

fn material(input: MaterialInput) -> Surface {
    let n = normalize(input.normal);
    let base = input.albedo * input.tint;

    let sky_l = input.light.y;
    let blk = input.light.x;

    let sun = frame.light_direction;
    let day = fx_day();
    let low = fx_low();
    let sc = fx_sun_color();

    let sg = smoothstep(0.88, 1.0, sky_l);
    let gate = sg * sqrt(sg);

    let ndl = clamp(
        (dot(n, sun) + 0.30) / 1.30,
        0.0,
        1.0
    );

    let shadow_vis = mix(
        1.0,
        bds_shadow_visibility(input.position),
        clamp(shadow_strength, 0.0, 1.0)
    );

    let sun_gain = select(1.0, 0.85, profile == 0u);

    let direct = sc * (
        ndl * gate * 1.7 *
        sun_gain * shadow_vis
    );

    let amb_col = mix(
        vec3<f32>(0.30, 0.37, 0.56),
        vec3<f32>(0.54, 0.30, 0.52),
        low
    );

    let sl = clamp(sky_l, 0.0, 1.0);
    let canopy = mix(
        0.50,
        1.0,
        smoothstep(0.70, 0.96, sky_l)
    );

    let hemi = 0.75 + 0.25 * n.y;

    var ambient = amb_col *
        hemi *
        (sl * sqrt(sqrt(sl))) *
        canopy *
        0.95 * day;

    ambient = ambient +
        sc * (0.16 * (1.0 - ndl) * sl * canopy);

    var moonlight = vec3<f32>(0.0);

    if (day < 0.999) {
        let night = 1.0 - day;
        let mdl = max(dot(n, frame.moon_direction), 0.0);

        ambient = ambient +
            vec3<f32>(0.028, 0.058, 0.16) *
            (sl * sl) * night *
            (0.6 + 0.4 * hemi);

        moonlight = vec3<f32>(0.06, 0.11, 0.28) *
            mdl * gate * night;
    }

    let bl = clamp(blk, 0.0, 1.0);

    let torch = vec3<f32>(1.0, 0.55, 0.22) *
        (bl * bl * sqrt(bl)) * 1.6;

    let floor_value = mix(
        0.008,
        0.075,
        clamp(ambient_floor, 0.0, 1.0)
    );

    let floor_l = vec3<f32>(floor_value) +
        vec3<f32>(0.5) * frame.night_vision;

    var lit = base.rgb *
        (direct + ambient + moonlight + torch + floor_l);

    // ----------------------------------------
    // BDS WATER REFLECTIONS
    // ----------------------------------------

    if (
        water_reflections &&
        input.fluid == 1u &&
        input.face == 1u &&
        frame.has_reflection != 0u
    ) {
        let view_dir = normalize(-input.position);

        // Fresnel reflection
        let fresnel = pow(
            1.0 - clamp(dot(n, view_dir), 0.0, 1.0),
            5.0
        );

        // Reflection distortion
        let distortion = input.normal.xz *
            clamp(water_distortion, 0.0, 1.0) *
            (0.002 + fresnel * 0.006);

        let refl_uv = clamp(
            input.screen + distortion,
            vec2<f32>(0.001),
            vec2<f32>(0.999)
        );

        // Sample mirrored world
        let reflected = textureSample(
            reflection,
            reflection_sampler,
            refl_uv
        ).rgb;

        // Smooth water base:
        // reduce vanilla texture influence
        var water_base = lit;

        if (water_smooth) {
            let smooth_tint = vec3<f32>(
                0.025,
                0.105,
                0.145
            );

            water_base = mix(
                lit,
                smooth_tint,
                0.85
            );
        }

        // Reflection intensity
        let reflect_amount = clamp(
            water_strength *
            (0.30 + fresnel * 0.65),
            0.0,
            0.95
        );

        lit = mix(
            water_base,
            reflected,
            reflect_amount
        );
    }

    return Surface(vec4<f32>(lit, base.a));
}

