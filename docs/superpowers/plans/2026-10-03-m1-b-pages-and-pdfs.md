# M1-B 페이지 관리와 여러 PDF 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 사용자의 직접 구현/main/단계 끝 fresh reviewer 한 번을 유지한다. 체크리스트를 순서대로 실행하고 PROGRESS와 Git을 먼저 대조한다.

**Goal:** 하나의 노트에 여러 PDF와 빈/줄/격자 페이지를 넣고, 페이지를 복제·정리·삭제·복원하고 책갈피로 찾은 뒤 실제 화면과 PDF 출력에서 같은 순서를 유지한다.

**Architecture:** schema v3가 PDF 자산 배열, 페이지별 자산 ID, 용지·책갈피, 삭제 페이지 보관을 표현한다. Foundation의 페이지 명령과 DocumentStore가 리비전/원자 저장을 책임지고, EditorSession은 현재 필기를 먼저 저장한 뒤 페이지 구조를 바꾼다. 출력은 활성 페이지만 문서 순서대로 합성한다.

**Tech Stack:** 기존 Swift 6/Foundation/SwiftUI/UIKit/PencilKit/PDFKit, 외부 라이브러리 없음, iPadOS 18 이상.

**Spec:** `docs/superpowers/specs/2026-09-26-minote-product-design.md`의 로컬 노트/페이지/PDF/저장. 이전 단계의 실제 라이브러리/저장/전환 검증은 `docs/PROGRESS.md` 및 `2026-10-03-m1-a-local-library.md`.

## Global Constraints

- 기본 저장소의 main에서 직접 구현한다. branch/worktree/PR/push를 만들지 않는다.
- Foundation 모델/저장은 MiNoteCore, UI/PencilKit/PDFKit은 앱에 둔다.
- 기존 문서·페이지·획·PDF 자산 ID/좌표/원본 bytes와 라이브러리 catalog version 1을 유지한다. v1/v2 읽기를 중단하지 않는다.
- 현재 필기·지원하지 않는 데이터·저장 실패를 무시하며 페이지/노트를 바꾸지 않는다. 구조 변경과 마지막 페이지 선택은 한 리비전/한 저장에 포함한다.
- 페이지 삭제는 본문 안의 삭제 페이지 보관으로 처리한다. 영구 제거/자산 cleanup과 `.minote` 백업은 M1-C에서 설계한다. 마지막 활성 페이지는 삭제할 수 없다.
- 기존 PDF의 100MB/500페이지/한 변 2000pt 제한을 유지한다. 여러 PDF 결합 노트는 활성+삭제 페이지 합계 1000개, 보관 자산 byteCount 합계 500MB를 초기 상한으로 사용한다. 기존 최대 501페이지 노트는 이 제한에 포함된다. 실기기 성능 보장 수치가 아니다.
- 줄/격자는 흰색 A4의 24pt 간격, 0.5pt 연회색 선으로 시작한다. 임의 크기/색/사용자 템플릿/표지는 후속이다. PDF 페이지의 용지는 변경하지 않는다.
- 기존 stroke Undo/Redo를 유지한다. 페이지 구조 변경 전후에는 현재 Canvas Undo를 reset하며 페이지 삭제 복원은 별도 보관 목록으로 제공한다. 모든 편집을 통합하는 Undo는 이번 범위가 아니다.
- 파일 접근과 모든 저장 실패를 원본/정상 backup 불변 테스트로 확인한다. UI에서 실패한 작업을 완료로 표시하지 않는다.
- 이번에는 M1-B까지만 완료한다. M1-C/M2/실기기 베타/다른 플랫폼을 구현했다고 표현하지 않는다.

## Review Focus

