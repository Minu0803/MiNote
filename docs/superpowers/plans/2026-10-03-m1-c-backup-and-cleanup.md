# M1-C Editable Backup and File Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 직접 구현하고 단계 끝에 fresh reviewer 한 번을 사용한다. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 편집 가능한 노트 전체를 `.minote` 파일로 백업하고 다른 빈 설치에 복원하며, 사용 중인 파일과 정상 복구본을 보호한 채 불필요한 파일을 정리한다.

**Architecture:** Foundation 코어가 streaming archive·검증·새 노트 복원·정리 후보를 책임진다. 앱은 security-scoped Files 접근, 진행/취소, 현재 필기 flush, 공유 파일의 사용 기간과 확인 UI를 관리한다. 기존 schema v3와 catalog v1을 유지하고 삭제를 위한 작은 복구 journal만 별도로 둔다.

**Tech Stack:** Swift 6/Foundation, SwiftUI/UIKit/PencilKit/PDFKit, 외부 라이브러리 없음, iPadOS 18 이상.

**Spec:** `docs/superpowers/specs/2026-09-26-minote-product-design.md`의 저장/복구·편집 원본 내보내기. 현재 구현 계약은 `docs/format/document-v3.md`, `docs/format/library-v1.md`, M1-B 실제 결과는 `docs/PROGRESS.md`.

## Global Constraints

- 기본 저장소 `/Users/minwookim/Documents/GitHub/MiNote`의 main에서 직접 작업한다. branch/worktree/PR/push 없음. 한 번에 M1-C만 실행한다.
- Foundation만 쓰는 MiNoteCore에 파일 계약을 둔다. UI/플랫폼 파일 접근은 앱에 둔다. 서버·자동 클라우드 백업·다른 플랫폼 앱은 제외한다.
- 백업은 문서/페이지/획/자산 UUID, revision, 필기 제어점과 변환, 용지/책갈피, 활성 및 삭제 페이지, 모든 등록 PDF 원본 bytes를 보존한다. Undo history·썸네일·폴더 전체 백업은 포함하지 않는다.
- 노트별 백업이며 PDF 배포용 출력과 구별한다. 복원은 기존 노트를 덮지 않고 새 노트로 추가한다. 이미 같은 document.id가 있으면 문서 ID만 새로 만들고 page/stroke/asset IDs를 유지한다. 기본 제목은 원래 제목 + ` (복원)`이다.
- 원래 PDF 제한 100MiB/500페이지/2000pt, 합계 PDF 500MiB·활성+삭제 페이지 1000개를 유지한다. 새로운 archive 상한은 640MiB, JSON/manifest entry 각 128MiB/1MiB, 총 entry 1002개다. 실기기 성능 보장 수치가 아니다.
- 파일 내보내기/복원은 actor에서 처리하고 bulk PDF I/O 버퍼를 64KiB로 제한한다. 취소는 각 chunk 경계에서 확인한다. 문서 JSON decode 비용은 별도 측정한다.
- future schema, 누락/변조/중복 자산, 잘못된 경로, I/O 실패는 명시적인 오류다. 빈 노트나 이전 단일 PDF로 대체하지 않는다. 기존 원본과 backup을 덮지 않는다.
- 영구 제거는 명시적인 사용자 확인 뒤에만 실행한다. 공유/미리보기 중 파일은 정리하지 않는다. 시작 시 무조건 전체 폴더를 지우거나 기간만으로 note/PDF 원본을 지우지 않는다.
- 실제 Pencil/손바닥/발열/대형 실제 PDF는 M3 확인 대기다. 이 계획은 아직 구현하지 않았다.

## Review Focus

1. 중복 document UUID의 백업을 여러 번 복원해도 원래 노트의 필기·PDF가 바뀌지 않는가(Task 2/4).
2. traversal/중복 ZIP entry·변조 bytes·future schema·취소·디스크 부족이 기존 목록/본문을 손상하지 않는가(Task 1/2).
3. catalog commit 전후 강제 중단이나 backup 쓰기 실패로 영구 제거했던 노트가 자동 복구되거나 정상 노트가 제거되지 않는가(Task 3).
4. 삭제 페이지 또는 정상 document backup에만 남은 PDF가 orphan cleanup으로 사라지지 않는가(Task 3).
5. 공유 소비자/QuickLook이 읽는 파일이 export cleanup과 경쟁하거나 늦은 필기가 백업에서 빠지지 않는가(Task 4).

