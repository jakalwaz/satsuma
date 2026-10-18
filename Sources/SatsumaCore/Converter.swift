import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ConvertError: LocalizedError {
    case unreadable, encodeFailed, noText, ffmpegMissing, ffmpegFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Could not read the file."
        case .encodeFailed: "Could not write the converted file."
        case .noText: "No text found. The PDF may be scanned images."
        case .ffmpegMissing: "ffmpeg not found. Install it with `brew install ffmpeg`."
        case .ffmpegFailed(let log): "ffmpeg failed: \(log)"
        }
    }
}

public enum Converter {
    /// Bundled `Resources/ffmpeg` first, then Homebrew locations.
    public static func findFFmpeg(bundle: Bundle = .main) -> URL? {
        let candidates = [bundle.url(forResource: "ffmpeg", withExtension: nil)?.path,
                          "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Converts `src` and writes the results beside it (several for multi-page PDF → image).
    public static func convert(_ src: URL, to format: Format, category: FileCategory, ffmpeg: URL?) throws -> [URL] {
        if category == .pdf { return try convertPDF(src, to: format.ext) }
        let out = Formats.outputURL(for: src, ext: format.ext)
        switch category {
        case .image where format.ext == "pdf":
            try imageToPDF(src, to: out)
        case .image:
            try convertImage(src, to: out, ext: format.ext)
        case .video, .audio:
            guard let ffmpeg else { throw ConvertError.ffmpegMissing }
            try run(ffmpeg, ffmpegArgs(input: src, output: out, ext: format.ext), cleaningUp: out)
        case .document:
            try convertDocument(src, to: out, ext: format.ext)
        case .pdf:
            break // handled above
        }
        return [out]
    }

    // MARK: Images (ImageIO)

    static func convertImage(_ src: URL, to out: URL, ext: String) throws {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil), CGImageSourceGetCount(source) > 0
        else { throw ConvertError.unreadable }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard var image = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw ConvertError.unreadable }
        // Source properties carry orientation and EXIF across.
        let props = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
        // JPEG/BMP have no alpha; ImageIO would turn transparency black.
        if ["jpg", "bmp"].contains(ext), hasAlpha(image) { image = try flattenOnWhite(image) }
        try writeImage(image, to: out, ext: ext, properties: props)
    }

    static func writeImage(_ image: CGImage, to out: URL, ext: String, properties: [CFString: Any]) throws {
        var props = properties
        props[kCGImageDestinationLossyCompressionQuality] = 0.9
        guard let type = UTType(filenameExtension: ext)?.identifier,
              let dest = CGImageDestinationCreateWithURL(out as CFURL, type as CFString, 1, nil)
        else { throw ConvertError.encodeFailed }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out)
            throw ConvertError.encodeFailed
        }
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    static func flattenOnWhite(_ image: CGImage) throws -> CGImage {
        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ConvertError.encodeFailed }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        guard let flat = ctx.makeImage() else { throw ConvertError.encodeFailed }
        return flat
    }

    // MARK: Video / audio (ffmpeg)

    public static func ffmpegArgs(input: URL, output: URL, ext: String) -> [String] {
        let h264 = ["-c:v", "h264_videotoolbox", "-q:v", "65", "-c:a", "aac", "-b:a", "192k"]
        let codec: [String] = switch ext {
        case "mp4": h264 + ["-sn", "-movflags", "+faststart"]
        case "mov": h264 + ["-sn"]
        case "mkv": h264 + ["-c:s", "copy"]
        case "webm": ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-deadline", "good",
                      "-cpu-used", "4", "-c:a", "libopus", "-b:a", "128k", "-sn"]
        case "gif": ["-vf", "fps=12,scale='min(640,iw)':-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse",
                     "-loop", "0", "-an", "-sn"]
        case "mp3": ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case "m4a": ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case "wav": ["-vn", "-c:a", "pcm_s16le"]
        case "flac": ["-vn", "-c:a", "flac"]
        case "aiff": ["-vn", "-c:a", "pcm_s16be"]
        case "ogg": ["-vn", "-c:a", "libvorbis", "-q:a", "5"]
        case "opus": ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        default: []
        }
        // -n: never overwrite; paths are absolute, so they can't be read as flags.
        return ["-hide_banner", "-nostdin", "-loglevel", "error", "-n", "-i", input.path] + codec + [output.path]
    }

    static func run(_ tool: URL, _ args: [String], cleaningUp out: URL) throws {
        let p = Process()
        p.executableURL = tool
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        let log = err.fileHandleForReading.readDataToEndOfFile() // drain before wait, or a full pipe deadlocks
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: out)
            let text = String(decoding: log, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConvertError.ffmpegFailed(String(text.suffix(400)))
        }
    }
}
