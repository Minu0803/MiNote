# MiNote

iPad-first handwriting notes, built to keep its document format portable across platforms.

## Implemented: local library, pages, writing, lasso movement, multiple PDFs and editable backups

The app opens a local library. Create a note, open its A4 page, and write with Pencil or, by choice, a finger. It includes pen and highlighter tools, stroke erasing, color and width controls, undo and redo, zoom, autosave, save retry and restoration after relaunch.

Use **올가미** to select whole strokes on paper or PDF, then drag inside the selection to translate them in page coordinates. Selection count and **선택 해제** are available. Drag previews leave the actual ink untouched until release; cancellation, zero movement, zoom and rotation do not edit the document. Selection intersects the interpolated stroke centre line, including the lasso boundary, rather than the brush's outer edge. Native ink and movements share the production canvas's explicit UndoManager history, including final canvas capture and guarded system Undo/Redo. IDs and source PDFs survive saving, reopening, editable backups and independent JSON edits. See [M2-A results](docs/milestones/2026-10-04-m2-a-lasso-move.md).

Create and rename notes and folders, move them into nested folders, view recent changes, and send notes to the trash or restore them. Each note keeps independent ink, pages and PDF assets. Closing the editor flushes its latest ink before returning to the library; save failures retain that editor. Existing single-note installations migrate automatically while their original files remain intact. Same-name folders have consistent disambiguated paths. See [the library format](docs/format/library-v1.md).
Use **PDF 가져오기** to select a PDF from Files. MiNote keeps the original pages and inserts each PDF after the selected page. Several PDFs, including files with the same name, retain separate immutable assets. Each page keeps its own editable ink, and reopening the app restores the last selected page. PDF crop boxes and 0/90/180/270-degree rotation use the same document coordinates for display and export.

Use **PDF 내보내기** to save the latest ink, generate a separate PDF, inspect it in QuickLook and open the system share sheet. Export keeps source text and vector page content while flattening handwriting as an image, up to 216 dpi and 4,096 pixels per side. Forms and source annotations are flattened; some links may not survive. The original PDF asset is never replaced. The exported PDF is for distribution; editable strokes remain in MiNote's JSON document.

The page manager adds blank, ruled or grid A4 pages, duplicates and reorders pages, filters bookmarks, and restores deleted pages. The last active page cannot be deleted. Duplicated PDF pages share their immutable source while keeping independent editable ink and IDs. Screen, thumbnails and PDF output use the same paper geometry.

Use **편집 원본 백업** and the system **Save to Files** action to keep an editable `.minote` copy. Restore it from the library with **백업에서 새 노트 복원**, or open it from Files. Restoration adds a new note; an existing document ID gets a new document UUID without changing page, stroke or asset IDs. The archive keeps ink, page order, paper, bookmarks, retained deleted pages and every registered source PDF. Undo history, thumbnails and folder structure are excluded. The app checks archive integrity and PDF geometry before adding the note, and offers progress and cancellation. See [the backup format](docs/format/backup-v1.md).

**저장 공간 정리** shows eligible files and protection reasons before confirmation. It preserves PDF references in both the current document and its valid recovery copy, and skips uncertain or unsupported files. Deleted pages and trashed notes can be permanently removed after confirmation. Interrupted note removal resumes from a journal; an active editor cannot be purged. PDF and backup preview/share consumers hold separate output leases.

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
node Tools/PortableInk/roundtrip.mjs --lasso --check
swift test --package-path Packages/MiNoteCore

xcodebuild -project MiNote.xcodeproj -scheme MiNote \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6' \
  test CODE_SIGNING_ALLOWED=NO
