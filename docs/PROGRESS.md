# MiNote 개발 진행 기록

## 현재 상태
- 완료 단계: **M0-A — iPad 빈 페이지 필기·로컬 저장·복원**
- 작업 공간: `/Users/minwookim/Documents/GitHub/MiNote`
- 브랜치: `main`
- 시작 기준 커밋: `9695ab6`; 사전 모델·저장소 체크포인트: `dfa943d`
- M0-A 구현 커밋: `fedd789` (`feat(ipad): complete M0-A writing and local recovery`)
- main 통합: `origin/codex/ipad-foundation`에서 `b07e9e2`까지 fast-forward 병합. 이후 사용자가 GitHub Desktop에서 `a943a49`를 push했고 local/main, origin/main, 실제 원격 main 일치를 확인했다.
- 진행 단계: **M0-B — PDF 가져오기·필기·내보내기**. 2026-10-01 사용자가 나머지 개발 재개를 요청했다. 한 번에 한 단계 원칙에 따라 이번 단위는 M0-B 전체다.
- M0-B 기준 커밋: `a943a49`; 현재 단계 1 좌표·PDFKit 기술 검증을 시작한다. 아직 M0-B 완료 기능은 없다.

## M0-A 완료 결과
- SwiftUI·UIKit·PencilKit 앱과 Foundation 전용 `MiNoteCore` Swift Package를 구성했다. 외부 라이브러리는 없다.
- A4 한 페이지에 펜·형광펜·획 지우개, 색상·두께 조절, 실행 취소·다시 실행, 손가락 입력 전환, 확대·스크롤을 구현했다.
- 획의 제어점, 시간, 압력, 크기, 불투명도, 기울기, 색상, 도구, 변환 정보, PencilKit seed와 ID를 플랫폼 독립 JSON 문서에 보존한다.
- 편집 후 자동 저장, 최신 리비전 검사, 원자 교체, 직전 정상본 백업, 오류 표시·재시도를 구현했다. 손상되거나 지원하지 않는 스키마는 빈 문서로 덮어쓰지 않는다.
- 앱은 하나의 편집 창으로 제한했다. M0-A 저장소가 단일 actor/파일을 전제로 하고 있어, 별도 앱 창이 같은 리비전을 읽고 마지막 저장이 앞선 편집을 덮어쓸 가능성을 제거한다.
- 코드 리뷰 후 JSON 손상·문서 무결성 오류일 때만 백업 복구를 허용했다. 실제 파일 읽기·접근 오류는 그대로 전파하고 원본과 백업을 보존한다.
- PencilKit의 기본 획에서 실제로 쓰이는 `secondaryScale`을 공통 모델에 추가했다. 기존 schema v1 문서에 값이 없으면 기본값 1로 읽는다.

## 검증 근거
- `swift test --package-path Packages/MiNoteCore`: 16개 테스트, 0 실패. main 체크아웃 로그: `/private/tmp/minote-main-core.log`.
- iPad Pro 11 M4 / iPadOS 18.6, main 체크아웃 `xcodebuild ... test`: 앱 단위 테스트 11개와 UI 테스트 1개 통과. 로그: `/private/tmp/minote-main18.log`; 결과: `/private/tmp/minote-main18.xcresult`.
- iPad Pro 11 M5 / iPadOS 26.4, main 체크아웃 전체 테스트: 앱 단위 테스트 11개와 UI 테스트 1개 통과. 로그: `/private/tmp/minote-main26.log`; 결과: `/private/tmp/minote-main26.xcresult`.
- UI 테스트에서 획 입력, undo/redo, `저장 완료`, 앱 재실행 후 복원을 확인했다.
- 빌드된 `MiNote.app/Info.plist`에서 `UIApplicationSupportsMultipleScenes = false`, `CFBundleExecutable = MiNote`를 확인했다. 빌드 로그: `/private/tmp/minote-scene-review-build3.log`.
- `git diff --check` 통과.
- 별도 리뷰의 데이터 손실 우려 2건을 각각 회귀 테스트·실제 빌드 설정 검증으로 수정했다. 저장소는 파일 없음만 따로 판별하며, 손상 JSON만 백업 복구하고 접근 오류·디렉터리 경로는 그대로 보존한다.
- 미실행 검증: 실기기 Apple Pencil 지연, 손바닥 입력 거부, 발열. 물리 iPad에서 확인해야 한다.

## 다음 재개 지점
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
- [ ] 1: PDFKit·좌표·회전·crop 검증
- [ ] 2: schema v2 마이그레이션과 안전한 PDF 자산 가져오기
- [ ] 3: 페이지 이동·필기·자동 저장·복원
- [ ] 4: 필기 포함 PDF 내보내기
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
