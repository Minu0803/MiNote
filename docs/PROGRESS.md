# MiNote 개발 진행

## 현재 상태
- 단계: M0-A — 진행 중
- 작업 위치: /Users/minwookim/.codex/worktrees/ipad-foundation/MiNote
- 브랜치: codex/ipad-foundation
- 기준 커밋: 9695ab6
- 승인: 직접 구현, 단계 말 별도 리뷰, 저장소 기록 + Notion 요약, iPadOS 18+, 시뮬레이터 우선
- 현재 작업: 모델·저장소·PencilKit 변환 검증 완료, 편집 세션·UI 개발
- 다음 시작점: EditorSession 실패·재시도 테스트 작성 후 화면 연결

## 작업 상태
- [x] 관리 작업 공간·브랜치 준비
- [x] 작업 재개 지침·구현 계획 작성
- [x] A1 공통 모델·앱 구성 (실행 셸까지)
- [ ] A2/A3 필기 화면·PencilKit 변환
- [ ] A4 저장·복원·오류 처리
- [ ] A5 두 OS 검증·코드 리뷰·Notion 기록

## 검증
- Xcode 27 / Swift 6.4 확인. 설치된 시뮬레이터: iPadOS 18.6, 26.4 포함.
- swift test --package-path Packages/MiNoteCore: 5개 통과 (2026-09-26). RED에서 모델 타입 부재를 확인한 뒤 구현. 로그: /private/tmp/minote-core-green.log
- Xcode 프로젝트 생성 완료. iPadOS 18.6 어댑터 테스트 RED: 미구현 변환으로 4개 실패, 미지원 입력 거부 1개 통과.
- 저장 테스트 RED: DocumentStore 타입 부재로 실패 확인. 이후 구현 완료, GREEN 검증 예정.
- 실기기 Pencil 지연·손바닥 입력·발열: 확인 대기.

## 결정 및 제한
- 한 문서·한 A4 페이지를 구현. 공통 데이터는 JSON, PencilKit 바이트가 원본이 아님.
- 작업 기록은 이 추적 파일에 영구 보존한다. Superpowers 임시 로그 정리는 이 파일에 적용하지 않는다.
- 자동 원격 push·배포는 이번 범위에 없음.

## Notion
- 마지막 반영: 2026-09-26 제품 계획서. M0-A 구현 결과는 단계 종료 시 반영.

## 체크포인트 — 데이터 기반 완료
- 공통 패키지: 모델/코덱 5개 + 저장소 8개 = 13개 테스트 통과. 로그 /private/tmp/minote-core-green.log.
- xcodebuild test, MiNoteTests, iPadOS 18.6: 어댑터 5개 테스트 통과. 로그 /private/tmp/minote-adapter-green.log.
- 앱 화면은 아직 Text 셸이며 UI 테스트는 미실행. 26.4 검증도 대기.
- 결정: 화면의 실제 오류·재시도 연결을 위해 Task 3의 저장소를 Task 2 화면보다 먼저 구현. 저장 성공은 Void, 로드 결과는 문서와 백업 복구 여부로 최소화.