1. PDF 페이지 복제 후 같은 원본 index가 두 번 등장해도 서로 다른 페이지/획 ID와 독립 필기 및 출력이 유지되는가(Task 1/2/3).
2. 현재 PDF 페이지 삭제/이동/복원과 lastOpenedPageID가 충돌해 다른 필기를 보여주거나 잃지 않는가(Task 2/4).
3. 두 번째 PDF 저장 중 I/O/리비전 오류가 첫 PDF·현재 필기·현재 페이지를 바꾸지 않는가(Task 3/4).
4. 같은 원본 PDF 페이지를 반복 출력할 때 한 PDFPage 인스턴스의 주석이 중복 누적되거나 다른 복제 페이지 필기와 섞이지 않는가(Task 3).
5. 구버전 문서/JS fixture의 migration과 여러 자산의 누락·미래 schema 때문에 기존 정상 기록을 덮어쓰지 않는가(Task 1/5).

## 파일과 공통 계약

- `Packages/MiNoteCore/Sources/MiNoteCore/Document.swift`: NoteDocument의 정식 v3 필드는 `pdfAssets: [PDFAsset]`, `deletedPages: [DeletedPage]`. `NotePage`는 `paper: PaperStyle`, `isBookmarked: Bool`; `PaperStyle: String, Codable, Sendable` 값 blank/ruled/grid. `DeletedPage(page: NotePage, originalIndex: Int, deletedAt: Double)`의 식별자는 page.id다.
- `PDFAsset.swift`: `PDFPageSource`에 `assetID: UUID?`를 추가한다. nil은 legacy decoding 입력만 허용하고, v3 validation은 PDF 페이지에 반드시 등록 자산 ID를 요구한다. index/media/crop/rotation은 기존 그대로다.
- `DocumentCodec.swift`: encode는 v3만 기록한다. decode는 v1/v2/v3를 받고 v1/v2를 v3로 정규화한다. v2의 단일 pdfAsset을 pdfAssets로, PDFPageSource에 같은 ID를 연결한다. 새 용지는 blank, 책갈피 false, deletedPages []가 기본이다. 기존 ID/revision/ink/PDF metadata는 변경하지 않는다. migration 전 v1 단일 페이지와 v2의 원본 index 전체/유일 mapping 규칙도 검사하여 기존에 invalid였던 파일을 새 규칙으로 조용히 허용하지 않는다. 미래 버전은 명시적으로 거부한다.
- `PageCommands.swift`: `PageCommand` 및 `PageCommands.apply(_:to:) throws -> NoteDocument`. 명령은 `insert(after: UUID, paper: PaperStyle)`, `duplicate(UUID)`, `move(UUID, toIndex: Int)`, `delete(UUID)`, `restore(UUID)`, `setPaper(UUID, PaperStyle)`, `setBookmark(UUID, Bool)`. 성공당 revision +1, 실패 시 입력은 불변이다. insert/duplicate/restore는 새로 나타난 페이지를 선택하고 move/setPaper/setBookmark는 기존 선택 ID를 유지한다. 복제는 새 페이지/모든 획 ID, 그 밖의 원본 geometry/style/seed를 유지하며 새 페이지 책갈피는 false다. 삭제는 원래 index/페이지 전체를 보관하고, 복원 index는 현재 활성 페이지 수 이내로 clamp한다.
- `DocumentStore.swift`: `applyPageCommand(_:expectedRevision:) throws -> NoteDocument`; `attachPDF(data:asset:pages:afterPageID:expectedRevision:) throws -> NoteDocument`. actor 안의 읽기/기대 revision 확인/저장에는 await를 넣지 않는다. 첨부는 자산 원자 저장 후 새 페이지와 자산 참조를 한 JSON에 commit한다. 자산 누락 검사는 보관 자산 전체에 적용한다.
- `MiNote/PDFImporter.swift`: asset을 먼저 만들고 PreparedPDF.pages의 각 source.assetID를 붙인다. `PDFValidation.open(url:asset:referencedPages:) throws -> PDFDocument`는 해당 asset의 원본 페이지 수와 참조 페이지 geometry를 검사한다. 같은 index의 반복/일부 index 삭제는 허용한다.
- `MiNote/PDFExporter.swift`: `export(_:sourceURLs: [UUID: URL],destination:) throws`. 활성 page마다 해당 asset/index의 독립 출력 페이지를 만들고 그 page의 ink만 합성한다. 자산/출력 경로 중복을 거부한다.
- `MiNote/EditorSession.swift`: `applyPageCommand(_:) async`, `importPDF(from:) async`는 await 전에 처리 잠금을 잡고 current drawing flush/.saved를 확인한다. currentPDFPage는 currentPage.source.assetID로 선택한다. 원본 PDF는 순차 검증하고 화면 표시용 PDFDocument 캐시는 최대 2개로 제한한다. 실패 시 기존 문서/drawing/선택을 유지한다.
- `PaperRenderer.draw(_: PaperStyle, in: CGContext, bounds: CGRect)`는 좌상단 문서 좌표의 컨텍스트에 그린다. `PageThumbnailRenderer.image(for: NotePage, pdfPage: PDFPage?, maximumPixelEdge: Int = 256) throws -> UIImage`는 MainActor에서 보이는 페이지에 한해 만들고 캐시 24개로 제한한다. 새 `PageManagerView.swift`는 썸네일/책갈피 필터/추가/복제/재정렬/삭제 확인/삭제 페이지 복원을 제공한다. `PaperRenderer.swift`는 화면·thumbnail·출력이 공유하는 용지 선 geometry를 계산한다. thumbnail 캐시는 pageID/revision/배율을 키로 하고 페이지 삭제/편집 때 무효화한다.

