// Drawing the field.
//
// Every primitive is the same unit quad, oriented and sized per instance and
// given its shape by the fragment shader: a dot is a filled circle, a halo is
// the web's radial gradient written out as a curve, a streak is a capsule
// that fades along its length. Blending is additive — the web draws the whole
// field with `globalCompositeOperation = 'lighter'`, and light adds.
//
// A flower is the exception, and gets its own pass. Adding a picture to what
// is behind it washes its colours out toward white; it is composited over
// instead, premultiplied, which is how the atlas comes off the loader.

#include <metal_stdlib>
using namespace metal;

constant uint kindDot = 0;
constant uint kindGlow = 1;
constant uint kindStreak = 2;
constant uint kindOutline = 3;
constant uint kindSprite = 4;

/// The flower atlas, four across and three down.
constant uint kAtlasColumns = 4;
constant uint kAtlasRows = 3;

/// A slot outline is a hairline, the way the web strokes one.
constant float kOutlineWidth = 1.0;

struct FieldInstance {
    float4 color;
    float2 center;
    float2 halfSize;
    /// Unit vector along the instance's local x. (1, 0) for anything round.
    float2 axis;
    uint kind;
    /// Sprite only: which slot of the atlas to sample.
    uint slot;
    /// Sprite only: how far to pull the illustration toward `color`.
    float tint;
    uint padding;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float2 halfSize;
    float4 color;
    uint kind;
    uint slot;
    float tint;
};

vertex VertexOut fieldVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device FieldInstance *instances [[buffer(0)]],
    constant float2 &viewport [[buffer(1)]]
) {
    const float2 corners[4] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1)
    };
    const float2 local = corners[vertexID];
    const FieldInstance instance = instances[instanceID];

    const float2 axis = instance.axis;
    const float2 perpendicular = float2(-axis.y, axis.x);
    const float2 offset =
        axis * (local.x * instance.halfSize.x) + perpendicular * (local.y * instance.halfSize.y);
    const float2 point = instance.center + offset;

    VertexOut out;
    // Points to clip space, with y running down the screen as it does on a
    // canvas.
    out.position = float4(
        point.x / viewport.x * 2.0 - 1.0,
        1.0 - point.y / viewport.y * 2.0,
        0.0,
        1.0);
    out.uv = local;
    out.halfSize = instance.halfSize;
    out.color = instance.color;
    out.kind = instance.kind;
    out.slot = instance.slot;
    out.tint = instance.tint;
    return out;
}

/// The halo's profile, stop for stop with the sprite the web paints once and
/// reuses: bright at the middle, most of it gone by a quarter out, a long
/// faint skirt to the edge.
static float haloAlpha(float d) {
    if (d >= 1.0) { return 0.0; }
    if (d < 0.25) { return mix(0.9, 0.32, d / 0.25); }
    if (d < 0.6) { return mix(0.32, 0.07, (d - 0.25) / 0.35); }
    return mix(0.07, 0.0, (d - 0.6) / 0.4);
}

fragment float4 fieldFragment(
    VertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(0)]]
) {
    float alpha = in.color.a;

    if (in.kind == kindSprite) {
        constexpr sampler flowers(filter::linear, address::clamp_to_edge);

        // Local -1…1 into the slot's corner of the atlas, held a texel short
        // of the edges so linear filtering cannot reach into the neighbour.
        const float2 within = clamp(in.uv * 0.5 + 0.5, 0.0, 1.0);
        const float2 grid = float2(kAtlasColumns, kAtlasRows);
        const float2 cell = float2(1.0) / grid;
        const float2 corner = float2(in.slot % kAtlasColumns, in.slot / kAtlasColumns) * cell;
        const float2 inset = 1.0 / float2(atlas.get_width(), atlas.get_height());
        const float2 uv = corner + clamp(within * cell, inset, cell - inset);

        // Premultiplied, so the colour wave has to be premultiplied too
        // before it can be mixed in.
        const float4 texel = atlas.sample(flowers, uv);
        const float3 wash = in.color.rgb * texel.a;
        return float4(mix(texel.rgb, wash, in.tint) * alpha, texel.a * alpha);
    }

    if (in.kind == kindDot) {
        const float d = length(in.uv);
        // One pixel of feather, in whatever the dot's size works out to on
        // screen — the same edge a filled arc on a canvas gets.
        const float feather = fwidth(d);
        alpha *= 1.0 - smoothstep(1.0 - feather, 1.0, d);
    } else if (in.kind == kindGlow) {
        alpha *= haloAlpha(length(in.uv));
    } else if (in.kind == kindOutline) {
        // Keep the ring one point wide inside the quad's edge, and nothing
        // else — the same pixels `strokeRect` would light.
        const float2 fromEdge = (float2(1.0) - abs(in.uv)) * in.halfSize;
        const float d = min(fromEdge.x, fromEdge.y);
        const float feather = fwidth(d);
        alpha *= 1.0 - smoothstep(kOutlineWidth - feather, kOutlineWidth + feather, d);
    } else {
        // A round-capped line: distance to the segment running along local
        // x, and a linear fade from the dot to the tip.
        const float2 point = in.uv * in.halfSize;
        const float halfLength = max(in.halfSize.x - in.halfSize.y, 0.0);
        const float2 toSegment = float2(max(abs(point.x) - halfLength, 0.0), point.y);
        const float d = length(toSegment) / max(in.halfSize.y, 1e-4);
        const float feather = fwidth(d);
        const float across = 1.0 - smoothstep(1.0 - feather, 1.0, d);

        const float along = clamp(point.x / max(in.halfSize.x, 1e-4) * 0.5 + 0.5, 0.0, 1.0);
        alpha *= (1.0 - along) * across;
    }

    // Not premultiplied: the pipeline blends with source-alpha against one,
    // which is what `lighter` does.
    return float4(in.color.rgb, alpha);
}
