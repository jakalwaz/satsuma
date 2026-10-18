import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SatsumaCore

final class CoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testCategoriesAndTargets() {
        XCTAssertEqual(Formats.category(of: URL(fileURLWithPath: "/a/B.JPEG")), .image)
        XCTAssertEqual(Formats.category(of: URL(fileURLWithPath: "/a/b.mkv")), .video)
        XCTAssertEqual(Formats.category(of: URL(fileURLWithPath: "/a/b.flac")), .audio)
        XCTAssertNil(Formats.category(of: URL(fileURLWithPath: "/a/b.xyz")))
        XCTAssertFalse(Formats.targets(for: .image, sourceExt: "JPEG").contains { $0.ext == "jpg" })
        XCTAssertFalse(Formats.targets(for: .audio, sourceExt: "aif").contains { $0.ext == "aiff" })
        XCTAssertEqual(Formats.targets(for: .video, sourceExt: "avi").count, 6)
    }

    func testOutputNameNeverOverwrites() throws {
        let src = dir.appendingPathComponent("photo.png")
        XCTAssertEqual(Formats.outputURL(for: src, ext: "jpg").lastPathComponent, "photo.jpg")
        try Data().write(to: dir.appendingPathComponent("photo.jpg"))
        try Data().write(to: dir.appendingPathComponent("photo 2.jpg"))
        XCTAssertEqual(Formats.outputURL(for: src, ext: "jpg").lastPathComponent, "photo 3.jpg")
    }

    func testTransparentPNGToJPEGIsFlattenedOnWhite() throws {
        let src = dir.appendingPathComponent("clear.png")
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: 4, height: 4)) // fully transparent
        let dest = CGImageDestinationCreateWithURL(src as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let out = try Converter.convert(src, to: Format("JPEG", "jpg"), category: .image, ffmpeg: nil)[0]
        XCTAssertEqual(out.lastPathComponent, "clear.jpg")
        let source = CGImageSourceCreateWithURL(out as CFURL, nil)!
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let img = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        var px = [UInt8](repeating: 0, count: 4)
        let probe = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        probe.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(px[0], 240, "transparent area should become white, not black")
    }

    func testFFmpegVideoAndAudio() throws {
        let ffmpeg = try XCTUnwrap(Converter.findFFmpeg(), "ffmpeg not installed")
        let video = dir.appendingPathComponent("clip.mkv")
        try Converter.run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=24:duration=1",
                                   "-f", "lavfi", "-i", "sine=duration=1", "-c:v", "libx264", "-c:a", "aac", "-shortest", video.path],
                          cleaningUp: video)
        for ext in ["mp4", "webm", "gif", "mp3"] {
            let out = try Converter.convert(video, to: Format(ext, ext), category: .video, ffmpeg: ffmpeg)[0]
            let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int)
            XCTAssertGreaterThan(size, 0, ext)
        }
        let mp3 = dir.appendingPathComponent("clip.mp3")
        for ext in ["m4a", "wav", "flac", "aiff", "ogg", "opus"] {
            let out = try Converter.convert(mp3, to: Format(ext, ext), category: .audio, ffmpeg: ffmpeg)[0]
            XCTAssertTrue(FileManager.default.fileExists(atPath: out.path), ext)
        }
    }

    func testFFmpegFailureRemovesPartialOutput() throws {
        let ffmpeg = try XCTUnwrap(Converter.findFFmpeg())
        let bogus = dir.appendingPathComponent("broken.mp4")
        try Data("not a video".utf8).write(to: bogus)
        XCTAssertThrowsError(try Converter.convert(bogus, to: Format("MP3", "mp3"), category: .video, ffmpeg: ffmpeg))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("broken.mp3").path))
    }
}
