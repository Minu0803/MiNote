# MiNote

iPad-first handwriting notes, built to keep its document format portable across platforms.

## Implemented: local library, pages, writing, multiple PDFs and recovery

The app opens a local library. Create a note, open its A4 page, and write with Pencil or, by choice, a finger. It includes pen and highlighter tools, stroke erasing, color and width controls, undo and redo, zoom, autosave, save retry and restoration after relaunch.


Create and rename notes and folders, move them into nested folders, view recent changes, and send notes to the trash or restore them. Each note keeps independent ink, pages and PDF assets. Closing the editor flushes its latest ink before returning to the library; save failures retain that editor. Existing single-note installations migrate automatically while their original files remain intact. Same-name folders have consistent disambiguated paths. See [the library format](docs/format/library-v1.md).
Use **PDF 가져오기** to select a PDF from Files. MiNote keeps the original pages and inserts each PDF after the selected page. Several PDFs, including files with the same name, retain separate immutable assets. Each page keeps its own editable ink, and reopening the app restores the last selected page. PDF crop boxes and 0/90/180/270-degree rotation use the same document coordinates for display and export.

Use **PDF 내보내기** to save the latest ink, generate a separate PDF, inspect it in QuickLook and open the system share sheet. Export keeps source text and vector page content while flattening handwriting as an image, up to 216 dpi and 4,096 pixels per side. Forms and source annotations are flattened; some links may not survive. The original PDF asset is never replaced. The exported PDF is for distribution; editable strokes remain in MiNote's JSON document.

The page manager adds blank, ruled or grid A4 pages, duplicates and reorders pages, filters bookmarks, and restores deleted pages. The last active page cannot be deleted. Duplicated PDF pages share their immutable source while keeping independent editable ink and IDs. Screen, thumbnails and PDF output use the same paper geometry.

The app keeps the pen input layer in PencilKit while the document uses schema-v3 JSON. A completed edit is stored under `Documents/MiNote/notes/<UUID>`; the last known good document is retained for recovery. PDF assets use immutable UUID-based paths. Schema-v1/v2 notes migrate without losing IDs or ink, and their original bytes are retained in the backup. See [the v3 document contract](docs/format/document-v3.md). The Foundation-only `MiNoteCore` package contains note, page, stroke and asset models, validation, the JSON codec and serialized local store.

Import and export lock editing, including undo and redo. One visible PDF page and canvas are reused; zoom completion rerenders the background within a 4,096-pixel limit. Missing PDF assets, invalid documents and unsupported versions show an error instead of replacing a note with an empty document.

## Open the iPad app

1. Open `MiNote.xcodeproj` in Xcode 27.
2. Choose the shared `MiNote` scheme and an iPad simulator with iOS 18 or later.
3. Build and run, create a note and open it. The simulator enables finger drawing by default. On an iPad, Pencil input is selected by default; the toolbar can enable finger drawing.

The app has no third-party package dependencies and targets iPadOS 18 or later.

## Portable ink lab

The dependency-free [PortableInk lab](Tools/PortableInk/README.md) reads schema-v2 and schema-v3 JSON and edits strokes by UUID in Canvas. Actual independent output is reconstructed, reedited, saved and reopened by iPad tests. The v3 round trip also preserves multiple PDF references, deleted pages, paper and bookmarks. See [the ink contract](docs/format/ink-v2.md) and [the v3 format](docs/format/document-v3.md) and [browser evidence](docs/assets/m0c-portable-ink.jpg). This is a test tool; other platform apps and a production JSON import UI remain future work.

## Verify

```sh
node --test Tools/PortableInk/*.test.mjs
node Tools/PortableInk/roundtrip.mjs --check
node Tools/PortableInk/roundtrip.mjs --v3 --check
swift test --package-path Packages/MiNoteCore

xcodebuild -project MiNote.xcodeproj -scheme MiNote \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6' \
  test CODE_SIGNING_ALLOWED=NO
```

The Xcode scheme covers PencilKit conversion, PDF coordinates and raster placement, import/export failures, edit sessions, zoom rendering and a 500-page fixture. UI tests exercise writing, undo/redo, Files import, page navigation, rotation, relaunch, export preview and the share sheet. Run on both iPadOS 18.6 and 26.4. Actual results and logs are recorded in [docs/PROGRESS.md](docs/PROGRESS.md).

The final M1-B run passed 31 Node tests, 60 core tests and, on each OS, 53 app unit tests and 5 regular UI tests. One fixture-only migration test is skipped in ordinary suites; it passed separately on a seeded isolated simulator for each OS, with raw legacy files verified unchanged. See [migration setup](Tools/LibraryTests/README.md), [the M1-B results](docs/milestones/2026-10-03-m1-b-pages-and-pdfs.md) and [the actual nine-page export preview](docs/assets/m1b-multi-page-export-preview.png).

## Current limits

- Multiple PDFs per note, up to 1,000 active plus retained deleted pages and 500 MiB of registered PDF assets. Deleted pages retain their data until later permanent-removal support.
- Imports are limited to 100 MB, 500 pages and 2,000 points per page edge. Password-protected, truncated and unsupported files are rejected. These are conservative limits, not a real-device performance guarantee.
- Stroke identities are matched across the whole surviving order. If identical strokes leave more than one possible ID mapping, saving fails explicitly and retains both visible ink and the prior saved document. Stroke reordering is not supported yet.
- Undo history starts again when switching pages. Partial erasing, selection, text and images are future work.
- Export may normalize the raw PDF MediaBox origin. Visible crop geometry, rotation and ink placement are preserved; the source asset and its stored metadata stay unchanged.
- Export temporary folders and interrupted-import orphan assets currently remain for later cleanup. Their lifetime management belongs to M1-C.
- Pencil latency, palm rejection, thermal behavior and large image-heavy PDFs need physical-device testing. The synthetic memory test does not establish those results.

## Roadmap

- **M0-A / M0-B / M0-C implemented:** Blank-page ink, safe local recovery, PDF import/export and independent portable-ink round-trip verification.
- **M1-A implemented:** Multiple notes, folders, trash/restore and safe switching between edit sessions.
- **M1-B implemented:** Page management, blank/ruled/grid paper, bookmarks, deleted-page recovery and multiple PDFs per note.
- **Next M1-C:** Editable `.minote` backup/restore, permanent removal and safe file cleanup.
- **M1:** Multiple notes, folders, pages and local recovery management.
- **M2:** Lasso, text, images and search.
- **M3:** Performance and real-device Pencil, palm and thermal checks.
- **Later:** Advanced editing, sync, collaboration and other platforms.

This is a local technical foundation, not the completed iPad product. Sync and other platform apps are not implemented. See [the next M1-C plan](docs/superpowers/plans/2026-10-03-m1-c-backup-and-cleanup.md) and [the product roadmap](docs/superpowers/specs/2026-09-26-minote-product-design.md).
