// The panel's value type, and the two things about it that can go wrong
// quietly: a colour typed in and not taken, and a tuning that never reaches
// the drawing.

import Testing

@testable import SQIACore

@Suite("Field tuning")
struct FieldTuningTests {
    @Test("A colour survives being written down and typed back")
    func hexRoundTrip() {
        let colour = RGB(198, 158, 48)
        #expect(colour.hex == "C69E30")
        #expect(RGB(hex: colour.hex) == colour)
        #expect(RGB(hex: "#C69E30") == colour)
        #expect(RGB(hex: " c69e30 ") == colour)
    }

    /// A field that took half-typed values would jump somewhere on the way
    /// to the colour being aimed at.
    @Test("Half a hex is not a colour")
    func partialHexIsRejected() {
        #expect(RGB(hex: "C69E3") == nil)
        #expect(RGB(hex: "C69E301") == nil)
        #expect(RGB(hex: "") == nil)
        #expect(RGB(hex: "ZZZZZZ") == nil)
    }

    @Test("The whole set can be written out and read back")
    func jsonRoundTrip() throws {
        var tuning = FieldTuning.current
        tuning.gain = 0.41
        tuning.rest[2].color = RGB(10, 20, 30)
        tuning.returnSeconds = 2.5

        let restored = try #require(FieldTuning.decoded(from: tuning.json))
        #expect(restored == tuning)
        #expect(!restored.isDefault)
        #expect(FieldTuning.current.isDefault)
    }

    /// The taper is read off the tuning rather than written into the
    /// geometry, so this is the wire between the panel and the picture.
    @Test("The taper comes from the tuning")
    func taperFollowsTheTuning() {
        var flat = FieldTuning.current
        flat.rimScale = 1
        flat.centreLift = 0
        let style = FieldStyle(lensK: 0, swell: true, heat: true, tuning: flat)
        let layout = Field.layout(x: 0, y: 0, width: 393, height: 700, style: style)

        // Nothing tapers: the corner and the middle measure the same.
        let corner = Field.warpScale(x: layout.ox, y: layout.oy, in: layout)
        let middle = Field.warpScale(x: layout.cx, y: layout.cy, in: layout)
        #expect(corner == 1)
        #expect(middle == 1)
    }

    /// The web's field is not the panel's to move.
    @Test("The classic style keeps the web's taper")
    func classicIsUntouched() {
        let layout = Field.layout(x: 0, y: 0, width: 375, height: 600)
        let middle = Field.warpScale(x: layout.cx, y: layout.cy, in: layout)
        #expect(abs(middle - (0.72 + 0.62)) < 1e-12)
    }

    @Test("Both ramps carry the number of stops the shader walks")
    func rampsAreTheLengthTheShaderExpects() {
        #expect(FieldTuning.current.rest.count == FieldTuning.restStops)
        #expect(FieldTuning.current.heat.count == FieldTuning.heatStops)
        // In order, or the interpolation between them runs backwards.
        #expect(zip(FieldTuning.current.rest, FieldTuning.current.rest.dropFirst())
            .allSatisfy { $0.at < $1.at })
        #expect(zip(FieldTuning.current.heat, FieldTuning.current.heat.dropFirst())
            .allSatisfy { $0.at < $1.at })
    }
}