## 파일 구성과 인터페이스

- Create core `StoredZIP.swift`: `.minote` v1은 표준 ZIP32의 **stored(method 0)** entry만 사용한다. `manifest.json`, `document.json`, `assets/<UUID>.pdf`. 자체 출력의 최소 reader/writer이며 deflate/암호/ZIP64/data descriptor는 명시적으로 거부한다. CRC32·local/central header 일치·entry 길이/offset/EOF 경계를 검사한다. 경로는 manifest의 정확한 allowlist만 허용한다. decoder가 임의의 경로로 추출하지 않는다.
- Create core `NoteBackup.swift`: `BackupManifest: Codable, Sendable`는 archiveVersion=1, documentID, schemaVersion, revision, entries(name, byteCount, crc32)를 가진다. `BackupProgress(completedBytes: Int64,totalBytes: Int64)`와 `ValidatedBackup(document: NoteDocument,stagingDirectory: URL)`를 정의한다. `NoteBackup` actor의 `export(document: NoteDocument, assetURLs: [UUID: URL], destination: URL, progress: @Sendable (BackupProgress) -> Void) async throws`, `validate(source: URL, stagingRoot: URL, progress: @Sendable (BackupProgress) -> Void) async throws -> ValidatedBackup`는 Task cancellation을 전파한다. 완료 archive를 원자 교체하기 전 실패 시 기존 destination 보존.
- Modify core `LibraryStore.swift`: `restoreBackup(_ backup: ValidatedBackup, folderID: UUID?) throws -> LibraryNoteRow`. staging에서 새 note directory를 완성한 뒤 catalog에 추가한다. catalog 실패 시 완성 디렉터리는 기존 orphan recovery가 회수하며 기존 노트는 불변이다. staging 데이터는 호출자가 defer로 정리한다.
- Create core `LibraryMaintenance.swift`: `MaintenanceReport`는 후보 URL/종류/예상 bytes/보호 이유를 가진다. `LibraryStore.maintenanceReport() throws -> MaintenanceReport`, `cleanUnreferencedFiles() throws -> MaintenanceReport`, `purgeTrashedNote(_: UUID, expectedCatalogRevision: Int64) throws`, `purgeDeletedPages(_: [UUID], noteID: UUID, expectedRevision: Int64) throws -> NoteDocument`를 제공한다. page purge는 정상 문서 저장 경로를 사용하고 기존 backup은 보존한다.
- Create core `PurgeJournal.swift`: permanent note purge의 `prepared → catalogCommitted → finished` 상태와 제거 대상 UUID·원래 catalog revision·임시 quarantine 상대 경로를 기록한다. journal/quarantine은 library 내부 고정 경로만 사용한다. load 시 journal을 먼저 처리한 뒤 orphan recovery를 실행한다.
- Create app `BackupFileAccess.swift`: security scope와 NSFileCoordinator를 복사/검증 완료까지 유지한다. PDFImporter의 scope 구현을 참고하고, 완성 staging의 모든 PDF를 PDFValidation으로 순차 검증해 원본 count/geometry/삭제 페이지 참조까지 확인한 뒤 복원을 허용한다. actor 경계를 넘어 PDFKit 객체를 전달하지 않는다.
- Create app `ExportFileRegistry.swift`: actor가 UUID별 export directory/createdAt/active lease를 소유한다. `acquire(_:) -> UUID`, `release(_:)`, `cleanExpired(now:)`는 활성 lease 없는 생성 후 7일 지난 registry 파일만 정리한다. raw note/PDF/unknown directory에는 접근하지 않는다. PDF 및 backup export가 같은 registry를 사용한다.
- Modify `EditorSession.swift`, `LibrarySession.swift`, `LibraryView.swift`, `NoteEditorView.swift`, `ExportPreview.swift`; Create `BackupViews.swift`, `BackupTypes.swift` 및 UIKit 공유 wrapper. `UTType.minote`는 `com.minote.backup`/확장자 `.minote`/ZIP archive conformance로 등록하고 `MiNoteApp.swift`·Xcode project Info 설정을 맞춘다. 마지막 drawing capture/flush와 await 후 snapshot 검사에 기존 M1-B 경합 보호를 재사용한다. UIActivityViewController completion 및 QuickLook dismissal까지 파일 lease를 유지한다. 기능 이름은 `편집 원본 백업`, `백업에서 새 노트 복원`, `저장 공간 정리`, `영구 삭제`다.

