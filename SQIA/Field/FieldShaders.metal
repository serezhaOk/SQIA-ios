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
    /// The level the outline is drawn at.
    float edge;
    /// How wide that outline is, in pixels.
    float softness;
    /// Rings per unit of intensity, how fast they travel, how far they push.
    float rippleFrequency;
    float rippleSpeed;
    float rippleAmplitude;
    /// Above zero, the ramp is quantised into this many bands — the stepped
    /// contour look, off by default.
    float bands;
};

/// A ramp, read from the stops the tuning panel is holding rather than
/// written in here. The look is somebody's decision, taken while watching
/// the screen; the shader's job is to interpolate it.
///
/// Each stop is a colour in rgb and its place along the ramp in w.
static float3 rampAt(constant float4 *stops, uint count, float t) {
    float3 out = stops[0].rgb;
    for (uint i = 1; i < count; i++) {
        out = mix(out, stops[i].rgb, smoothstep(stops[i - 1].w, stops[i].w, t));
    }
    return out;
}

/// How many stops each ramp carries. `FieldTuning` says the same thing on
/// the other side, and the two have to agree.
constant uint kRestStops = 5;
constant uint kHeatStops = 8;

fragment float4 heatFragment(
    ScreenOut in [[stage_in]],
    texture2d<float> field [[texture(0)]],
    constant HeatUniforms &u [[buffer(0)]],
    constant float4 *stops [[buffer(1)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    const float2 sum = field.sample(linearClamp, in.uv).rg;

    const float v = sum.x;

    // How much the sum changes across one pixel, which is what turns a
    // level into an edge of a chosen width. Taken here, before anything can
    // discard: a derivative is worked out across a quad of neighbouring
    // fragments, and it needs all four of them still running.
    const float band = max(fwidth(v) * u.softness, 1e-5);
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
    // Drawn, and sounding. The rest ramp comes first in the buffer and the
    // heat ramp after it.
    const float3 rgb = mix(
        rampAt(stops, kRestStops, t),
        rampAt(stops + kRestStops, kHeatStops, t),
        energy);

    // The outline is a contour through the sum, and its width is set in
    // pixels rather than in field values. That difference is the whole
    // reason a drawn note used to look soft while a struck one looked
    // sharp: the old fade ran from nothing up to `edge`, so a shape whose
    // peak barely cleared the level was almost all fade, and one that
    // towered over it was a plateau with a thin fringe — the same rule
    // giving opposite results either side of it. A contour cannot tell them
    // apart. It is drawn where the sum crosses the level and it is exactly
    // as sharp there as `softness` says, whether one note made it or six
    // did.
    const float alpha = smoothstep(u.edge - band, u.edge + band, v);
    if (alpha <= 0.0) { discard_fragment(); }
    return float4(rgb, alpha);
}