### Task 1: schema v3와 기존 기록 migration

**Files:** Modify core Document.swift, PDFAsset.swift, DocumentCodec.swift, DocumentStore.swift, LibraryStore.swift; Test `SchemaV3Tests.swift` 및 기존 codec/portable/migration tests. 앱의 기존 단일 자산 호출은 이 작업에서 배열의 첫 자산만 읽는 임시 연결로 컴파일시키고 Task 3/4에서 모두 교체한다. 최종 코드에 first-asset 가정을 남기지 않는다.

**Interfaces:** 위 v3 모델/codec; 이후 Task 2/3의 명령과 PDF가 같은 타입을 사용한다.

- [ ] `testV1AndV2MigrateToV3WithoutIdentityOrGeometryLoss`: 기존 raw fixtures decode 후 IDs/revision/ink/asset metadata 같음, source.assetID 연결, 새 필드 기본값. encode/decode 후 동일 v3 문서.
- [ ] `testDuplicatedPDFIndicesAreValidWithUniquePageAndStrokeIDs`: 한 asset/index를 다른 pageID/새 strokeID로 두 번 참조하면 통과; 잘못된 assetID/index/중복 object ID는 거부.
- [ ] `testUnsupportedSchemaAndMissingSecondAssetPreservePrimaryAndBackup`: 미래 version/두 번째 자산 누락/byteCount 불일치 때 blank 또는 이전 단일 PDF로 fallback하지 않음, raw 파일 불변.
- [ ] core 관련 `swift test --package-path Packages/MiNoteCore --filter SchemaV3Tests` RED 확인 → 모델/codec/자산 검증 최소 구현 → 전체 core GREEN.
- [ ] LibraryStore legacy copy가 모든 pdfAssets를 복사하고 기존 catalog/노트별 directory를 유지하게 수정. raw v1/v2 backup을 보존하는 재저장 테스트 포함.
- [ ] 기존 앱 단위 컴파일/왕복 tests GREEN → PROGRESS/계획 체크 → 커밋.

### Task 2: 페이지 명령과 삭제 복원 저장

**Files:** Create core PageCommands.swift/`PageCommandsTests.swift`; Modify DocumentStore.swift; Test `PageStoreTests.swift`.

**Interfaces:** consumes Task 1 v3. produces PageCommand/apply 및 store.applyPageCommand(_:expectedRevision:).

