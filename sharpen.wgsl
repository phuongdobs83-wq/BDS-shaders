override sharpen_enabled: bool = true;
override sharpen_strength: f32 = 0.35;

fn bds_luma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(
        0.2126,
        0.7152,
        0.0722
    ));
}

fn post(input: PostInput) -> vec4<f32> {
    let center = input.color.rgb;

    if (!sharpen_enabled || sharpen_strength <= 0.001) {
        return input.color;
    }

    let size = vec2<f32>(textureDimensions(previous));
    let texel = 1.0 / max(size, vec2<f32>(1.0));

    let north = textureSampleLevel(
        previous, linear_sampler,
        input.uv + vec2<f32>(0.0, -texel.y), 0.0
    ).rgb;

    let south = textureSampleLevel(
        previous, linear_sampler,
        input.uv + vec2<f32>(0.0, texel.y), 0.0
    ).rgb;

    let east = textureSampleLevel(
        previous, linear_sampler,
        input.uv + vec2<f32>(texel.x, 0.0), 0.0
    ).rgb;

    let west = textureSampleLevel(
        previous, linear_sampler,
        input.uv + vec2<f32>(-texel.x, 0.0), 0.0
    ).rgb;

    let average = (north + south + east + west) * 0.25;
    let detail = center - average;

    let edge = smoothstep(
        0.015,
        0.18,
        abs(bds_luma(center) - bds_luma(average))
    );

    let strength = clamp(sharpen_strength, 0.0, 1.0);
    let result = center + detail * strength * mix(0.35, 1.0, edge);

    let low = min(min(north, south), min(east, west));
    let high = max(max(north, south), max(east, west));

    let final_color = clamp(
        result,
        max(low - vec3<f32>(0.025), vec3<f32>(0.0)),
        high + vec3<f32>(0.025)
    );

    return vec4<f32>(final_color, input.color.a);
}
