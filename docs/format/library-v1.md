# Local library catalog v1

M1-A stores library metadata separately from the authoritative note document.
M1-B keeps catalog version 1 while note bodies use schema v3; see
[the current document contract](document-v3.md).
`LibraryCatalog` is Foundation-only. A title is read from `NoteDocument.title`;
the catalog never keeps a second title that could overwrite newer ink or text.

## Paths

```text
Documents/MiNote/
  library.json
  library.backup.json
  notes/<note UUID>/document.json
  notes/<note UUID>/document.backup.json
  notes/<note UUID>/assets/<asset UUID>.pdf
```

The old root `document.json`, `document.backup.json` and `assets` remain after
migration. They are retained source records, not another active editor. The
library actor owns one DocumentStore instance per note. There is one active
editor in the app; concurrent editing windows and cross-process writers are
outside this contract.

## Metadata

- `version`: 1. Future versions fail explicitly before decoding their bodies.
- `revision`: nonnegative Int64, incremented for each successful metadata change.
- `notes`: unique UUID `id`, optional `folderID`, finite epoch-seconds
  `modifiedAt`, optional finite `trashedAt`. A non-nil trashedAt means soft trash.
- `folders`: unique UUID `id`, nonempty trimmed `name`, optional `parentID`.
  Parents must exist, and cycles are rejected. Repeated names are allowed.
- Note folder references must exist, including references from trash. There is
  no folder deletion or permanent note deletion in M1-A.

Optional nil metadata is omitted by JSONEncoder. All data changes are validated
before catalog encoding. Active/recent notes sort by modification time descending,
then UUID; this is modification recency, not an access log. UI folder paths include
ancestor names and stable UUID suffixes when sibling names collide.

## Commit and recovery

A new note's document and immutable PDF assets are durable before catalog commit.
A catalog write uses atomic replacement and retains the prior valid raw catalog
as backup. The cached catalog is published only after the disk write succeeds.
Async library mutations acquire a busy guard before their first await; a cached
catalog that differs from disk is rejected as a conflict.

If a primary catalog contains corrupt JSON, a valid backup is restored with a
notice. Unknown versions, invalid relationships and actual file I/O failures are
reported; they are not replaced with an empty library. A referenced missing note
is an error row. A UUID note directory not linked in the catalog is recovered as
an item, even when its document is missing or corrupt; its bytes are retained.

When no catalog exists, the legacy DocumentStore validates the source document
and assets first. Migration copies PDF bytes and raw document/backup bytes into
the note directory and commits the catalog last. An interrupted catalog commit
can be retried without changing the original source. Normal editing still rotates
the note directory's recovery copy; the retained legacy root remains untouched.

## Editor transitions

Closing, opening another note and renaming an active note first flush outgoing
ink and require a saved state. Modified note metadata must also commit. After the
last awaited refresh, the session rechecks the entire document and save state
against the flushed snapshot, then removes the editor without another suspension.
A late drawing or serialization failure retains that same editor. The native
canvas follows the view's enabled state; queued callbacks still reach the session
so they cannot silently disappear during this check. Disk or serialization failure
preserves visible ink and offers retry.

See `docs/PROGRESS.md` for actual tests, failure histories and device limitations.

## M1-C 파일 정리와 영구 제거

문서 actor에서 primary와 존재하는 backup을 각각 strict decode하고 모든 등록 PDF의 존재/길이를 검증한다. 두 snapshot의 asset UUID union을 보호하며 정확한 UUID.pdf 일반 파일만 정리한다. 한 snapshot이라도 future/손상/읽기 오류이면 그 노트 전체 정리를 보류한다. legacy root와 unknown은 유지한다. 삭제 보관 페이지 purge는 expectedRevision을 검사하고 정상 save를 사용하므로 이전 backup의 PDF를 바로 지우지 않는다.

노트 영구 삭제는 trash와 expectedCatalogRevision이 필요하다. 이전 DocumentStore를 retire한 뒤 library 내부 purge-journal.json(v1, 원래/commit catalog, UUID/디렉터리 이름, stage)과 quarantine/<UUID>를 사용한다. prepared journal→quarantine 이동→primary catalog commit→fallback catalog 동일 commit→catalogCommitted journal→quarantine 제거→finished journal→journal 제거 순서다. 시작 시 orphan 회수 전에 처리하며 primary가 원래 값이면 commit 전 복구, commit 값이면 fallback에서 참조 제거 후 삭제를 완결한다. 손상·future·다른 catalog·잘못된 경로는 추측 삭제하지 않고 편집을 막는다. journal 상한16MiB는 기록/읽기 양쪽에 동일하다.

7개 durable 경계 중단/실제 ENOSPC·stale store·backup fallback 재등장 방지 테스트를 사용한다. 다중 프로세스/동기화/외부 파일 교체는 이 로컬 단일 actor 계약 범위 밖이다. 실제 영구 제거 UI는 반드시 사용자 확인을 제공한다.
