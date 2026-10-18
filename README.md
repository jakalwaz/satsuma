```
 .-.-.
( -+- )  satsuma
 '-'-'
```

A zero-click file converter for macOS. Drag a file in Finder, tap **Shift**, and drop it on a format in the wheel that appears under your pointer. The converted copy is saved next to the original. Everything runs locally.

## Formats

| Input | Converts to |
|---|---|
| Images: JPG, PNG, HEIC, TIFF, BMP, GIF, WebP, AVIF | JPEG, PNG, HEIC, TIFF, BMP, GIF, PDF |
| Video: MP4, MOV, MKV, WebM, AVI, WMV, FLV, MPG, 3GP, TS | MP4, MOV, MKV, WebM, GIF, MP3 |
| Audio: MP3, M4A, AAC, WAV, FLAC, OGG, Opus, AIFF, WMA, CAF | MP3, M4A, WAV, FLAC, AIFF, OGG, Opus |
| PDF | JPEG/PNG (every page, 300 DPI), DOCX, TXT, RTF, HTML |
| Documents: DOCX, DOC, RTF, RTFD, ODT, HTML, webarchive, TXT, Markdown | PDF, DOCX, RTF, ODT, HTML, TXT |

Images, PDFs and documents use Apple frameworks (ImageIO, PDFKit, the AppKit text system). Video and audio use `ffmpeg`, with hardware H.264 encoding via VideoToolbox.

## Requirements

- macOS 13 or later
- Xcode command-line tools (Swift 5.10+)
- `ffmpeg` for video and audio: `brew install ffmpeg`

## Build and run

```sh
./bundle.sh
open build/Satsuma.app
```

Satsuma lives in the menu bar. Run the tests with `swift test`.

## Using it

1. Start dragging one or more files in Finder.
2. While still dragging, tap Shift.
3. Drop on a wedge. Escape cancels; dropping in the centre does nothing.

Results never overwrite anything: `photo.jpg` becomes `photo 2.jpg` if needed.

## Permissions

macOS asks once per protected folder (Desktop, Documents, Downloads). To never be asked, choose **Allow All Folders (Full Disk Access)…** from the menu and add Satsuma. Ad-hoc signed builds lose these grants on every rebuild; if you have an Apple Development certificate, `bundle.sh` signs with it so grants persist.

## How it works

- A 10 Hz timer reads the mouse button, modifier keys and the system drag pasteboard's change count. No Accessibility or Input Monitoring permission is needed.
- On a Shift tap during a file drag, a borderless non-activating panel at pop-up-menu level opens under the pointer. The wheel is a drop target that picks the wedge by angle.
- Conversions run off the main thread; Finder reveals the results.
