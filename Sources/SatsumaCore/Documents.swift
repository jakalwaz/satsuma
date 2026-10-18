import AppKit
import PDFKit

extension Converter {
    // MARK: PDF in

    static func convertPDF(_ src: URL, to ext: String) throws -> [URL] {
        guard let doc = PDFDocument(url: src), !doc.isLocked else { throw ConvertError.unreadable }
        if ext == "jpg" || ext == "png" { return try renderPages(doc, of: src, ext: ext) }

        let text = NSMutableAttributedString()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i)?.attributedString else { continue }
            if text.length > 0 { text.append(NSAttributedString(string: "\n")) }
            text.append(page)
        }
        guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConvertError.noText }
        let out = Formats.outputURL(for: src, ext: ext)
        try writeDocument(text, to: out, ext: ext)
        return [out]
    }

    /// Every page at 300 DPI: `name.ext` for one page, `name-1.ext`, `name-2.ext`… for more.
    static func renderPages(_ doc: PDFDocument, of src: URL, ext: String) throws -> [URL] {
        let scale: CGFloat = 300 / 72
        let dir = src.deletingLastPathComponent(), base = src.deletingPathExtension().lastPathComponent
        var outputs: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let turned = page.rotation % 180 != 0
            let width = Int(((turned ? box.height : box.width) * scale).rounded())
            let height = Int(((turned ? box.width : box.height) * scale).rounded())
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { throw ConvertError.encodeFailed }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx) // applies the page's rotation and box origin
            guard let image = ctx.makeImage() else { throw ConvertError.encodeFailed }

            let name = doc.pageCount == 1 ? base : "\(base)-\(i + 1)"
            let out = Formats.outputURL(for: dir.appendingPathComponent(name).appendingPathExtension("pdf"), ext: ext)
            try writeImage(image, to: out, ext: ext, properties: [:])
            outputs.append(out)
        }
        return outputs
    }

    // MARK: Image → PDF

    static func imageToPDF(_ src: URL, to out: URL) throws {
        guard let image = NSImage(contentsOf: src), let page = PDFPage(image: image) else { throw ConvertError.unreadable }
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        guard doc.write(to: out) else { throw ConvertError.encodeFailed }
    }

    // MARK: Documents (AppKit text system)

    static let readTypes: [String: NSAttributedString.DocumentType] = [
        "docx": .officeOpenXML, "doc": .docFormat, "rtf": .rtf, "rtfd": .rtfd, "odt": .openDocument,
        "html": .html, "htm": .html, "webarchive": .webArchive, "txt": .plain, "md": .plain, "markdown": .plain,
    ]
    static let writeTypes: [String: NSAttributedString.DocumentType] = [
        "docx": .officeOpenXML, "rtf": .rtf, "odt": .openDocument, "html": .html, "txt": .plain,
    ]

    static func convertDocument(_ src: URL, to out: URL, ext: String) throws {
        try writeDocument(try readDocument(src), to: out, ext: ext)
    }

    static func readDocument(_ src: URL) throws -> NSAttributedString {
        let type = readTypes[src.pathExtension.lowercased()] ?? .plain
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        if type == .plain { options[.characterEncoding] = String.Encoding.utf8.rawValue }
        let read = { try NSAttributedString(url: src, options: options, documentAttributes: nil) }
        // HTML/webarchive import goes through WebKit, which is main-thread only.
        if (type == .html || type == .webArchive) && !Thread.isMainThread { return try DispatchQueue.main.sync(execute: read) }
        return try read()
    }

    static func writeDocument(_ text: NSAttributedString, to out: URL, ext: String) throws {
        if ext == "pdf" { return try writePDF(text, to: out) }
        guard let type = writeTypes[ext] else { throw ConvertError.encodeFailed }
        var attrs: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: type]
        if type == .plain { attrs[.characterEncoding] = String.Encoding.utf8.rawValue }
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attrs)
        try data.write(to: out, options: .withoutOverwriting)
    }

    /// Paginates onto US Letter pages with 1-inch margins.
    static func writePDF(_ text: NSAttributedString, to out: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 72
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: CGSize(width: mediaBox.width - 2 * margin, height: mediaBox.height - 2 * margin))
            layout.addTextContainer(container)
            // Nothing fit (e.g. an attachment taller than a page): stop instead of adding pages forever.
            if !containers.isEmpty && layout.glyphRange(for: container).length == 0 {
                layout.removeTextContainer(at: containers.count)
                break
            }
            containers.append(container)
        } while NSMaxRange(layout.glyphRange(for: containers.last!)) < layout.numberOfGlyphs

        guard let ctx = CGContext(out as CFURL, mediaBox: &mediaBox, nil) else { throw ConvertError.encodeFailed }
        for container in containers {
            ctx.beginPDFPage(nil)
            ctx.translateBy(x: 0, y: mediaBox.height) // AppKit text draws top-down
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let range = layout.glyphRange(for: container)
            let origin = CGPoint(x: margin, y: margin)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}
