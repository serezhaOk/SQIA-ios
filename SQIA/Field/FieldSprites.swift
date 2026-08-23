// The flower atlas.
//
// Twelve illustrations, one per grid column, packed 4x3 into a single
// texture by `tools/make-sprites.py` — which is also where they are scaled to
// a common size and put in an order that keeps neighbouring columns apart.
// Nothing here decides how they look; it loads what that produced.

import MetalKit
import UIKit

enum FieldSprites {
    /// Slots across and down, which the fragment shader has to agree with.
    static let columns = 4
    static let rows = 3

    /// Loads the atlas, or nil if it is missing — in which case the field
    /// draws no flowers rather than refusing to start.
    static func atlas(device: MTLDevice) -> MTLTexture? {
        guard
            let image = UIImage(named: "FlowerAtlas"),
            let cgImage = image.cgImage
        else { return nil }

        // The illustrations are flat colour, authored as they are meant to
        // appear, so the loader must not treat them as sRGB and linearise
        // them on the way in. Mipmaps because a field shrinks into a mixer
        // panel, where a flower lands on a fraction of the pixels it was
        // packed at.
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .generateMipmaps: true,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
        ]
        return try? MTKTextureLoader(device: device).newTexture(
            cgImage: cgImage, options: options)
    }

    /// One transparent texel, for the case where the atlas is not there. The
    /// field then draws nothing where a flower would have gone, rather than
    /// leaving the shader's texture slot empty.
    static func blank(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var clear: UInt32 = 0
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &clear,
            bytesPerRow: 4)
        return texture
    }
}
