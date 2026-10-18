import Foundation

public enum FileCategory: Equatable { case image, video, audio, pdf, document }

public struct Format: Hashable {
    public let label: String
    public let ext: String
    public init(_ label: String, _ ext: String) { self.label = label; self.ext = ext }
}

public enum Formats {
    static let imageIn: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp", "avif"]
    static let videoIn: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "mpg", "mpeg", "3gp", "ts"]
    static let audioIn: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "oga", "opus", "aif", "aiff", "wma", "caf"]
    static let documentIn: Set<String> = ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "webarchive", "txt", "md", "markdown"]

    static let imageOut = [Format("JPEG", "jpg"), Format("PNG", "png"), Format("HEIC", "heic"),
                           Format("TIFF", "tiff"), Format("BMP", "bmp"), Format("GIF", "gif"), Format("PDF", "pdf")]
    static let videoOut = [Format("MP4", "mp4"), Format("MOV", "mov"), Format("MKV", "mkv"),
                           Format("WebM", "webm"), Format("GIF", "gif"), Format("MP3", "mp3")]
    static let audioOut = [Format("MP3", "mp3"), Format("M4A", "m4a"), Format("WAV", "wav"), Format("FLAC", "flac"),
                           Format("AIFF", "aiff"), Format("OGG", "ogg"), Format("Opus", "opus")]
    static let pdfOut = [Format("JPEG", "jpg"), Format("PNG", "png"), Format("DOCX", "docx"),
                         Format("TXT", "txt"), Format("RTF", "rtf"), Format("HTML", "html")]
    static let documentOut = [Format("PDF", "pdf"), Format("DOCX", "docx"), Format("RTF", "rtf"),
                              Format("ODT", "odt"), Format("HTML", "html"), Format("TXT", "txt")]

    static let aliases = ["jpeg": "jpg", "tif": "tiff", "aif": "aiff", "heif": "heic", "htm": "html"]

    public static func category(of url: URL) -> FileCategory? {
        let e = url.pathExtension.lowercased()
        if imageIn.contains(e) { return .image }
        if videoIn.contains(e) { return .video }
        if audioIn.contains(e) { return .audio }
        if e == "pdf" { return .pdf }
        if documentIn.contains(e) { return .document }
        return nil
    }

    /// Output formats for a category, minus the source's own format.
    public static func targets(for category: FileCategory, sourceExt: String) -> [Format] {
        let list = switch category { case .image: imageOut; case .video: videoOut; case .audio: audioOut
                   case .pdf: pdfOut; case .document: documentOut }
        let src = sourceExt.lowercased()
        return list.filter { $0.ext != (aliases[src] ?? src) }
    }

    /// `dir/name.ext`, or `dir/name 2.ext`, `name 3.ext`… so nothing is overwritten.
    public static func outputURL(for src: URL, ext: String) -> URL {
        let dir = src.deletingLastPathComponent(), base = src.deletingPathExtension().lastPathComponent
        var url = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
