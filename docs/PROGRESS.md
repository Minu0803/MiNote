# MiNote 개발 진행 기록

## 현재 상태
- 완료 단계: **M0-A — iPad 빈 페이지 필기·로컬 저장·복원**
- 작업 공간: `/Users/minwookim/Documents/GitHub/MiNote`
- 브랜치: `main`
- 시작 기준 커밋: `9695ab6`; 사전 모델·저장소 체크포인트: `dfa943d`
- M0-A 구현 커밋: `fedd789` (`feat(ipad): complete M0-A writing and local recovery`)
- main 통합: `origin/codex/ipad-foundation`에서 `b07e9e2`까지 fast-forward 병합. 이후 사용자가 GitHub Desktop에서 `a943a49`를 push했고 local/main, origin/main, 실제 원격 main 일치를 확인했다.
- 진행 단계: **M0-B — PDF 가져오기·필기·내보내기**. 2026-10-01 사용자가 나머지 개발 재개를 요청했다. 한 번에 한 단계 원칙에 따라 이번 단위는 M0-B 전체다.
- M0-B 기준 커밋: `a943a49`; 현재 기능·최종 자동 검증·별도 리뷰 수정을 완료했다. 단계 종료 문서·Notion 반영과 최종 커밋을 마무리 중이다.

## M0-A 완료 결과
- SwiftUI·UIKit·PencilKit 앱과 Foundation 전용 `MiNoteCore` Swift Package를 구성했다. 외부 라이브러리는 없다.
- A4 한 페이지에 펜·형광펜·획 지우개, 색상·두께 조절, 실행 취소·다시 실행, 손가락 입력 전환, 확대·스크롤을 구현했다.
- 획의 제어점, 시간, 압력, 크기, 불투명도, 기울기, 색상, 도구, 변환 정보, PencilKit seed와 ID를 플랫폼 독립 JSON 문서에 보존한다.
- 편집 후 자동 저장, 최신 리비전 검사, 원자 교체, 직전 정상본 백업, 오류 표시·재시도를 구현했다. 손상되거나 지원하지 않는 스키마는 빈 문서로 덮어쓰지 않는다.
- 앱은 하나의 편집 창으로 제한했다. M0-A 저장소가 단일 actor/파일을 전제로 하고 있어, 별도 앱 창이 같은 리비전을 읽고 마지막 저장이 앞선 편집을 덮어쓸 가능성을 제거한다.
- 코드 리뷰 후 JSON 손상·문서 무결성 오류일 때만 백업 복구를 허용했다. 실제 파일 읽기·접근 오류는 그대로 전파하고 원본과 백업을 보존한다.
- PencilKit의 기본 획에서 실제로 쓰이는 `secondaryScale`을 공통 모델에 추가했다. 기존 schema v1 문서에 값이 없으면 기본값 1로 읽는다.

## M0-A 검증 근거 (이전 기록)
- `swift test --package-path Packages/MiNoteCore`: 16개 테스트, 0 실패. main 체크아웃 로그: `/private/tmp/minote-main-core.log`.
- iPad Pro 11 M4 / iPadOS 18.6, main 체크아웃 `xcodebuild ... test`: 앱 단위 테스트 11개와 UI 테스트 1개 통과. 로그: `/private/tmp/minote-main18.log`; 결과: `/private/tmp/minote-main18.xcresult`.
- iPad Pro 11 M5 / iPadOS 26.4, main 체크아웃 전체 테스트: 앱 단위 테스트 11개와 UI 테스트 1개 통과. 로그: `/private/tmp/minote-main26.log`; 결과: `/private/tmp/minote-main26.xcresult`.
- UI 테스트에서 획 입력, undo/redo, `저장 완료`, 앱 재실행 후 복원을 확인했다.
- 빌드된 `MiNote.app/Info.plist`에서 `UIApplicationSupportsMultipleScenes = false`, `CFBundleExecutable = MiNote`를 확인했다. 빌드 로그: `/private/tmp/minote-scene-review-build3.log`.
- `git diff --check` 통과.
- 별도 리뷰의 데이터 손실 우려 2건을 각각 회귀 테스트·실제 빌드 설정 검증으로 수정했다. 저장소는 파일 없음만 따로 판별하며, 손상 JSON만 백업 복구하고 접근 오류·디렉터리 경로는 그대로 보존한다.
- 미실행 검증: 실기기 Apple Pencil 지연, 손바닥 입력 거부, 발열. 물리 iPad에서 확인해야 한다.