### Task 1: 안전한 편집 원본 archive

**Files:** StoredZIP.swift, NoteBackup.swift; tests `StoredZIPTests.swift`, `NoteBackupTests.swift`; Create `docs/format/backup-v1.md`.

**Interfaces:** consumes DocumentCodec v3 and UUID asset URLs; produces NoteBackup/ValidatedBackup.

- [x] `testArchiveKeepsV3InkPagesAndEveryPDFByte`: 실제 multi-source fixture+PDF 2개 export/validate, decode 문서 전체 값·모든 bytes 동일, independent Python zipfile로 own output의 entry/CRC 확인.
- [x] `testMalformedArchiveNeverEscapesStaging`: `../`, absolute/backslash 경로, 중복 entry, symlink external attribute, unsupported method/encryption/ZIP64, local/central 불일치, 겹치는 offset, truncation/CRC/byteCount 오류를 각각 거부. library/destination sentinel bytes 불변.
- [x] `testCancelledOrFailedExportPreservesDestination`: chunk write 중 취소와 주입한 writer I/O 실패. 이전 정상 archive 불변, 미완성 temp만 자신의 범위에서 제거.
- [x] `swift test --package-path Packages/MiNoteCore --filter 'StoredZIPTests|NoteBackupTests'` RED → streaming reader/writer와 manifest allowlist → GREEN. 전체 core/Node도 확인하고 PROGRESS·format·커밋.

### Task 2: 기존 노트 보존 복원

**Files:** LibraryStore.swift; tests `LibraryBackupTests.swift`; LibraryTests helper의 별도 backup 설치 fixture.

**Interfaces:** consumes ValidatedBackup; produces restoreBackup and new catalog row.

- [x] `testRestoreIntoEmptyLibraryAndDuplicateIdentity`: 빈 library 복원/다시 복원/원래 UUID 충돌. 페이지·획·자산은 그대로, document UUID만 필요할 때 변경, 원래 노트 bytes와 폴더 불변, 재열기 성공.
- [x] `testBadBackupAndFailedCatalogCannotLoseExistingNotes`: future v4/등록 asset 누락·CRC 변조/폴더 없음/취소/staging copy I/O/catalog 쓰기 실패. 원래 primary/backup/자산 불변. 완성 orphan은 다음 load에서 한 번만 회수.
- [x] RED → 모든 자산 복사/검증 후 catalog commit, 기존 codec/row 오류 처리 재사용 → GREEN. core 전체 → PROGRESS → 커밋.

### Task 3: 복구본을 지키는 정리와 영구 제거

**Files:** LibraryMaintenance.swift, PurgeJournal.swift, LibraryStore.swift, DocumentStore.swift; tests `LibraryMaintenanceTests.swift`, `PurgeRecoveryTests.swift`.

**Interfaces:** consumes catalog/doc validation; produces maintenance/purge APIs and startup journal recovery.

- [ ] `testOnlyKnownUnreferencedAssetsAreCandidates`: primary+정상 backup의 활성/삭제 페이지와 pdfAssets union을 보호. 알려진 UUID 자산 파일 중 두 정상 snapshot 어디에도 없는 것만 orphan 후보. future/손상/읽기 불가 snapshot이 하나라도 있으면 해당 note cleanup 중단. legacy root/unknown 파일은 건드리지 않음.
- [ ] `testPagePurgeRetainsBackupAssetsAndLatestInk`: 삭제 목록에 있는 요청 page만 영구 제거, active page/없는 ID/stale revision 거부. 실패 시 문서 불변. previous backup이 참조하는 PDF는 cleanup이 보존하고 backup이 정상적으로 교체된 뒤에만 orphan 가능.
- [ ] `testNotePurgeResumesAtEveryWriteBoundary`: trash note만 허용. prepared journal·quarantine 이동·catalog primary/backup commit·quarantine 제거 직후 각각 강제 중단/쓰기 실패 재현. commit 전은 원래 note 복구; commit 후는 purge 완료. catalog backup에서 대상 참조도 제거한 다음 디렉터리를 지우고, 완료 전 orphan recovery가 대상 재등록하지 않음. journal 오류는 library 편집 차단과 안내, 추측 삭제 없음.
- [ ] RED → 정확한 reference union/UUID allowlist/journal recovery 구현 → GREEN. 실제 filesystem byte 검증·core 전체 → PROGRESS → 커밋.

