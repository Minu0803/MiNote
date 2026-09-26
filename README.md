# MiNote

iPad-first handwriting notes, built to keep its document format portable across platforms.

## M0-A: blank-page writing and local recovery

The first milestone opens one A4 page where you can write with Pencil or, by choice, a finger. It includes pen and highlighter tools, stroke erasing, color and width controls, undo and redo, zoom, autosave, save retry and restoration after relaunch.

The app keeps the pen input layer in PencilKit while the document itself uses versioned JSON. A completed edit is stored under the app's `Documents/MiNote` directory; the last known good document is retained for recovery. The `MiNoteCore` package contains the platform-independent note, page and stroke models, validation, JSON codec and serialized local store.

## Open the iPad app

1. Open `MiNote.xcodeproj` in Xcode 27.
2. Choose the shared `MiNote` scheme and an iPad simulator with iOS 18 or later.
3. Build and run. The simulator enables finger drawing by default. On an iPad, Pencil input is selected by default; the toolbar can enable finger drawing.

The app has no third-party package dependencies and targets iPadOS 18 or later.

## Verify

```sh
swift test --package-path Packages/MiNoteCore

xcodebuild -project MiNote.xcodeproj -scheme MiNote \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6' \
  test CODE_SIGNING_ALLOWED=NO
```

The Xcode test scheme covers PencilKit conversion, local edit sessions and UI writing, undo/redo and app relaunch. Testing on iOS 18.6 and 26.4 is part of M0-A.

## Roadmap

- **M0-B:** Import PDF, write over it and export a flattened or editable PDF.
- **M0-C:** Validate portable ink from another renderer.
- **M1:** Multiple notes, folders, pages and local recovery management.
- **M2:** Lasso, text, images and search.
- **M3:** Performance and real-device Pencil, palm and thermal checks.
- **Later:** Advanced editing, sync, collaboration and other platforms.

The current milestone does not import PDFs or sync data. Real Pencil latency, palm rejection and thermal behavior still need a physical iPad.
