// BDS shared helpers. Procedural noise only; no cloud texture is required.
const FX_PI: f32 = 3.14159265;

fn fx_hash31(p3in: vec3<f32>) -> f32 {
    var p3 = fract(p3in * 0.1031);
    p3 = p3 + dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

fn fx_hash21(p2: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p2.x, p2.y, p2.x) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn fx_vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = fx_hash21(i);
    let b = fx_hash21(i + vec2<f32>(1.0, 0.0));
    let c = fx_hash21(i + vec2<f32>(0.0, 1.0));
    let d = fx_hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fx_ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn fx_luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn fx_hg(c: f32, g: f32) -> f32 {
    let g2 = g * g;
    let d = max(1.0 + g2 - 2.0 * g * c, 0.0001);
    return (1.0 - g2) / (4.0 * FX_PI * d * sqrt(d));
}

fn fx_view_dir(uv: vec2<f32>) -> vec3<f32> {
    let ndc = vec2<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    let v = frame.projection_inverse * vec4<f32>(ndc.x, ndc.y, 0.5, 1.0);
    let vv = v.xyz / v.w;
    let w = frame.view_inverse * vec4<f32>(vv.x, vv.y, vv.z, 0.0);
    return normalize(w.xyz);
}

fn fx_low() -> f32 {
    return 1.0 - smoothstep(0.02, 0.5, clamp(frame.sun_direction.y, -0.3, 1.0));
}

fn fx_day() -> f32 {
    return smoothstep(-0.08, 0.30, frame.sun_direction.y);
}

fn fx_night() -> f32 {
    return 1.0 - smoothstep(-0.20, -0.02, frame.sun_direction.y);
}

fn fx_sun_color() -> vec3<f32> {
    let low = fx_low();
    let noon = vec3<f32>(1.0, 0.93, 0.80);
    let dusk = vec3<f32>(1.0, 0.40, 0.58);
    let vis = smoothstep(-0.10, 0.06, frame.sun_direction.y);
    return mix(noon, dusk, sqrt(low) * sqrt(sqrt(low))) * vis;
}

fn fx_sky_radiance(dir: vec3<f32>) -> vec3<f32> {
    let sun = frame.sun_direction;
    let low = fx_low();
    let day = fx_day();
    let up = clamp(dir.y, 0.0, 1.0);
    let h1 = 1.0 - up;
    let hz = h1 * h1 * h1 * sqrt(h1);
    let mu = max(dot(dir, sun), 0.0);
    let zen_day = vec3<f32>(0.10, 0.26, 0.68);
    let zen_dusk = vec3<f32>(0.30, 0.16, 0.46);
    let zen_night = vec3<f32>(0.003, 0.010, 0.055);
    let hor_day = vec3<f32>(0.60, 0.72, 0.88);
    let hor_dusk = vec3<f32>(1.00, 0.42, 0.62);
    let hor_night = vec3<f32>(0.010, 0.030, 0.110);
    let zen = mix(zen_night, mix(zen_day, zen_dusk, low), day);
    let hor = mix(hor_night, mix(hor_day, hor_dusk, low), day);
    var col = mix(zen, hor, hz);
    let bb = (dir.y - 0.16) * 4.2;
    let belt = 1.0 / (1.0 + bb * bb);
    col = col + vec3<f32>(1.00, 0.45, 0.68) * belt * low * day * (0.18 + 0.42 * mu);
    let sc = fx_sun_color();
    let m2 = mu * mu;
    let m4 = m2 * m2;
    let m5 = m4 * mu;
    let m10 = m5 * m5;
    let m20 = m10 * m10;
    let m40 = m20 * m20;
    let m80 = m40 * m40;
    let m160 = m80 * m80;
    let m320 = m160 * m160;
    let m400 = m320 * m80;
    let mie = m5 * 0.25 + m40 * 0.35 + m400 * 0.8;
    col = col + sc * mie * (0.35 + 0.65 * low);
    let below = 1.0 - smoothstep(-0.25, 0.0, dir.y);
    col = mix(col, hor * 0.75, below);
    let g = fx_luma(col);
    return mix(col, vec3<f32>(g, g, g) * 0.65, frame.rain * 0.7);
}

fn fx_fog_radiance(pd: vec3<f32>) -> vec3<f32> {
    let sun = frame.sun_direction;
    let low = fx_low();
    let day = fx_day();
    let il = inverseSqrt(pd.x * pd.x + pd.z * pd.z + 0.0009);
    let mu = max((pd.x * sun.x + pd.z * sun.z + 0.03 * sun.y) * il, 0.0);
    let zen = mix(vec3<f32>(0.003, 0.010, 0.055), mix(vec3<f32>(0.10, 0.26, 0.68), vec3<f32>(0.30, 0.16, 0.46), low), day);
    let hor = mix(vec3<f32>(0.010, 0.030, 0.110), mix(vec3<f32>(0.60, 0.72, 0.88), vec3<f32>(1.00, 0.42, 0.62), low), day);
    var col = mix(zen, hor, 0.9);
    col = col + vec3<f32>(1.00, 0.45, 0.68) * (0.742 * low * day * (0.18 + 0.42 * mu));
    let m2 = mu * mu;
    let m4 = m2 * m2;
    let m5 = m4 * mu;
    let m10 = m5 * m5;
    let m20 = m10 * m10;
    let m40 = m20 * m20;
    let m80 = m40 * m40;
    let m160 = m80 * m80;
    let m320 = m160 * m160;
    let mie = m5 * 0.25 + m40 * 0.35 + m320 * m80 * 0.8;
    col = col + fx_sun_color() * (mie * (0.35 + 0.65 * low));
    let g = fx_luma(col);
    return mix(col, vec3<f32>(g, g, g) * 0.65, frame.rain * 0.7);
}
