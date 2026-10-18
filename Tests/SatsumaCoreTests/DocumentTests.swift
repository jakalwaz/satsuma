import AppKit
import PDFKit
import XCTest
@testable import SatsumaCore

final class DocumentTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func convert(_ src: URL, _ ext: String) throws -> [URL] {
        try Converter.convert(src, to: Format(ext, ext), category: Formats.category(of: src)!, ffmpeg: nil)
    }

    func testDocxToPDFPaginatesAndRoundTripsThroughText() throws {
        let body = (1...200).map { "Line \($0) of the Satsuma test document." }.joined(separator: "\n")
        let docx = dir.appendingPathComponent("notes.docx")
        try Converter.writeDocument(NSAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: 12)]),
                                    to: docx, ext: "docx")

        let pdf = try convert(docx, "pdf")[0]
        let doc = try XCTUnwrap(PDFDocument(url: pdf))
        XCTAssertGreaterThan(doc.pageCount, 1, "200 lines should span several pages")
        XCTAssertTrue(doc.string?.contains("Line 200 of the Satsuma") ?? false, "last line must not be dropped")

        let txt = try convert(pdf, "txt")[0]
        XCTAssertTrue(try String(contentsOf: txt, encoding: .utf8).contains("Line 1 of the Satsuma"))

        let back = try convert(pdf, "docx")[0]
        XCTAssertTrue(try Converter.readDocument(back).string.contains("Line 100"))

        let pages = try convert(pdf, "png")
        XCTAssertEqual(pages.count, doc.pageCount)
        XCTAssertEqual(pages[0].lastPathComponent, "notes-1.png")
        let img = try XCTUnwrap(NSImage(contentsOf: pages[0])?.representations.first)
        XCTAssertEqual(img.pixelsWide, 2550, "Letter width at 300 DPI")
    }

    func testRotatedPageRendersLandscape() throws {
        let pdfURL = dir.appendingPathComponent("turned.pdf")
        let doc = PDFDocument()
        let page = PDFPage(image: NSImage(size: NSSize(width: 100, height: 200), flipped: false) { _ in
            NSColor.red.setFill(); NSBezierPath.fill(NSRect(x: 0, y: 0, width: 100, height: 200)); return true
        })!
        page.rotation = 90
        doc.insert(page, at: 0)
        XCTAssertTrue(doc.write(to: pdfURL))
        let out = try convert(pdfURL, "jpg")
        XCTAssertEqual(out.map(\.lastPathComponent), ["turned.jpg"])
        let rep = try XCTUnwrap(NSImage(contentsOf: out[0])?.representations.first)
        XCTAssertGreaterThan(rep.pixelsWide, rep.pixelsHigh)
    }

    func testHTMLAndTextInputs() throws {
        let html = dir.appendingPathComponent("page.html")
        try "<h1>Hello</h1><p>from <b>Satsuma</b></p>".write(to: html, atomically: true, encoding: .utf8)
        let rtf = try convert(html, "rtf")[0]
        XCTAssertTrue(try Converter.readDocument(rtf).string.contains("Satsuma"))

        let md = dir.appendingPathComponent("readme.md")
        try "# Título ünïcode".write(to: md, atomically: true, encoding: .utf8)
        let odt = try convert(md, "odt")[0]
        XCTAssertTrue(try Converter.readDocument(odt).string.contains("Título ünïcode"))
    }

    func testImageToPDF() throws {
        let png = dir.appendingPathComponent("pic.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: png)
        let pdf = try convert(png, "pdf")[0]
        XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 1)
    }

    func testScannedPDFWithoutTextReportsIt() throws {
        let png = dir.appendingPathComponent("scan.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: png)
        let pdf = try convert(png, "pdf")[0]
        XCTAssertThrowsError(try convert(pdf, "txt")) { XCTAssertEqual($0.localizedDescription, ConvertError.noText.localizedDescription) }
    }
}