### Task 4: Files 백업·복원·공유·정리 화면

**Files:** 위 app 파일, `BackupSessionTests.swift`, `ExportFileRegistryTests.swift`, `BackupUITests.swift`.

**Interfaces:** consumes backup/restore/purge/maintenance APIs; produces cancellable UI actions, preview/share leases.

- [ ] `testBackupFlushesLatestDrawingAndBlocksOnLateCallback`: 필기 직후 백업, flush 실패/늦은 지원·미지원 callback. 최신 성공 snapshot만 출력; 실패해도 drawing/session 유지.
- [ ] `testExportLeaseSurvivesPreviewShareAndCleanup`: QuickLook/공유 lease 두 개 동안 시간 8일 이동에도 보존. 마지막 lease 해제 후만 cleanup. 취소/재실행/registry 손상에서 알려지지 않은 파일을 삭제하지 않음.
- [ ] `testBackupRestoreViaFilesRemainsEditable`: 실제 finger ink+PDF A/B+복제/삭제 보관+용지/책갈피 → Files 백업 저장 → 독립 빈 설치 복원 → 획 재편집/Undo/저장/재실행. 기존 노트가 있는 설치의 동일 백업 복원도 새 note 확인.
- [ ] `testPurgeRequiresConfirmationAndProtectsActiveNote`: 취소 불변, trash note/삭제 page만 확인 후 제거, 실패 inline 안내, 저장 공간 정리의 보호 이유/결과 표시. CRC가 정상이어도 PDFKit이 거부하거나 metadata와 geometry가 다른 PDF backup은 catalog 추가 전에 거부.
- [ ] API 미존재/실제 UI RED → 입력 잠금/진행률/취소/Files/lease/확인 연결 → 앱 전체+관련 UI GREEN → PROGRESS → 커밋.

### Task 5: 전체 검증·한 번 리뷰·기록

**Files:** AGENTS/README/PROGRESS/milestone/Notion, 다음 M2 계획.

- [ ] Node/v2·v3 fixture check, core 전체, MiNote app/UI를 iPadOS 18.6/26.4 모두 실행. fixture-only migration은 별도 seeded 실행/원본 bytes 검증. 백업의 빈 설치 이동을 별도 기기로 실제 실행하며 정상 사용자 데이터 reseed 금지.
- [ ] fresh 전체 reviewer 한 번에 Review Focus 다섯 항목과 journal/streaming/lease 경합 검증을 제공. 중요한 문제는 RED/수정/GREEN과 최종 관련 suite로 확인. Minor는 근거와 후속 위치를 기록.
- [ ] 성공·실패·미검증·제한과 코드 커밋/마지막 Notion 시각을 기록. M2를 실행 가능한 작은 단위로 나눠 **첫 편집 단위만** 계획하고, 이번에는 구현하지 않음.
- [ ] main 커밋·clean 확인. push는 별도 요청. 물리 iPad/외부 앱 공유 소비자별 호환은 실제 실행 여부를 구분한다.

## 계획 자기 점검과 다음 실행

archive와 복원, 영구 제거 journal/reference 보호, UI·lease는 각각 독립 검증 가능한 Task 1~4이며 Task 5가 단계 인계다. schema v3/catalog v1을 변경하지 않는다. ZIP은 압축 기능을 추가하지 않고 own backup 읽기로 제한해 상호운용 및 메모리 경계를 명시했다. 복원 이름/ID 규칙, archive 상한, 취소·원자 commit, cleanup 보호 대상과 journal 재개 기준을 테스트에 대응했다.

다음 실행 첫 작업은 Git/PROGRESS 대조 → 현재 codec/backup/library orphan recovery와 PDF export 임시 경로 읽기 → Task 1 실제 multi-source 보존/손상 archive RED다. 이 파일 작성은 M1-C 구현 완료를 의미하지 않는다.
