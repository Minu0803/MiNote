# M0-A iPad Foundation Implementation Plan

> For agentic workers: Use superpowers:executing-plans. 직접 구현 후 단계 말 별도 코드 리뷰.

**Goal:** 한 A4 페이지에 필기하고 저장·재실행 후 계속 편집한다.
**Architecture:** SwiftUI 셸 + UIKit/PencilKit 캔버스. Foundation 전용 로컬 Swift Package MiNoteCore에 문서 모델과 JSON 저장소. 앱은 @MainActor, 저장소는 actor.
**Tech Stack:** Xcode 27, Swift 6, iPadOS 18+, XCTest, Swift Package Manager. 외부 의존성 없음.
**Spec:** docs/superpowers/specs/2026-09-26-minote-product-design.md 및 승인된 M0-A 계획.

## Global Constraints
- 한 문서, 한 A4 페이지. 펜·형광펜·획 지우개, undo/redo, 색상·굵기, 손가락 모드, 확대·스크롤.
- schemaVersion 1. 페이지 좌상단 원점, 72pt/in. A4 595.2756 × 841.8898pt.
- 기본 PencilKit contentVersion1 도구만 사용. bitmap eraser·마스크·기타 브러시는 지원하지 않으며 명시적 오류.
- 문서 JSON은 Documents/MiNote/document.json, 직전 정상본은 document.backup.json. 모르는 스키마를 덮어쓰지 않는다.
- 실제 Pencil 검증은 미완료로 표시한다.

## Review Focus
1. 오래된 저장 요청이 새 리비전을 덮어쓰지 않는가.
2. 원본 손상·미래 버전에서 백업 복구가 데이터 삭제로 이어지지 않는가.
3. PencilKit 변환에서 획 ID·제어점·색상·변환·randomSeed를 보존하는가.
4. 저장 중 추가 편집·재시도·백그라운드 전환이 마지막 필기를 잃지 않는가.
5. 확대·회전·undo/redo가 저장 상태와 일치하는가.
6. 파일 읽기 오류가 JSON 손상처럼 취급되어 백업으로 조용히 되돌아가지 않는가.
7. 같은 노트가 두 편집 창에서 동시에 열려 최신 획이 덮어쓰이지 않는가.

## Task 1: 공통 문서·코덱
- Produces: NoteDocument / NotePage / InkStroke / InkPoint / InkColor / InkTransform, DocumentCodec.encode/decode.
- [x] 직렬화 왕복·미래 스키마·비정상 좌표·중복 ID 테스트 RED.
- [x] Codable/Sendable 모델, 명시적 검증·코덱 구현.
- [x] swift test GREEN, 진행 기록·커밋.

## Task 2: 필기 변환·앱 화면
- Consumes: 공통 모델.
- Produces: InkAdapter.decode(strokes:) -> PKDrawing, encode(drawing:preserving:) -> [InkStroke].
- [x] 제어점·색상·변환·ID 보존, 미지원 도구·mask 거부의 XCTest RED.
- [x] 앱·로컬 패키지 참조·테스트 타깃·MiNote 공유 스킴 구성.
- [x] SwiftUI 툴바 + PKCanvasView, 도구·undo/redo·줌 구현.
- [x] iPadOS18.6/26.4 테스트 GREEN. 구현/최종 기록 커밋 대기.

## Task 3: 저장소와 편집 세션
- Consumes: NoteDocument, DocumentCodec, InkAdapter.
- Produces: DocumentStore.load() -> LoadedDocument?, save(document:) throws -> Void; EditorSession의 문서/저장 상태.
- [x] 재열기·직전 백업·손상 복구·쓰기 실패·오래된 리비전·미래 스키마 보존 테스트 RED.
- [x] actor 직렬 저장, 원자적 파일 교체, 백업 복구 상태, 버전 오류 보호 구현.
- [x] EditorSession의 재시도·리비전·저장 중 추가 편집 테스트 RED → 구현.
- [x] 저장소와 화면 연결. 초기 불러오기 실패 시 편집 차단·재시도, 쓰기 실패 시 메모리 필기 유지.
- [x] swift test / 앱 XCTest GREEN (18.6·26.4). 커밋 대기.

## Task 4: 통합 검증 및 인계
- [x] UI 시험: 시뮬레이터 터치 필기·undo/redo·앱 재실행 복원.
- [x] iPad Pro 11 M4 / iPadOS18.6와 iPad Pro 11 M5 / iPadOS26.4에서 MiNote 스킴 빌드·테스트.
- [x] 별도 에이전트 리뷰 1회와 중요 이슈 수정.
- [x] 회귀 테스트: 파일 읽기 오류 때 백업 복구·원본 교체가 발생하지 않음.
- [x] 회귀 테스트: 문서 경로가 디렉터리일 때 백업 복구·경로 교체가 발생하지 않음.
- [x] 같은 문서의 교차 창 덮어쓰기를 피하도록 다중 장면 비활성화, 빌드 산출 Info.plist 값 확인.
- [x] README·PROGRESS·Notion 갱신 및 단계 커밋 (`fedd789`).
- [x] M0-A 결과에 근거한 다음 단계 M0-B 계획 작성.

## 실행 명령
- Core: swift test --package-path Packages/MiNoteCore
- iPad18.6: xcodebuild -project MiNote.xcodeproj -scheme MiNote -destination 'platform=iOS Simulator,id=7964CDF4-782A-44C2-BC51-1176AF6C67AB' -derivedDataPath /private/tmp/minote-derived test CODE_SIGNING_ALLOWED=NO
- iPad26.4: 같은 명령에 destination id=423D4FF6-C678-45F9-9D3E-CB886EE82462.
- Core tests cover codec/store, app XCTest covers adapter/session, UI tests exercise actual controls and disk persistence.
