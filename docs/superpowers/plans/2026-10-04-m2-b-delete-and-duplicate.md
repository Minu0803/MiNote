# M2-B Selected Stroke Deletion and Duplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 직접 구현하고 단위 끝에 fresh reviewer 한 번을 사용한다. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 현재 페이지에서 올가미로 선택한 획을 삭제하거나 같은 페이지에 복제하고, native 필기와 같은 Undo/Redo·저장·백업 흐름에서 원본과 복제본의 ID를 안전하게 유지한다.

**Architecture:** M2-A의 임시 선택 overlay와 실제 canvas의 명시적 snapshot 이력을 재사용한다. Foundation 명령은 선택 UUID의 삭제 또는 새 UUID를 가진 복제본 추가만 수행한다. 앱은 원래 native drawing과 새 획을 함께 유지하고, 명령 전 최종 canvas 캡처부터 같은 coordinator를 통과한다.

**Tech Stack:** Swift/Foundation, SwiftUI/UIKit/PencilKit/PDFKit, iPadOS 18 이상, 외부 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-26-minote-product-design.md` 객체 편집·안정 ID·포트폴리오용 검증. 이전 결과 `docs/milestones/2026-10-04-m2-a-lasso-move.md`; 계약 `docs/format/document-v3.md`, `docs/format/backup-v1.md`.

**상태:** 계획만 작성했다. M2-B 코드는 미구현이다. 재개 시 M2-A 최종 기록/실제 Git 상태를 먼저 대조한다.

## Global Constraints

- 학습과 업무를 비슷하게 지원하며 iPad 필기 품질을 우선한다. 기본 저장소 `main`에서 직접 작업하고 branch/worktree/PR/push는 만들지 않는다.
- schema v3/catalog v1/backup v1을 유지한다. MiNoteCore는 Foundation만 사용한다. 원본 PDF bytes·자산·페이지·비선택 획 값/순서/ID는 변경하지 않는다.
- 이번 범위는 선택 획 삭제와 **같은 페이지 복제**다. 새 복제본은 원본 선택 순서대로 페이지 획 배열 끝에 추가하고 모두 새 UUID를 받는다. 원본/새 복제본의 제어점·색상·도구·seed·시간·선형 변환은 같고 tx/ty만 각각 +20pt다. 페이지 밖의 유한 위치도 잘라내지 않는다.
- 삭제 후 선택은 비우고, 복제 후에는 새 복제본들만 선택한다. Undo/Redo 때 선택은 비운다. 성공한 명령/Undo/Redo는 revision을 한 번 증가시킨다. 빈 선택은 문서·이력·revision 무변경이다.
- `.minote` 복원/페이지 전환/재실행은 기존대로 Undo를 초기화한다. 다른 페이지 Undo나 이력 영속화는 포함하지 않는다.
- 삭제는 휴지통 페이지와 별개인 현재 페이지 필기 편집이다. 같은 페이지 Undo로 되돌릴 수 있고 자동 저장한다. 저장 실패 때 화면 필기·정상 primary/backup·이력을 유지하며 명령을 차단하고 재시도를 제공한다.
- 클립보드 복사·다른 페이지 붙여넣기는 **M2-B2**로 분리한다. 외부 payload 검증, 사용자 요청 시 읽기, 지연 완료의 소유 page/generation 및 배치 좌표를 별도로 검증할 필요가 있다. 기존 목표에서 제외하지 않는다. 크기/회전·부분 선택·텍스트·이미지·검색은 후속이다.
- 실제 Pencil·손바닥·발열·장시간/큰 실제 문서는 M3 검증 대기다. 실제 UI와 programmatic callback 시험을 구분한다.

## Review Focus

1. 같은 모양/겹친 획을 복제·삭제·Undo한 뒤 native 지우개/pen을 쓰면 다른 UUID를 추측해 붙이지 않아야 한다(Task2).
2. 최종 canvas B가 delegate A 뒤 명령보다 먼저 캡처되면 B를 유지하고 native 이력과 명령을 각각 한 번 되돌려야 한다(Task2).
3. 시스템 Undo/Redo가 ENOSPC 또는 백업 busy 중 직접 호출돼도 stack을 소비하지 않고 복구 후 정확히 재생돼야 한다(Task3).
4. 이전 페이지/generation의 지연 명령이나 native callback은 새 페이지를 바꾸지 않아야 한다(Task3).
5. 회전/crop PDF의 복제 20pt가 화면과 PDF 출력에서 같아야 하고 모든 원본 PDF bytes와 비선택 metadata가 유지돼야 한다(Task3).

## 파일과 인터페이스

- Modify core `Packages/MiNoteCore/Sources/MiNoteCore/InkCommands.swift`: `delete(strokeIDs: Set<UUID>, pageID: UUID, expectedRevision: Int64, in document: NoteDocument) throws -> NoteDocument`, `duplicate(strokeIDs: Set<UUID>, pageID: UUID, dx: Double, dy: Double, expectedRevision: Int64, in document: NoteDocument) throws -> NoteDocument`. 문서 전체·revision·활성 page·ID subset을 먼저 검사한다. 복제는 유한 양/합산 overflow와 새 ID 전체 무결성도 검사한다.
- Modify app `MiNote/EditorSession.swift`: `deleteSelectedInk() throws -> InkTransition?`, `duplicateSelectedInk(dx: Double, dy: Double) throws -> InkTransition?`. 기존 `acceptInkCommand`와 snapshot/alias를 재사용한다. nil은 빈 선택 무변경이다.
- Modify app `MiNote/InkUndoCoordinator.swift`: `deleteSelection() throws`, `duplicateSelection(dx: Double, dy: Double) throws`. 기존 이동과 공통 명령 등록 경계를 추출하고 실제 InkCanvasView manager에 등록한다.
- Modify app `MiNote/NoteCanvas.swift`: `CanvasReference.deleteSelectedInk(in session: EditorSession)`, `duplicateSelectedInk(in session: EditorSession)`. 현재 canvas를 먼저 캡처하고 소유 session/page/generation과 eligibility를 확인한다. UI 오류는 `operationError`로 전달한다.
- Modify `MiNote/NoteEditorView.swift`: 올가미일 때 `선택 삭제`, `복제` 버튼, accessibility identifiers `deleteSelectedInk`, `duplicateSelectedInk`. 선택이 비었거나 `!canApplyInkCommand`이면 비활성화한다. 복제는 (20,20)pt를 사용한다.
- Tests: core `InkCommandTests.swift`; app `InkUndoTests.swift`, `InkSelectionTests.swift`, `SelectionSessionTests.swift`; Create UI `MiNoteUITests/SelectionCommandUITests.swift`; portable fixtures/독립 도구는 Task3에서 연결한다.

### Task 1: Foundation 삭제·복제 명령

**Interfaces:** 현재 InkCommands/DocumentCodec/NoteDocument를 소비하고 위 `delete`/`duplicate` API를 제공한다.

- [ ] RED: 선택 2/전체 4획 삭제 시 남은 2획 값/순서/ID, 다른 활성/삭제 페이지·PDF·용지·책갈피 불변, revision+1. 빈 선택은 rev Int64.max에서도 무변경.
- [ ] RED: (20,20) 복제 시 원본 4획 그대로 + 선택 2획 순서의 새 UUID 복제본, 점/선형 변환 불변, tx/ty +20, revision+1. 겹친 동일 모양 2획도 별개 ID다.
- [ ] RED: 없는/다른/삭제 page ID·다른 page stroke ID·stale revision·NaN/Infinity·합산 overflow·revision 한도를 거부하고 입력은 그대로다. 잘못된 문서에 빈 선택이라고 검증을 생략하지 않는다.
- [ ] `swift test --package-path Packages/MiNoteCore --filter InkCommandTests` 실제 RED 확인 → API 구현 → GREEN/전체 core → PROGRESS → main commit.

### Task 2: 선택 편집과 실제 native 이력

**Interfaces:** Task1 API를 소비하고 EditorSession transition/InkUndoCoordinator/CanvasReference의 위 API와 toolbar 버튼을 제공한다.

- [ ] RED: 실제 UI pen → 선택 복제 → pen → Undo3/Redo3의 획 수·위치·모든 ID/순서. 다른 흐름 pen → 선택 삭제 → Undo/Redo → 추가 pen/획 지우개/Undo가 현재 페이지에서 이어진다. 매 저장 경계의 JSON은 외부 read-only observer로 검증한다. 가짜 manager나 프로그램 입력만으로 실제 UI gate를 대체하지 않는다.
- [ ] RED: 같은 모양 2획/복제본/두 번째 복제 후 정확한 선택 대상·ID, 새 획 append/erase/Undo 뒤 alias provenance. 모호한 다른 UUID는 현재 화면/정상 disk 보존 오류로 처리한다.
- [ ] RED: delegate A→final B canvas capture→delete/duplicate→queued B callback에서 B와 명령 각각 한 Undo/Redo. 빈 선택은 이력을 추가하지 않고 기존 Redo를 지우지 않는다. 실패 명령도 문서/선택/이력을 바꾸지 않는다.
- [ ] 위 app API/공통 transition 등록/버튼 구현 → 관련 app tests/실제 UI GREEN → PROGRESS → main commit. M2-A system Undo eligibility와 capture-before-delegate 회귀를 유지한다.

### Task 3: 저장·백업·PDF·독립 왕복

**Interfaces:** Task2 session/history를 소비하고 같은 UUID 계약으로 저장/복원/독립 편집이 검증된 선택 명령을 제공한다.

- [ ] RED: 삭제/복제 후 autosave/reopen/`.minote` 새 노트 복원에서 모든 IDs/metadata/PDF bytes 유지, 선택/Undo는 복원하지 않음. 실패하지 않는 복제본만 새 UUID다.
- [ ] RED: backup 실제 writer gate/ENOSPC에서 직접 manager Undo/Redo stack 보존·현재 drawing/양 disk 보존·retry 후 정확한 replay; 구조/page 전환의 이전 callback/명령 거부. queued final input도 유지한다.
- [ ] RED: 0/90/180/270 crop PDF 복제 (20,20)의 실제 pixel·삭제 원위치·선택 테두리 비출력·원본 SHA 불변.
- [ ] actual app 생성 source/복제 fixture → independent JS의 동일 삭제/복제 결과 비교 → JS 추가 편집 → iPad 재편집/Undo/save/reopen. 도구의 명령으로 구현한 독립 소비자가 비교하며 단순 기대 JSON 복사로 대체하지 않는다.
- [ ] 관련 core/app/Node fixture 검증 GREEN → PROGRESS → main commit. tool README와 fixture provenance를 기록한다.

### Task 4: 양 OS 검증·리뷰·인계

**Interfaces:** Task1~3 결과를 소비하고 완료 여부/근거/미검증/다음 시작점을 저장소와 Notion에 제공한다.

- [ ] core/Node/v2·v3·선택 명령 fixture check와 app 전체/실제 UI를18.6→26.4 순차 실행,26 새 DerivedData/cacheOFF. 실제 입력·save/relaunch·기존 PDF/library/backup 동작을 포함한다. 기존 simulator/user 데이터 삭제나 reseed 없음.
- [ ] fresh reviewer 한 번, Review Focus 전부 전달. Important는 원인 확인/실제 RED→수정→GREEN 뒤 마감하고 declined 항목을 판단한다. 실기기 결과를 가정하지 않는다.
- [ ] AGENTS/PROGRESS/README/milestone/Notion append·재조회로 실제 결과를 기록한다. 다음 M2-B2 clipboard는 계획만 작성한다. main commit/clean, no push.

## 계획 자기 점검과 재개

현재 페이지 삭제·복제에만 scope를 고정했고 Foundation 명령→native 이력→영속/교환→전체 gate 순서를 유지했다. 다섯 Review Focus마다 해당 Task의 회귀가 있다. API 이름/반환형은 위 파일별 계약과 일치한다. 새 schema/외부 클립보드/후속 객체를 끼워 넣지 않는다.

첫 작업: AGENTS→PROGRESS→이 계획→Git 상태 대조, `InkCommands`, `InkCanvasView`, `InkUndoCoordinator`, `NoteCanvas` 캡처와 M2-A 최종 회귀 읽기 → Task1 두 명령의 RED. M2-A를 다시 구현하지 않는다. 사용자 지정 직접 구현/단계 끝 한 번 리뷰 방식을 유지한다.
