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