```

The Xcode scheme covers PencilKit conversion, PDF coordinates and raster placement, import/export failures, edit sessions, zoom rendering, backup validation/cancellation, output leases and a 500-page fixture. UI tests exercise writing, undo/redo, Files import and backup save/restore, page navigation, rotation, permanent-removal confirmation, relaunch, export preview and the share sheet. Run on both iPadOS 18.6 and 26.4. Actual results and logs are recorded in [docs/PROGRESS.md](docs/PROGRESS.md).

M1-C passed 31 Node tests and both v2/v3 fixture checks, 78 core tests and 64 app unit tests on each OS. The 26.4 whole run passed 7 regular UI tests and skipped 2 fixture-only tests. The final 18.6 combined command exited 65 after one Save to Files UI failure; its 64 app tests and 6 other UI tests passed. The failed backup flow passed a focused rerun after waiting for the action to be enabled and hittable. Both fixture-only migration and actual Files backup transfer passed separately on a fresh isolated installation for each OS, with IDs/metadata and original bytes verified. See [fixture setup](Tools/LibraryTests/README.md), [M1-C results](docs/milestones/2026-10-04-m1-c-backup-and-cleanup.md) and [the actual restored-note screen](docs/assets/m1c-restored-backup-ink.png). Failed invocations remain recorded separately.

M2-A passed 87 core tests, 32 Node tests and all three fixture checks. Both 18.6 and 26.4 final whole runs passed 83 app tests and 9 regular UI tests with 2 fixture-only skips, plus the live saved-ink/PDF-hash observer on each OS. A fresh review found two history gaps, each reproduced and fixed with regression tests. The first pre-review 18.6 command failed PDF navigation; its focused diagnostic passed without reproducing the cause, and the corrected source passed both final whole runs. Actual input, read-only saved JSON and programmatic delegate regressions are recorded separately in [M2-A results](docs/milestones/2026-10-04-m2-a-lasso-move.md).

## Current limits

- Multiple PDFs per note, up to 1,000 active plus retained deleted pages and 500 MiB of registered PDF assets. Permanent page removal retains the previous valid recovery copy; its PDF references stay protected until backup rotation.
- Imports are limited to 100 MB, 500 pages and 2,000 points per page edge. Password-protected, truncated and unsupported files are rejected. These are conservative limits, not a real-device performance guarantee.
- Stroke identities are matched across the whole surviving order. If identical strokes leave more than one possible ID mapping, saving fails explicitly and retains both visible ink and the prior saved document. Stroke reordering is not supported yet.
- Undo history and selection start again when switching pages, restoring a backup or relaunching. Partial erasing, selected-stroke deletion/duplication, clipboard copy/paste, resize/rotation, text and images are future work.
- Export may normalize the raw PDF MediaBox origin. Visible crop geometry, rotation and ink placement are preserved; the source asset and its stored metadata stay unchanged.
- Backups use the stored-only ZIP32 format with a 640 MiB archive limit and 128 MiB document-JSON limit. General compressed ZIP, folder-wide backups and cloud synchronization are not supported.
- Known unused PDF assets and inactive registered outputs can be cleaned safely. Unknown files, invalid snapshots, interrupted restore staging and output leases left by process interruption remain protected; automatic ownership recovery is future work and disk usage may accumulate.
- Pencil latency, palm rejection, thermal behavior and large image-heavy PDFs need physical-device testing. The synthetic memory test does not establish those results.

## Roadmap

- **M0-A / M0-B / M0-C implemented:** Blank-page ink, safe local recovery, PDF import/export and independent portable-ink round-trip verification.
- **M1-A implemented:** Multiple notes, folders, trash/restore and safe switching between edit sessions.
- **M1-B implemented:** Page management, blank/ruled/grid paper, bookmarks, deleted-page recovery and multiple PDFs per note.
- **M1-C implemented:** Editable `.minote` backup/restore, confirmed permanent removal, journal recovery and safe file cleanup.
- **M2-A implemented:** Whole-stroke lasso selection/translation, unified native undo/redo, stable IDs and save/backup verification.
- **Next M2-B, plan only:** Selected-stroke deletion and same-page duplication. Clipboard copy/paste follows as a separate M2-B2 unit.
- **Later M2 units:** Text, images, title/folder and existing PDF-text search, then mixed-object portability.
- **M3:** Performance and real-device Pencil, palm and thermal checks.
- **Later:** Advanced editing, sync, collaboration and other platforms.

This is a local technical foundation, not the completed iPad product. Sync and other platform apps are not implemented. See [the next M2-B plan](docs/superpowers/plans/2026-10-04-m2-b-delete-and-duplicate.md) and [the product roadmap](docs/superpowers/specs/2026-09-26-minote-product-design.md).