## M0-A 종료 시 다음 재개 지점 (이전 기록)
- M0-A 코드와 검증 근거는 `fedd789`에 있다. 최종 테스트 로그는 위 검증 항목을 따른다.
- M0-B 실행 계획이 저장소와 Notion에 있다. 다음 작업에서는 PDFKit overlay API를 iOS 18에서 확인하고, 회전·crop box를 포함한 좌표 fixture를 만드는 기술 검증부터 시작한다.
- M0-B 구현은 별도 단계로 유지한다. PDF 페이지 매핑 검증 전에 문서 모델이나 캔버스 구조를 확정하지 않는다.
- 사용자는 이후 코딩을 모두 기본 저장소의 `main`에서 진행하도록 지정했다. 새 브랜치·worktree·PR을 만들지 않는다.

## 계속 적용할 규칙
- 재개 시 이 문서, Git 상태, 마지막 검증 로그를 대조하고 진행 중 변경을 먼저 확인한다.
- 장시간 작업 전과 작은 작업 직후 진행 상태를 갱신한다. 통과하지 않은 검증은 완료로 표시하지 않는다.
- 단계 종료마다 앱에서 작동하는 결과, 기술 결정, 테스트 근거, 제한, 다음 시작점을 Notion과 저장소에 기록한다.
- 원격 push·배포는 승인된 범위에 포함하지 않는다.

