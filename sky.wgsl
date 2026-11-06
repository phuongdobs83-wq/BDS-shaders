override sun_enabled: bool = true;
override sun_shape: u32 = 0u;
override sun_size: f32 = 1.0;
override sun_halo: f32 = 0.75;
override warmth: f32 = 0.62;

fn bds_sun_disk(dir: vec3<f32>) -> vec3<f32> {
    if (!sun_enabled) { return vec3<f32>(0.0); }
    let sun = normalize(frame.sun_direction);
    let mu = clamp(dot(dir, sun), -1.0, 1.0);
    let radius = 0.0038 * sun_size;
    var disk = 0.0;
    if (sun_shape == 0u) {
        let angular = 1.0 - mu;
        disk = 1.0 - smoothstep(radius * radius * 0.42, radius * radius * 0.72, angular);
    } else {
        var right = cross(sun, vec3<f32>(0.0, 1.0, 0.0));
        if (dot(right, right) < 0.0001) { right = cross(sun, vec3<f32>(1.0, 0.0, 0.0)); }
        right = normalize(right);
        let up = normalize(cross(right, sun));
        let edge = max(abs(dot(dir, right)), abs(dot(dir, up)));
        disk = 1.0 - smoothstep(radius * 0.88, radius * 1.12, edge);
    }
    let halo = pow(max(mu, 0.0), 180.0) * sun_halo;
    let color = mix(vec3<f32>(1.0, 0.82, 0.60), vec3<f32>(1.0, 0.48, 0.30), fx_low());
    return color * (disk * 3.0 + halo * 0.45) * smoothstep(-0.08, 0.05, sun.y);
}

fn fx_cirrus(dir: vec3<f32>) -> vec4<f32> {
    return vec4<f32>(0.0, 0.0, 0.0, 1.0);
}

fn sky(input: SkyInput) -> vec4<f32> {
    if (frame.dimension != 0) { return input.color; }
    let dir = normalize(input.direction);
    if (dir.y < -0.05) {
        let w = 1.0 - 0.25 * smoothstep(0.0, 0.25, 0.0 - dir.y);
        return vec4<f32>(fx_fog_radiance(dir) * w, 1.0);
    }
    var col = fx_sky_radiance(dir);
    let clouds = fx_cirrus(dir);
    col = col * clouds.w + clouds.rgb;
    col = col + bds_sun_disk(dir);
    return vec4<f32>(max(col, vec3<f32>(0.0)), 1.0);
}
