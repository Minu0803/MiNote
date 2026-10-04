# Isolated legacy migration UI check

`LibraryUITests.testLegacyMigrationInSeededSimulator` requires a freshly created,
empty simulator. The regular suite skips this fixture-specific check when the
fixture is absent; the library, ink and PDF UI flows still run. Run migration
separately on both supported test runtimes.

1. Create a simulator named `MiNote M1-B Migration <OS>` using `xcrun simctl create`.
2. Boot it and install the built `MiNote.app`. Do not launch the app yet.
3. Run `python3 Tools/LibraryTests/legacy_fixture.py <device-UUID>`.
4. Run the `MiNote` scheme with that destination and
   `-only-testing:MiNoteUITests/LibraryUITests/testLegacyMigrationInSeededSimulator`.
5. Boot it again if Xcode shut it down, then run
   `python3 Tools/LibraryTests/legacy_fixture.py <device-UUID> --verify`.

The seed helper refuses general-purpose simulator names and existing MiNote
folders. It copies the actual schema-v2 PencilKit/PDF fixture, retaining raw
primary and backup bytes. UI checks open the migrated ink and PDF, navigate,
close and relaunch. The final helper checks the original bytes, copied IDs/ink,
PDF bytes and updated revision. Core tests separately cover v1, corrupt input,
missing PDF and interrupted catalog writes. No real user's note is replaced.

M1-B verifier는 v2 raw 원본이 루트에 그대로 남고 새 본문만 v3로 정규화됐는지 검사한다. 기존 ID/ink/geometry에 source.assetID와 blank/false 기본값만 추가되며 pdfAssets/deletedPages를 확인한다. 이미 사용한 migration 기기의 MiNote data를 지우거나 reseed하지 않는다. 새 기기를 만든다. M1-A prefix도 helper의 안전 검사에는 계속 허용한다.

## Editable backup transfer check (M1-C)

Run `BackupUITests.testBackupExportViaFilesAndDuplicateRestore` in a regular
simulator after app tests have created the two PDF fixtures. It actually draws,
adds paper/bookmarks/retained deleted pages, imports both PDFs, saves through
UIKit **Save to Files**, restores a duplicate note, edits, undoes/redoes and
relaunches. Its log prints `MINOTE_BACKUP_FILE=Backup-<suffix>.minote`.

1. Preserve that actual file from the regular simulator's app `Documents`.
2. Create a **new** simulator named `MiNote M1-C Backup <OS>`, boot and install
   the built app without launching it.
3. Run `python3 Tools/LibraryTests/backup_fixture.py <device-UUID> <actual-Backup-file>`.
4. Run only `MiNoteUITests/BackupUITests/testBackupTransferIntoEmptyInstallation`.
5. Boot again if Xcode shut it down, then run the same helper with `--verify`.

The helper refuses general-purpose devices and existing library/transfer data.
It copies the actual archive bytes, not a fabricated JSON fixture. Verification
checks source/transfer SHA, document/page/stroke/asset IDs, both PDF bytes,
paper/bookmarks/deleted pages, new editable ink, Undo/Redo and relaunch. Regular
suites skip this empty-installation-only test. Do not erase or reseed previous
test devices. M1-C migration devices are also accepted by `legacy_fixture.py`.

## Actual lasso ink evidence (M2-A)

`python3 Tools/LibraryTests/lasso_evidence.py <device-UUID> <DerivedData> <new-result.xcresult> --all-tests`
runs the complete scheme sequentially with compilation caching disabled. Omit
`--all-tests` to run only the two lasso UI flows. Result/log/evidence paths must
be new: the helper refuses to replace previous evidence.

The UI uses actual native finger gestures and normal product controls. At21
declared save boundaries, the observer only reads the app container, matches
the UI-created note via catalog UUID and document title, and retains saved JSON.
It verifies stable IDs, point data, linear transforms, order, translation,
native pen/move/pen Undo3/Redo3, moved-stroke erasure, zoom/rotation/relaunch,
and a90-degree cropped PDF's unchanged registered asset SHA against the original
fixture. Xcode or observer failure remains a failure. There are no app test
hooks, data seeding, simulator erasure or app-document writes by this helper.
