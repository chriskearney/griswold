import Foundation

/// Metal shader source, compiled at launch. Keeping it inline means the app has
/// no resource bundle to sign or locate, and builds with plain `swift build`.
enum ShaderSource {
    static let metal = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 viewport;   // size in points
        float scale;       // pixels per point
        float time;
    };

    struct Sprite {
        float2 pos;        // centre, points, origin top-left
        float2 size;       // full size, points
        float4 color;      // straight rgb, a = opacity
        float4 uv;         // atlas rect (u0, v0, u1, v1)
        float rot;
        float shape;
        float p0;
        float p1;
    };

    struct SpriteOut {
        float4 position [[position]];
        float2 local;
        float2 uv;
        float4 color;
        float2 half_size [[flat]];
        float shape [[flat]];
        float p0 [[flat]];
        float p1 [[flat]];
    };

    constant float2 kCorners[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(1, -1), float2(1, 1), float2(-1, 1)
    };

    vertex SpriteOut sprite_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   const device Sprite *sprites [[buffer(0)]],
                                   constant Uniforms &u [[buffer(1)]]) {
        Sprite s = sprites[iid];
        float2 c = kCorners[vid];
        float2 h = s.size * 0.5;
        float2 p = c * h;
        float cs = cos(s.rot);
        float sn = sin(s.rot);
        float2 r = float2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
        float2 world = s.pos + r;
        SpriteOut o;
        o.position = float4(world.x / u.viewport.x * 2.0 - 1.0,
                            1.0 - world.y / u.viewport.y * 2.0, 0.0, 1.0);
        o.local = c;
        o.uv = mix(s.uv.xy, s.uv.zw, c * 0.5 + 0.5);
        o.color = s.color;
        o.half_size = h * u.scale;
        o.shape = s.shape;
        o.p0 = s.p0;
        o.p1 = s.p1;
        return o;
    }

    static float sd_uneven_capsule(float2 p, float r1, float r2, float h) {
        p.x = abs(p.x);
        float b = (r1 - r2) / h;
        float a = sqrt(1.0 - b * b);
        float k = dot(p, float2(-b, a));
        if (k < 0.0) return length(p) - r1;
        if (k > a * h) return length(p - float2(0.0, h)) - r2;
        return dot(p, float2(a, b)) - r1;
    }

    static float sd_round_box(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    static float sd_star5(float2 p, float r, float rf) {
        const float2 k1 = float2(0.809016994375, -0.587785252292);
        const float2 k2 = float2(-k1.x, k1.y);
        p.x = abs(p.x);
        p -= 2.0 * max(dot(k1, p), 0.0) * k1;
        p -= 2.0 * max(dot(k2, p), 0.0) * k2;
        p.x = abs(p.x);
        p.y -= r;
        float2 ba = rf * float2(-k1.y, k1.x) - float2(0, 1);
        float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
        return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
    }

    static float sd_segment(float2 p, float2 a, float2 b) {
        float2 pa = p - a;
        float2 ba = b - a;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        return length(pa - ba * h);
    }

    // Six-armed crystal, in a -1...1 box.
    static float sd_crystal(float2 p) {
        const float sector = 1.0471975512;
        float ang = atan2(p.y, p.x);
        float r = length(p);
        float a = abs(fmod(abs(ang) + sector * 0.5, sector) - sector * 0.5);
        float2 q = float2(cos(a), sin(a)) * r;
        float d = sd_segment(q, float2(0.0, 0.0), float2(0.92, 0.0));
        d = min(d, sd_segment(q, float2(0.42, 0.0), float2(0.62, 0.20)));
        d = min(d, sd_segment(q, float2(0.66, 0.0), float2(0.80, 0.14)));
        return d;
    }

    // Light bulb: returns premultiplied colour. `lit` is 0 (dark glass) and up.
    static float4 bulb(float2 local, float2 half_px, float3 tint, float lit, float style) {
        float aspect = half_px.y / half_px.x;
        float2 p = float2(local.x, local.y * aspect);
        float aa = 1.5 / half_px.x;

        float glass;        // signed distance to glass
        float socket;       // signed distance to socket
        float2 hot;         // filament centre
        if (style < 0.5) {              // C9
            glass = sd_uneven_capsule(p - float2(0.0, -aspect + 1.80), 0.92, 0.34, aspect * 2.0 - 2.19);
            socket = sd_round_box(p - float2(0.0, -aspect + 0.50), float2(0.50, 0.50), 0.12);
            hot = float2(0.0, -aspect + 1.9);
        } else if (style < 1.5) {       // mini
            glass = sd_uneven_capsule(p - float2(0.0, -aspect + 1.86), 0.66, 0.14, aspect * 2.0 - 2.05);
            socket = sd_round_box(p - float2(0.0, -aspect + 0.62), float2(0.62, 0.62), 0.10);
            hot = float2(0.0, -aspect + 2.0);
        } else if (style < 2.5) {       // globe
            glass = length(p - float2(0.0, aspect - 0.96)) - 0.94;
            socket = sd_round_box(p - float2(0.0, -aspect + 0.36), float2(0.36, 0.36), 0.08);
            hot = float2(0.0, aspect - 0.96);
        } else {                        // star
            glass = sd_star5(float2(p.x, -p.y), 0.80, 0.46) - 0.14;
            socket = 10.0;
            hot = float2(0.0, 0.0);
        }

        float glass_a = clamp(0.5 - glass / aa, 0.0, 1.0);
        float socket_a = clamp(0.5 - socket / aa, 0.0, 1.0);

        float inside = clamp(-glass, 0.0, 1.0);
        float core = smoothstep(0.0, 0.75, inside);
        float hot_d = length((p - hot) * float2(1.0, 0.7));
        float filament = exp(-hot_d * hot_d * 3.2);

        float3 dark = tint * 0.42 + float3(0.03, 0.03, 0.04);
        float3 glow = tint * (0.72 + 0.70 * core) + float3(1.0, 0.97, 0.90) * filament * 0.70;
        float l = clamp(lit, 0.0, 1.0);
        float3 body = mix(dark, glow, l) + tint * max(lit - 1.0, 0.0) * 0.6
                    + float3(1.0) * max(lit - 1.0, 0.0) * filament;

        // Glass rim and a single specular streak, so an unlit bulb still reads as glass.
        float rim = smoothstep(0.22, 0.0, inside);
        body *= 1.0 - rim * 0.22 * (1.0 - l * 0.6);
        float2 sp = (p - (hot + float2(-0.34, -0.30))) / float2(0.13, 0.30);
        float spec = clamp(1.0 - dot(sp, sp), 0.0, 1.0);
        body += float3(1.0) * spec * spec * (0.42 + 0.2 * l);

        float ridge = 0.5 + 0.5 * cos((p.y + aspect) * 14.0);
        float3 socket_rgb = float3(0.06, 0.27, 0.16) * (0.75 + 0.35 * ridge)
                          * (1.0 - 0.45 * smoothstep(-0.2, 0.6, p.x));
        socket_rgb += tint * l * 0.10;

        float3 rgb = mix(socket_rgb, body, glass_a);
        float alpha = max(glass_a * 0.96, socket_a);
        return float4(rgb * alpha, alpha);
    }

    fragment float4 sprite_fragment(SpriteOut in [[stage_in]],
                                    constant Uniforms &u [[buffer(1)]],
                                    texture2d<float> atlas [[texture(0)]],
                                    sampler samp [[sampler(0)]]) {
        int shape = int(in.shape + 0.5);
        float2 l = in.local;
        float d = length(l);
        float3 rgb = in.color.rgb;
        float op = in.color.a;

        switch (shape) {
        case 0: {   // soft round flake; p0 = solid core radius
            float a = op * smoothstep(1.0, in.p0, d);
            return float4(rgb * a, a);
        }
        case 1: {   // crystal flake
            float px = min(in.half_size.x, in.half_size.y);
            float w = 0.055 + 1.0 / px;
            float sd = sd_crystal(l);
            float a = op * clamp((w - sd) * px * 0.75, 0.0, 1.0) * smoothstep(1.0, 0.86, d);
            return float4(rgb * a, a);
        }
        case 2: {   // halo; p0 = how much it also tints (0 is pure added light)
            float g = max(1.0 - d, 0.0);
            g = g * g * (0.35 + 0.65 * g);
            float i = g * op;
            return float4(rgb * i, i * in.p0);
        }
        case 3: {   // bulb; p0 = lit, p1 = style
            float4 c = bulb(l, in.half_size, rgb, in.p0, in.p1);
            return c * op;
        }
        case 4: {   // four-point glint; p0 = solidity
            float ax = abs(l.x);
            float ay = abs(l.y);
            float glint = exp(-ax * 16.0) * exp(-ay * 2.6) + exp(-ay * 16.0) * exp(-ax * 2.6);
            float core = exp(-d * d * 9.0);
            float fade = clamp(1.0 - d, 0.0, 1.0);
            float i = (glint * 0.75 + core) * fade * op;
            return float4(rgb * i, min(i, 1.0) * in.p0);
        }
        case 5: {   // atlas art (premultiplied texture)
            float4 t = atlas.sample(samp, in.uv);
            return float4(t.rgb * rgb, t.a) * op;
        }
        case 6: {   // snow clump; p0 = seed
            float ang = atan2(l.y, l.x);
            float wob = 0.10 * sin(ang * 3.0 + in.p0 * 6.283) + 0.06 * sin(ang * 5.0 + in.p0 * 17.0);
            float a = op * smoothstep(1.0, 0.45, d + wob);
            return float4(rgb * a, a);
        }
        case 7: {   // northern lights; p0 = intensity, p1 = horizontal offset in points
            float2 pt = in.position.xy / u.scale;
            float x = (pt.x + in.p1) * 0.0042;
            float t = u.time * 0.13;
            float n1 = sin(x * 2.1 + t * 1.7 + sin(x * 0.7 - t) * 1.6);
            float n2 = sin(x * 4.3 - t * 2.3 + sin(x * 1.9 + t * 0.6) * 1.1);
            float curtain = 0.5 + 0.25 * n1 + 0.25 * n2;
            float rays = 0.62 + 0.38 * sin((pt.x + in.p1) * 0.105 + sin((pt.x + in.p1) * 0.031 + t * 3.0) * 4.0);
            float yy = l.y * 0.5 + 0.5;
            float yb = 0.38 + 0.50 * curtain;
            float above = max(yb - yy, 0.0);
            float i = smoothstep(yb + 0.05, yb - 0.03, yy) * exp(-above * 3.4) * smoothstep(0.0, 0.05, yy);
            float3 green = float3(0.12, 1.0, 0.50);
            float3 violet = float3(0.56, 0.26, 1.0);
            float3 c = mix(green, violet, smoothstep(0.05, 0.85, above / max(yb, 0.01) + 0.18 * n2));
            i *= rays * in.p0 * op;
            return float4(c * i, i * 0.22);
        }
        case 8: {   // streak with a bright head at +x
            float along = l.x * 0.5 + 0.5;
            float tail = along * along * along;
            float width = mix(0.12, 0.55, along);
            float body = exp(-(l.y * l.y) / (width * width)) * tail;
            float2 hd = float2((l.x - 0.86) * in.half_size.x / in.half_size.y, l.y);
            float head = exp(-dot(hd, hd) * 2.4);
            float i = (body * 0.8 + head * 1.4) * op * smoothstep(1.0, 0.9, abs(l.x));
            return float4(rgb * i, min(i, 1.0) * in.p0);
        }
        default: {
            float a = op * smoothstep(1.0, 0.9, d);
            return float4(rgb * a, a);
        }
        }
    }

    struct MeshIn {
        float2 pos;
        float2 aux;
        float4 color;
    };

    struct MeshOut {
        float4 position [[position]];
        float4 color;
        float2 aux;
    };

    vertex MeshOut mesh_vertex(uint vid [[vertex_id]],
                               const device MeshIn *verts [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]]) {
        MeshIn v = verts[vid];
        MeshOut o;
        o.position = float4(v.pos.x / u.viewport.x * 2.0 - 1.0,
                            1.0 - v.pos.y / u.viewport.y * 2.0, 0.0, 1.0);
        o.color = v.color;
        o.aux = v.aux;
        return o;
    }

    fragment float4 mesh_fragment(MeshOut in [[stage_in]]) {
        return float4(in.color.rgb * in.color.a, in.color.a);
    }
    """
}