- [ ] `testDuplicateAllocatesNewIDsAndPreservesInkValues`: 페이지·획 ID 새로 생성, 원본 ID/전체 필기 값 불변, 복제 책갈피 false, revision 한 번 증가.
- [ ] `testMoveDeleteRestoreKeepSelectionAndAllData`: current 삭제 시 가까운 남은 페이지 선택; 다른 page 이동 시 선택 ID 유지; 보관 원본과 모든 ID 보존 후 복원; 재실행 후 같은 순서/책갈피/용지.
- [ ] `testInvalidCommandCannotMutateOrExceedLimits`: 마지막 페이지/없는 ID/PDF 용지 변경/범위 밖 index/리비전 overflow/1000페이지 초과 거부. 입력 문서 불변.
- [ ] RED: `swift test --package-path Packages/MiNoteCore --filter Page` → value 명령/validation/actor 기대 revision 저장 구현 → GREEN.
- [ ] `testStalePageCommandAndDiskFailureKeepLatestInk`: 저장 직전 최신 revision으로 바뀜/backup path I/O 오류 때 command가 최신 필기를 덮지 않음. 정상 retry 후 정확한 page 순서.
- [ ] 전체 core GREEN → PROGRESS → 커밋.

### Task 3: 여러 PDF 가져오기와 순서대로 내보내기

**Files:** Modify core DocumentStore.swift/PDF tests; app PDFImporter.swift/PDFExporter.swift; Create PaperRenderer.swift 및 `MultiPDFTests.swift`; Modify PDFImportTests/PDFExportTests.

**Interfaces:** consumes v3 assets/page references and new attachPDF signature; produces PreparedPDF and export sourceURLs mapping/asset-specific validation.

- [ ] `testTwoPDFsWithSameFilenameKeepIndependentAssets`: 같은 파일명/서로 다른 bytes PDF 2개, 각각 UUID path와 index/geometry, 현재 페이지 뒤 삽입, 최초 PDF/기존 ink 불변.
- [ ] `testFailedSecondImportAndStaleRevisionKeepFirstPDFAndInk`: asset 기록 후 JSON 실패/limit 오류/기대 revision 오류 → 이전 JSON/backup/자산 불변. 새 orphan은 지우지 않고 M1-C에 넘김.
- [ ] `testExportDuplicatedAndReorderedPDFPagesHasOnlyTheirOwnInk`: 서로 다른 자산 및 같은 source index 복제 페이지를 섞어 재정렬. output page 순서/텍스트/crop/rotation/각 page별 ink pixel 위치 확인, 서로의 주석 중복 없음. 삭제 페이지는 출력 제외, 용지 선도 출력됨.
- [ ] core/Xcode 관련 RED → 자산 ID 연결, validation, 독립 출력 page, 용지 geometry 구현 → GREEN. 기존 source/destination 보존·잠긴 PDF·4회전 테스트 유지.
- [ ] 두 번째 PDF가 없다는 이유로 첫 PDF를 택하는 fallback 제거. sourceURLs 누락을 명시적 실패로 처리.
- [ ] 관련 전체 tests → PROGRESS → 커밋.

### Task 4: 편집 세션과 페이지 관리 화면

**Files:** Modify EditorSession.swift/NoteCanvas.swift/NoteEditorView.swift; Create PageManagerView.swift/`PageThumbnailRenderer.swift`; Test `PageEditorTests.swift`/`PageManagerUITests.swift`.

**Interfaces:** consumes PageCommand and multi-PDF boundaries; produces EditorSession.applyPageCommand(_:) async and visible page manager.

