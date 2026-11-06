override profile: u32 = 1u;
override godrays_enabled: bool = true;
override godrays_intensity: f32 = 0.65;
override godrays_samples: i32 = 8;
override godrays_thickness: f32 = 1.0;
override bloom_enabled: bool = true;
override bloom_strength: f32 = 0.22;
override vignette_enabled: bool = true;
override warmth: f32 = 0.62;
override saturation: f32 = 1.08;
override contrast: f32 = 1.05;
override exposure: f32 = 1.05;
override night_blue: f32 = 1.0;
override fog_amount: f32 = 1.0;

fn gr_filmic(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bds_ray_lane(uv: vec2<f32>, to_sun: vec2<f32>, perp: vec2<f32>, lane_px: f32, samples: i32, jitter: f32) -> f32 {
    var acc = 0.0;
    for (var i: i32 = 0; i < samples; i = i + 1) {
        let t = (f32(i) + jitter) / f32(samples);
        let suv = uv + to_sun * (t * 0.92) + perp * lane_px;
        var visible = 0.0;
        if (suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0) {
            visible = select(0.0, 1.0, depth_at(suv) <= 0.0);
        }
        acc = acc + visible * (1.0 - t * 0.45);
    }
    return acc / f32(samples);
}

fn post(input: PostInput) -> vec4<f32> {
    var rgb = max(input.color.rgb, vec3<f32>(0.0));
    let low = fx_low();
    var dist = 0.0;

    if (frame.dimension == 0 && frame.eye_in == 0u) {
        let dir = fx_view_dir(input.uv);
        let sun = frame.sun_direction;
        let sun_c = fx_sun_color();
        if (input.depth <= 0.0) {
            if (dir.y < 0.6) {
                let h0 = 1.0 - clamp(dir.y, 0.0, 1.0);
                let h02 = h0 * h0;
                rgb = mix(rgb, fx_fog_radiance(dir), h02 * h02 * h02 * 0.5 * clamp(fog_amount, 0.0, 1.5));
            }
        } else {
            let p = view_position(input.uv, input.depth);
            dist = length(p);
            let ym = frame.camera_position.y + 0.5 * p.y;
            let hfall = exp(0.0 - max(ym - 62.0, 0.0) * 0.012);
            let k = 0.0060 * fog_amount * (1.0 + frame.rain * 2.0 + frame.thunder);
            let tr = exp(0.0 - dist * k * hfall);
            let pd = p / max(dist, 0.0001);
            var fogc = fx_fog_radiance(pd);
            let mu0 = max(dot(pd, sun), 0.0);
            let mu2 = mu0 * mu0;
            fogc = fogc + sun_c * (mu2 * mu2 * mu2) * 0.35 * (0.4 + 0.6 * low);
            rgb = mix(fogc, rgb, tr);
        }

        let vis_sun = smoothstep(-0.08, 0.10, sun.y);
        let mu = dot(dir, sun);
        if (godrays_enabled && godrays_intensity > 0.0 && vis_sun > 0.0 && mu > -0.05) {
            let vs = (frame.view * vec4<f32>(sun.x, sun.y, sun.z, 0.0)).xyz;
            let clip = frame.projection * vec4<f32>(vs, 1.0);
            if (clip.w > 0.02) {
                let ndc = clip.xy / clip.w;
                let sun_uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
                let to_sun = sun_uv - input.uv;
                let perp = normalize(vec2<f32>(-to_sun.y, to_sun.x) + vec2<f32>(0.000001, 0.0));
                let jitter = fx_ign(input.pixel);
                let samples = clamp(godrays_samples, 4, 12);
                var shaft_visibility = 0.0;
                if (godrays_thickness <= 0.001) {
                    shaft_visibility = bds_ray_lane(input.uv, to_sun, perp, 0.0, samples, jitter);
                } else {
                    let px = clamp(godrays_thickness, 0.0, 3.0) * 1.5;
                    shaft_visibility = (
                        bds_ray_lane(input.uv, to_sun, perp, -px / max(frame.resolution.y, 1.0), samples, jitter) +
                        bds_ray_lane(input.uv, to_sun, perp, 0.0, samples, jitter) +
                        bds_ray_lane(input.uv, to_sun, perp, px / max(frame.resolution.y, 1.0), samples, jitter)
                    ) / 3.0;
                }
                let shaft = smoothstep(0.16, 0.66, shaft_visibility);
                let mu2 = max(mu, 0.0) * max(mu, 0.0);
                let phase = 0.25 + mu2 * mu2 * 1.8;
                var medium = 0.72;
                if (input.depth > 0.0) { medium = 1.0 - exp(0.0 - dist * 0.010); }
                let fall = 1.0 / (1.0 + length(to_sun) * 0.55);
                let edge = smoothstep(-0.05, 0.48, mu);
                var profile_gain = 1.0;
                if (profile == 0u) { profile_gain = 0.78; }
                if (profile == 2u) { profile_gain = 1.15; }
                let gain = godrays_intensity * profile_gain * (1.0 - frame.rain * 0.8);
                rgb = rgb + sun_c * (shaft * phase * medium * fall * gain * vis_sun * edge * 1.35);

                if (bloom_enabled && bloom_strength > 0.0) {
                    let aspect = frame.projection[1][1] / frame.projection[0][0];
                    let dd = vec2<f32>(to_sun.x * aspect, to_sun.y);
                    let d2 = dot(dd, dd);
                    let halo = 0.9 / (1.0 + d2 * 900.0) + 0.30 / (1.0 + d2 * 30.0);
                    rgb = rgb + sun_c * (halo * bloom_strength * vis_sun * edge * mix(0.25, 1.0, shaft) * (1.0 - frame.rain * 0.8) * 0.45);
                }
            }
        }
    }

    if (bloom_enabled && bloom_strength > 0.0 && input.depth > 0.0) {
        let bl = fx_luma(rgb);
        let hot = max(bl - 0.6, 0.0);
        let orange = smoothstep(0.35, 0.65, (rgb.r - rgb.b) / max(rgb.r, 0.001));
        rgb = rgb + vec3<f32>(1.0, 0.50, 0.20) * (hot * orange * bloom_strength * 0.8);
    }

    rgb = rgb * exposure;
    rgb = mix(rgb, gr_filmic(rgb * 1.15), 0.6);
    let dayw = fx_day();
    let wd = 0.05 * warmth * dayw;
    let wp = 0.30 * warmth * low * dayw;
    rgb = rgb * vec3<f32>(1.0 + wd * 0.98, 1.0 + wd * 0.35, 1.0 - wd * 0.91);
    rgb = rgb * vec3<f32>(1.0 + wp * 0.80, 1.0 - wp * 0.30, 1.0 + wp * 0.30);
    rgb = rgb + vec3<f32>(0.010, 0.009, 0.013);
    rgb = (rgb - vec3<f32>(0.5)) * contrast + vec3<f32>(0.5);
    rgb = max(rgb, vec3<f32>(0.0));
    let l2 = fx_luma(rgb);
    rgb = mix(vec3<f32>(l2), rgb, saturation);

    let night = fx_night();
    if (night > 0.0) {
        let nl = fx_luma(rgb);
        let nb = vec3<f32>(0.30, 0.55, 1.0) * (nl * 1.8 + 0.035 * night_blue);
        let keep = 1.0 - smoothstep(0.08, 0.40, nl);
        rgb = mix(rgb, nb, clamp(0.7 * night_blue, 0.0, 1.0) * night * keep);
    }
    if (vignette_enabled) {
        let centred = (input.uv - vec2<f32>(0.5)) * vec2<f32>(1.0, frame.resolution.y / max(frame.resolution.x, 1.0));
        let vignette = 1.0 - smoothstep(0.32, 0.82, length(centred)) * 0.22;
        rgb = rgb * vignette;
    }
    return vec4<f32>(clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
