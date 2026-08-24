// Drawing the field.
//
// Two ways of drawing live here, and the difference between them is the
// whole point.
//
// The dot field draws each primitive on its own: every one is the same unit
// quad, oriented and sized per instance and given its shape by the fragment
// shader — a dot is a filled circle, a halo is the web's radial gradient
// written out as a curve, a streak is a capsule that fades along its length.
//
// The heat field cannot work that way. Two notes side by side have to come
// out as one shape with one outline, and nothing you do to two separately
// drawn circles will produce that: you have to know the total at a pixel
// before you can pick a colour for it. So sources are summed into a texture
// first, and a second pass reads the sum and maps it through the ramp. That
// is why a cluster burns and a lone note stays cool — heat is what the
// arithmetic of the sum makes it.

#include <metal_stdlib>
using namespace metal;

constant uint kindDot = 0;
constant uint kindGlow = 1;
constant uint kindStreak = 2;
constant uint kindOutline = 3;

/// A slot outline is a hairline, the way the web strokes one.
constant float kOutlineWidth = 1.0;

struct FieldInstance {
    float4 color;
    float2 center;
    float2 halfSize;
    /// Unit vector along the instance's local x. (1, 0) for anything round.
    float2 axis;
    uint kind;
    /// Source only: how hot the flash under it still is.
    float energy;
    uint padding;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float2 halfSize;
    float4 color;
    uint kind;
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

fragment float4 fieldFragment(VertexOut in [[stage_in]]) {
    float alpha = in.color.a;

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

    return float4(in.color.rgb, alpha);
}

// ------------------------------------------------------------------ heat --

struct SourceOut {
    float4 position [[position]];
    float2 uv;
    /// How much this source contributes at its middle.
    float weight;
    /// How hot the flash under it still is.
    float energy;
};

vertex SourceOut sourceVertex(
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
    const float2 point = instance.center + local * instance.halfSize;

    SourceOut out;
    out.position = float4(
        point.x / viewport.x * 2.0 - 1.0,
        1.0 - point.y / viewport.y * 2.0,
        0.0,
        1.0);
    out.uv = local;
    out.weight = instance.color.a;
    out.energy = instance.energy;
    return out;
}

/// The falloff, and the reason blobs join rather than overlap.
///
/// `(1 - r²)³` reaches zero smoothly at the rim and has no tail beyond it, so
/// a sum of them has no seams where one source's support ends — which is what
/// a contour drawn through the sum needs if it is to close around two sources
/// as one curve.
fragment float2 sourceFragment(SourceOut in [[stage_in]]) {
    const float r2 = dot(in.uv, in.uv);
    if (r2 >= 1.0) { return float2(0.0); }
    const float k = 1.0 - r2;
    const float falloff = k * k * k;

    const float here = in.weight * falloff;
    // Two channels: the sum itself, and the flash energy weighted by the
    // same falloff. Dividing one by the other at colouring time gives the
    // energy of whichever source dominates a pixel — so a struck blob
    // ripples and the quiet one beside it does not, even after the two have
    // merged into one shape.
    return float2(here, here * in.energy);
}

struct ScreenOut {
    float4 position [[position]];
    float2 uv;
};

vertex ScreenOut heatVertex(uint vertexID [[vertex_id]]) {
    // One triangle covering the screen: cheaper than two, and no seam down
    // the diagonal.
    const float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    const float2 p = corners[vertexID];

    ScreenOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = float2(p.x * 0.5 + 0.5, 1.0 - (p.y * 0.5 + 0.5));
    return out;
}

struct HeatUniforms {
    /// Seconds, for the ripple.
    float time;
    /// How much of the ramp the sum is stretched across.
    float gain;
    /// Below this the field dissolves into the ground.
    float edge;
    /// Rings per unit of intensity, how fast they travel, how far they push.
    float rippleFrequency;
    float rippleSpeed;
    float rippleAmplitude;
    /// Above zero, the ramp is quantised into this many bands — the stepped
    /// contour look, off by default.
    float bands;
    float padding;
};

/// What a note looks like when it is only drawn: brighter where the sum is
/// thicker. This is the field at rest, and most of what is on screen most of
/// the time.
static float3 restRamp(float t) {
    const float3 colors[5] = {
        float3(0.30, 0.22, 0.05),  // the faintest edge, on its way out
        float3(0.66, 0.48, 0.07),
        float3(0.90, 0.72, 0.12),
        float3(0.99, 0.88, 0.30),
        float3(1.00, 0.97, 0.74),  // the core
    };
    const float stops[5] = { 0.0, 0.30, 0.55, 0.78, 1.0 };

    float3 out = colors[0];
    for (uint i = 1; i < 5; i++) {
        out = mix(out, colors[i], smoothstep(stops[i - 1], stops[i], t));
    }
    return out;
}

/// What a note looks like while it is sounding: a lone source is a cool
/// speck, a cluster burns. Kept from the heat map — this is the reading the
/// field is actually taking, and the green is what it looks like between
/// readings.
static float3 heatRamp(float t) {
    const float3 colors[8] = {
        float3(0.36, 0.52, 0.86),  // the faintest edge, on its way out
        float3(0.20, 0.38, 0.83),  // blue
        float3(0.42, 0.68, 0.90),  // lighter blue
        float3(0.86, 0.93, 0.95),  // the pale turn
        float3(0.99, 0.93, 0.62),  // pale yellow
        float3(0.99, 0.80, 0.20),  // yellow
        float3(0.96, 0.52, 0.12),  // orange
        float3(0.87, 0.16, 0.10),  // the core
    };
    const float stops[8] = { 0.0, 0.22, 0.42, 0.55, 0.66, 0.78, 0.89, 1.0 };

    float3 out = colors[0];
    for (uint i = 1; i < 8; i++) {
        out = mix(out, colors[i], smoothstep(stops[i - 1], stops[i], t));
    }
    return out;
}

fragment float4 heatFragment(
    ScreenOut in [[stage_in]],
    texture2d<float> field [[texture(0)]],
    constant HeatUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    const float2 sum = field.sample(linearClamp, in.uv).rg;

    const float v = sum.x;
    if (v <= 0.0) { discard_fragment(); }

    // The energy of whatever dominates here, not the total — a hot blob next
    // to a cold one must not drag the cold one's colour with it.
    const float energy = clamp(sum.y / max(v, 1e-4), 0.0, 1.0);

    // Intensity falls off outward, so a wave in intensity travels outward
    // too: the colour leaves the core and spreads, rather than the whole
    // shape flashing at once.
    const float ripple =
        sin(v * u.rippleFrequency - u.time * u.rippleSpeed) * u.rippleAmplitude * energy;

    float t = clamp(v * u.gain + ripple, 0.0, 1.0);
    if (u.bands > 0.5) {
        t = floor(t * u.bands) / max(u.bands - 1.0, 1.0);
    }

    // Green at rest, and the heat ramp for as long as the note is sounding.
    // The crossfade is the same per-pixel energy the ripple uses, so it
    // follows the flash out of the blob it landed in and leaves the quiet
    // shapes beside it green.
    const float3 rgb = mix(restRamp(t), heatRamp(t), energy);

    // Dissolve into the ground at the bottom of the ramp rather than ending
    // on a visible edge.
    const float alpha = smoothstep(0.0, u.edge, v);
    return float4(rgb, alpha);
}