- [ ] `testPageCommandFlushesLatestInkAndKeepsSessionOnFailure`: 현재 canvas ink 저장 후 command 적용, 필기 저장 실패/미지원 ink/늦은 callback 때 command를 막고 같은 page/drawing 유지.
- [ ] `testPDFAssetSwitchAndRestoredPageRemainEditable`: PDF A/B 페이지 전환, 복제 페이지 독립 ink, 삭제/복원 후 원래 ID와 geometry, 노트 닫기/다른 노트/재열기 유지.
- [ ] RED → await 전 잠금·최종 최신 상태 확인·필기 flush·actor 명령/commit·histories/선택/PDF cache 교체. canvas delegate의 page owner 보호 유지.
- [ ] 페이지 manager UI RED → 추가/용지/복제/재정렬/책갈피/삭제 확인/복원·접근성 IDs 구현. 썸네일은 활성/보관 원본을 수정하지 않고 생성한다. snapshot이 늦게 돌아오면 현재 pageID/revision과 다를 때 게시하지 않는다.
- [ ] UI `testPagesAndTwoPDFsSurviveRelaunchAndExport`: blank/ruled/grid, 실제 손가락 ink, A/B PDF, 복제/이동/삭제/복원/책갈피 필터/재실행/미리보기. storage API만 호출한 시험과 구분한다.
- [ ] 앱 전체 단위·관련 UI GREEN → PROGRESS → 커밋.

### Task 5: 독립 문서 호환성·전체 검증·인계

**Files:** Modify Tools/PortableInk/document.mjs/editor.mjs/app.mjs/render.mjs/관련 tests 및 ink-v2.md; Create `docs/format/document-v3.md`; Add v3 multi-PDF fixture; Update LibraryTests helper/README/AGENTS/PROGRESS/Notion.

**Interfaces:** JS accepts v2 and v3; v2 input keeps v2 output to preserve existing exact fixtures. v3 source editing retains all assets/deleted pages/paper/bookmark metadata and untouched object IDs. Canvas 용지 geometry는 iPad와 같은 24pt 기준이다; PDF 원본 배경은 여전히 표시하지 않는다.

- [ ] JS `testV3EditsKeepMultipleAssetsDeletedPagesAndPageMetadata`: 지원 v3 active-page ink edit가 자산/보관 페이지/순서/용지를 지우지 않음. future schema/잘못된 관계 거부. 기존 v2 fixture check 계속 동일.
- [ ] RED → validator/편집 도구의 version별 계약 구현 → Node GREEN; iPad `testIndependentV3RoundTripPreservesPagesAssetsAndEditableInk`로 JS 결과 재편집/저장/재열기 확인.
- [ ] Node 전체+fixture check, core 전체, 18.6/26.4 앱/기존 라이브러리·ink·PDF/새 페이지 UI, 별도 seeded migration 모두 GREEN. 기존 fixture-only skip은 별도 실제 실행 결과와 분리한다.
- [ ] 한 번의 fresh 전체 리뷰 → 중요한 문제 재현/수정/관련 검증 → 최종 전체 tests. 실기기 Pencil/손바닥/발열/큰 실제 PDF는 계속 대기.
- [ ] 성공 근거/실패 이력/제한/커밋/Notion 반영 시점을 기록하고 M1-C 백업·파일 수명주기 계획을 실제 결과로 작성 → main 커밋. push는 별도 요청이다.

## 완료 조건·계획 자기 점검

M1-B는 페이지/다중 PDF/기본 용지/책갈피/삭제 복원과 해당 데이터의 양방향 호환·출력을 완료 범위로 삼는다. schema/명령/PDF/session/UI/독립 검증은 Task 1~5로 연결된다. Review Focus 다섯 항목은 각 작업의 구체 테스트에 대응한다. API 명칭과 입력/출력 타입을 교차 점검했다.

노트 즐겨찾기/제목·폴더 검색/텍스트·이미지·올가미는 M2, `.minote` 전체 백업·복원/영구 제거/공유 중 임시 export cleanup은 M1-C, 표지/커스텀 템플릿/통합 Undo·다중 창/성능·실기기는 후속이다. 전체 제품 명세의 해당 항목을 완료에서 제외했다. 이 계획은 다음 실행용이며 아직 구현/검증하지 않았다.