## Notion
- 문서: [MiNote 제품 계획서](https://app.notion.com/p/3e76538f55f68051a2fad6f22562bd3d?pvs=204)
- 마지막 반영: 2026-09-26 09:33:38 UTC (2026-09-26 18:33:38 KST). M0-A 결과와 M0-B 계획 요약을 새 섹션으로 추가하고 다시 읽어 내용·검증·커밋을 확인했다.

## M0-B 실행 체크포인트 (2026-10-01)
- [x] 1: PDFKit·좌표·회전·crop 검증
- [x] 2: schema v2 마이그레이션과 안전한 PDF 자산 가져오기
- [x] 3: 페이지 이동·필기·자동 저장·복원
- [x] 4: 필기 포함 PDF 내보내기
- [ ] 5: 양 시뮬레이터 전체 검증·별도 리뷰·Notion·기록
- 결정: 사용자 승인된 제품 설계/기존 M0-B 계획을 실행한다. main 직접 작업 지시가 격리 브랜치 절차보다 우선한다.
- 사전 검사: 1의 좌표가 2 페이지 크기/메타데이터, 3 화면, 4 출력에 공통으로 필요하다. 2 저장의 문서 리비전은 3 가져오기/페이지 편집에서도 같은 문서 ID로 이어간다. 4는 2 원본 자산을 읽되 수정하지 않는다.
- 환경: sandbox 내 simctl은 서비스 접근 권한 때문에 실패했다. 승인된 시뮬레이터 검증용 권한으로 다시 조회하여 18.6/26.4 기기를 확인했다.
- 다음 즉시 작업: 좌표 및 PDF fixture 테스트를 먼저 만들고 실패를 확인한다.

### M0-B 1A: 좌표 기초 검증
- `MiNote/PDFGeometry.swift`, `MiNoteTests/PDFFixture.swift`, `PDFGeometryTests.swift`: 비영점 media/crop 원점과 0/90/180/270도 회전 fixture의 변환·역변환을 검증했다.
- 실패 근거: `/private/tmp/minote-m0b-geometry-red.log` (어댑터 없음). 첫 실행의 8 좌표 실패는 PDFKit이 fixture 재저장 시 원점을 정규화했기 때문이었다. `/private/tmp/minote-m0b-geometry-diagnose.log`에서 실제 bounds를 확인해 raw PDF fixture로 교체했다.
- 통과: `xcodebuild ... -only-testing:MiNoteTests/PDFGeometryTests ... test`, iPadOS 18.6, 1 테스트/0 실패, `/private/tmp/minote-m0b-geometry-green2.log`.
- 결정: PDFKit overlay API(iOS 16+)는 조사했다. M0-B는 기존 `PageZoomHost`에서 PDF 배경+한 개 PencilKit 캔버스와 명시적 페이지 이동을 사용한다. 회전된 crop box 크기를 문서 크기로 쓰므로 PDFView의 overlay 재생성·gesture 경쟁을 피하면서 화면상의 같은 좌표를 유지한다. 페이지 수와 무관하게 화면 캔버스는 하나다. 실제 입력/zoom/화면 회전 검증은 단계 3/5에서 수행한다.
- 다음: schema v2 migration/여러 페이지 테스트의 실제 실패를 확인했다 (`/private/tmp/minote-m0b-core-red2.log`). Foundation 모델을 확장한다. 아직 미커밋인 core 테스트는 이 다음 작업에 해당한다.

### M0-B 2A: Foundation 문서·자산 저장 완료
- schema v2는 여러 페이지, `PDFAsset` UUID/상대 경로/파일명/페이지 수/바이트 수/가져온 시점, 페이지별 media/crop/rotation/index를 보존한다. v1 A4는 ID·리비전·획을 유지해 v2로 읽고, 저장 시 원본 v1 바이트를 backup으로 먼저 보존한다.
- `DocumentStore.attachPDF`는 기대 리비전을 검사하고 PDF 자산을 먼저 원자 저장한 후 JSON을 갱신한다. 기존 A4 페이지는 남고 PDF 페이지를 추가한다. 현재 노트에 한 PDF만 연결하며 후속 가져오기로 원본·필기를 교체하지 않는다. 여러 PDF/노트 선택은 M1 범위다.
- 자산 없음·크기 불일치는 백업의 빈 노트로 자동 복구하지 않고 오류로 차단한다. 가져오기 실패 때 기존 JSON을 유지하며 중단 후 orphan 자산은 안전하게 남는다(정리는 M1).
- 검증: `swift test --package-path Packages/MiNoteCore` 24 테스트/0 실패, `/private/tmp/minote-m0b-core-green.log`. 마이그레이션/다중 페이지 실제 RED는 `minote-m0b-core-red2.log`, PDF 자산 API 누락 RED는 `minote-m0b-assets-red2.log`. 중간 구문 오류는 수정 후 전체 통과했다.
- 다음: 앱에서 security-scoped 파일 조정·PDF 검증·페이지 세션 연결을 구현한다. 잠금/잘림/미지원 크기 및 세션 실패 보존을 테스트한다. PDF 파일 앱 흐름은 아직 미구현이다.

### M0-B 2B/3A: 가져오기·페이지 세션
- `PDFImporter` actor는 security scope를 복사 완료까지 유지하고 NSFileCoordinator로 원본을 읽는다. 암호 잠금, PDF header/EOF 없음, 빈 PDF, 미지원 페이지를 거부한다. PDFKit 객체는 actor 안에 두고 portable metadata/bytes만 넘긴다.
- `EditorSession`은 여러 페이지의 drawing, 페이지마다 독립 획 ID 이력, 마지막 페이지 ID, 기존 문서 보존 가져오기 오류를 처리한다. 동일 획을 다른 페이지에 그릴 때 global history가 ID를 재사용한 실제 RED를 확인했고 페이지별 이력으로 수정했다.
- 검증: iPadOS 18.6 `xcodebuild ... -only-testing:MiNoteTests ... test` 앱 단위 16 테스트/0 실패 (`/private/tmp/minote-m0b-import-green3.log`). 잠금/잘림, 원본 bytes/geometry, 실패 후 현재 필기, 페이지 왕복·재실행, 동일 모양 획의 독립 ID를 검증했다.
- 제한은 임시 보수값 100MB/500페이지/한 변 2,000pt다. 단계 5에서 여러 페이지의 화면 뷰/bitmap 메모리 상한을 측정하고 근거를 남긴다. 실제 대형 PDF·실기기 성능은 아직 미검증이다.
- 다음 즉시 작업: `PDFCanvasTests` RED 확인 → PDF 배경 렌더러, 가변 페이지 크기 zoom host, 페이지 이동과 파일 가져오기 UI. 현재 canvas 테스트는 이 작업의 미커밋 변경이다.

### M0-B 3B/4 작업 중 체크포인트
- PDF 배경은 PDFKit crop-box 렌더링과 top-left 변환을 사용한다. 4 회전의 red/green corner pixel이 기대 위치에 있으며 zoom 후 viewport 변경에도 canvas.bounds가 문서 크기를 유지한다. 앱 단위 18/0 (`minote-m0b-canvas-green.log`).
- 파일 선택/페이지 이동 UI를 연결했다. UI 테스트에서 import 버튼은 존재하나 picker 검색창이 나타나지 않아 **아직 UI 검증 실패**다. `minote-m0b-ui-green2.log`, `minote-m0b-picker-diagnose.log`가 실제 실패 근거이며 후자에 접근성 트리가 있다. 원인 조사 후 재검증한다.
- 단계 4 출력 테스트를 작성했다. 다음: export API 없는 RED를 확인하고 원본 geometry/텍스트/획 위치 검증을 통과시킨 뒤 picker UI 문제로 복귀한다.
- 출력 spike 판단: PDFKit burnInAnnotations는 nonzero MediaBox 원점을 (0,0)으로 정규화한다. custom annotation은 원본 content의 원점 이동을 별도로 적용해야 한다 (`minote-m0b-export-diagnose.log`, 4 회전 blue bbox로 확인). 출력은 media 크기/rotation/crop의 media 대비 위치와 **보이는 페이지 좌표**를 보존하는 것으로 판단했다. raw box 원점까지 동일한 출력은 public PDFKit writer로 보장하지 않는다. PDF 원본과 편집 모델은 전혀 바꾸지 않는다.
- 출력 판단: PencilKit 공개 API는 vector drawing export를 제공하지 않아 획만 최대 216dpi/한 변 4096px 이미지로 합성한다. 원본 PDF 텍스트/벡터 유지와 정확한 필기 모양을 우선한다. 확대 시 필기 해상도 및 원본 annotation/form의 고정화는 앱 안내·Notion·완료 보고에 남긴다.

### M0-B 4A: PDF 합성 출력 기반 완료
- 출력 writer의 원점 이동을 custom annotation에 적용하여 4 회전 모두 canonical (130,120) 획 pixel이 유지된다. 원본 bytes, media 크기/crop 상대 위치/rotation, 검색 가능한 text, 출력 실패 시 원본·기존 대상 보존을 검증했다.
- `xcodebuild ... -only-testing:MiNoteTests ... test` 20 앱 단위 테스트/0 실패 (`/private/tmp/minote-m0b-export-green2.log`). 공유 UI는 아직 연결 전이다.
- 내보내기는 PDFKit writer를 사용하고 원본 파일을 건드리지 않는다. 텍스트/벡터 원본 위에 최대 216dpi, max 4096px의 PencilKit 필기 이미지를 고정 합성한다. vector ink는 후속 엔진 검증에서 검토한다.
- 다음: picker 고정 루트 컨테이너 수정의 UI 테스트 결과 확인. 공유 시트 연결·백그라운드 출력·메모리 검증·전체 리뷰/최종 검증으로 이어간다.
- Picker 원인 확인: 실제 화면에는 파일 선택기가 표시되고 검색은 버튼 뒤에 숨겨져 있었다. 화면/런타임/뒤늦은 AX 트리로 확인했다 (`minote-picker-wait-screen.png`, `minote-m0b-picker-wait.log`). 테스트는 존재하지 않는 검색창을 기다리고 있었다. 시스템 파일 선택기에서 나의 iPad → MiNote → fixture를 선택하는 경로로 변경했다. 다음 실행은 테스트 runner bootstrap crash로 UI 자체가 시작되지 않았으므로 아직 통과 아님 (`minote-m0b-picker-browse.log`).

### M0-B 3/4 기능 연결 완료, 단계 5 검증 중
- iPadOS 18.6 전체 앱 검증: **단위 23/0, UI 2/0** (`/private/tmp/minote-m0b18-full.log`, `/private/tmp/minote-m0b18-full.xcresult`). PDF 입력 undo/redo, 확대, 화면 회전, 페이지 이동·relaunch, QuickLook PDF 미리보기와 실제 공유 시트의 파일 저장 항목까지 확인했다.
- 500페이지 sequential render의 simulator phys_footprint는 85,150,432 → 93,424,400 bytes, 증가 8,273,968 bytes (약 7.9MiB). 한 페이지 뷰/캔버스를 재사용하므로 500개의 bitmap을 보관하지 않는다. fixture는 텍스트·벡터 소형 페이지이며 이미지가 많은 실제 100MB PDF의 성능을 입증하는 수치는 아니다. 한 변 2,000pt/100MB/500페이지 보수 상한을 유지하고 실기기/다양한 큰 자료는 M3 검증에 남긴다.
- PDF 출력은 별도 작업에서 수행한다. UI 없는 InkAdapter 변환은 MainActor 제한을 제거했고 background export도 pixel/geometry 테스트를 통과했다. 공유 전 최신 revision을 저장하며 출력 중 편집을 잠근다.
- 중복 import의 실제 RED에서 늦은 요청이 stale revision 오류로 끝났다. 작업 잠금을 첫 await 전에 획득하고 문서/asset/마지막 페이지 선택을 한 트랜잭션으로 완료하도록 수정했다. commit 후 자산 reopen 실패는 오래된 메모리 문서 편집을 차단하고 authoritative load를 재시도한다.
- 아직 남음: iPadOS 26.4 전체 검증, 최신 core 전체 테스트, 한 차례 별도 코드 리뷰, Notion 결과 반영 및 최종 기록. UI 재실행 테스트는 기존 fixture 노트가 있으면 재가져오기를 건너뛰며, 첫 실제 Files import 통과 근거는 `minote-m0b-flow-green.log`에 있다.
- 최신 core 전체 검증: `swift test --package-path Packages/MiNoteCore`, 24 테스트/0 실패 (`/private/tmp/minote-m0b-core-final.log`). 26.4 전체 테스트는 현재 실행 중이다. 18.6 UI/출력 기능과 core 변경을 커밋한 후 별도 리뷰를 진행한다.
- iPadOS 26.4 전체 검증도 완료: 단위 **23/0**, UI **2/0** (`/private/tmp/minote-m0b26-full.log`, `/private/tmp/minote-m0b26-full.xcresult`). 첫 Files import와 공유 항목을 포함했다. 500페이지 소형 vector fixture footprint는 67,619,144 → 79,104,376 bytes, 증가 11,485,232 bytes (약 11.0MiB). 실기기·실제 이미지 PDF 성능과 구분한다.
- 코드 리뷰: 별도 `/root/m0b_code_review`가 `a943a49..26faf40` 범위를 읽기 전용으로 검토 중이다. 구현상 변경은 리뷰 결과를 받은 후 필요한 회귀 테스트와 함께 수행한다.

### M0-B 리뷰 결과와 수정 시작점
- 별도 리뷰에서 Critical은 없었다. Important/P2 2건: (1) import/export 중 header Undo/Redo가 잠기지 않아 세션과 실제 캔버스 이력이 엇갈림, (2) PDF 배경이 zoom 종료 후 낮은 bitmap 배율 그대로여서 확대 가독성 저하. 둘 다 실제 사용자 동작 문제로 받아들이고 회귀 RED→GREEN으로 수정한다.
- Minor/P3: UUID별 내보내기 임시 파일 정리 수명주기 없음. 단계 5의 이번 중요한 수정 범위와 분리해 M1 파일/복구 관리 작업으로 이월한다. 공유가 끝나기 전 파일을 삭제하지 않도록 소비자 수명주기를 설계해야 한다.
- 리뷰가 제외한 판단: 실기기 Pencil·발열 및 이미지가 많은 실제 큰 PDF는 M3에서 검증한다. ink 이미지 출력/원점 정규화/양식·링크 영향은 이미 기록·UI 안내한 의도적 범위다. 페이지 전환 때 canvas의 Undo 이력은 새로 시작하며 현재 페이지의 undo/redo만 보장한다. Background drawing은 작업별 객체를 소유하고 현재 검증을 통과했다.
- 다음: 작업 잠금의 명령 경계 방어와 zoom 후 4096px 안에서의 PDF 재렌더링 테스트를 만들고 실패를 확인한다. 수정 후 두 시뮬레이터 앱 전체 검증을 다시 수행한다.
- 회귀 RED 확인: 새 명령 인터페이스가 없어 최초 빌드 실패(`minote-m0b-review-red.log`), 인터페이스만 연결한 실제 동작 테스트에서 busy undo/redo와 zoom 해상도 모두 실패했다(`minote-m0b-review-behavior-red.log`, 2 테스트/4 assertions 실패).
- P2 명령 수정: 헤더 버튼과 `CanvasReference.undo(in:)`/`redo(in:)` 양쪽에서 `session.isProcessing`을 검사한다. 실제 500페이지 import/export 작업 중 호출하는 회귀 테스트 **1/0** (`minote-m0b-command-green.log`).
- P2 확대 수정 진행: pinch 중에는 기존 backing을 쓰고 zoom 종료/viewport layout에서 PDF 해상도를 갱신한다. 가장 긴 변을 4096px로 제한하며 문서 좌표와 canvas.bounds는 바꾸지 않는다. PDFCanvasTests를 실행 중이며 아직 최종 통과 기록 전이다.
- P2 확대 회귀 및 배경·zoom·500페이지 테스트 **4/0** (`minote-m0b-zoom-green.log`). 배경 해상도를 늘린 후 이 소형 fixture의 footprint 증가 16,957,464 bytes. 현재 18.6/26.4 앱 전체를 재검증 중이다 (`minote-m0b18-review-final.log`, `minote-m0b26-review-final.log`). 다음은 실제 전체 결과 확인 → 단계 문서/Notion → 최종 커밋이다.

### M0-B 리뷰 수정 후 최종 검증 완료
- 18.6 전체 **앱 단위 25/0, UI 2/0**, xcodebuild exit 0 / TEST SUCCEEDED. 로그 `/private/tmp/minote-m0b18-review-final.log`, result `/private/tmp/minote-m0b18-review-final.xcresult`.
- 26.4 전체 **앱 단위 25/0, UI 2/0**, xcodebuild exit 0 / TEST SUCCEEDED. 로그 `/private/tmp/minote-m0b26-review-final.log`, result `/private/tmp/minote-m0b26-review-final.xcresult`.
- 공통 패키지는 마지막 core 변경 이후 **24/0** (`minote-m0b-core-final.log`). 리뷰 수정은 앱/테스트에만 있었으므로 core는 반복 실행하지 않았다.
- 최종 500페이지 fixture footprint: 18.6은 95,095,544 → 113,560,312 bytes (증가 18,464,768; 약 17.6MiB), 26.4는 64,948,576 → 87,067,000 bytes (증가 22,118,424; 약 21.1MiB). zoom 해상도 수정 후의 현재 측정이며 앞선 수치보다 우선한다. 소형 벡터 PDF 한 종류이고 GPU/실기기/큰 이미지 PDF의 상한을 보장하지 않는다.
- 최종 UI 결과에서 내보내기 QuickLook 화면을 추출해 실제 획·5페이지 표시·안내 문구·공유 버튼을 시각 확인했다. 화면 파일은 `docs/assets/m0b-export-preview.png`로 보존한다. 실제 시스템 Files 가져오기는 앞선 fresh 실행 로그에 있으며 최종 UI 재실행은 기존 노트에 필기를 추가해 복원을 확인했다.
- 마지막 실행 명령:
  `xcodebuild -project MiNote.xcodeproj -scheme MiNote -destination 'platform=iOS Simulator,id=7964CDF4-782A-44C2-BC51-1176AF6C67AB' -derivedDataPath /private/tmp/minote-m0b18 -resultBundlePath /private/tmp/minote-m0b18-review-final.xcresult -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test`
  26.4는 device `423D4FF6-C678-45F9-9D3E-CB886EE82462`, derivedData `/private/tmp/minote-m0b26`, result `/private/tmp/minote-m0b26-review-final.xcresult`로 실행했다.
- 현재 미커밋 변경: P2 캔버스 명령/zoom 수정, 회귀 테스트, README/단계 계획/다음 M0-C 계획, 이 기록. 다음 즉시 작업: P2 수정 커밋 → Notion에 검증된 M0-B 결과 추가 → 최신 동기화 시점과 최종 SHA를 기록·커밋한다.
