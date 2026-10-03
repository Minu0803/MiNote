# MiNote 작업 지침

1. 시작할 때 `docs/PROGRESS.md`, 현재 단계 계획, 관련 코드와 Git 상태를 읽는다.
2. M0-A, M0-B, M0-C, M1-A 로컬 라이브러리는 완료했다. 다음 개발 단위는 M1-B 페이지/다중 PDF이며 `docs/superpowers/plans/2026-10-03-m1-b-pages-and-pdfs.md`에 따라 진행한다. M1-C 백업/정리는 이후 실제 결과를 반영해 계획한다. 한 번에 한 개발 단위를 완료·검증·기록한다.
3. 사용자는 이후 작업을 `main`에서 직접 진행하길 원한다. 기본 저장소 `/Users/minwookim/Documents/GitHub/MiNote`의 `main`에서 작업한다. 별도 브랜치·worktree·PR을 만들지 않는다. 사용자가 이 선호를 바꾸면 그 지시를 따른다.
4. 앱은 iPadOS 18 이상. UI/PencilKit 코드는 앱에, 공통 문서·저장은 Foundation만 사용하는 MiNoteCore에 둔다.
5. 작은 작업마다 관련 테스트를 실행하고 결과·미검증 항목·다음 작업을 PROGRESS에 기록한 후 커밋한다. 긴 작업 전에도 체크포인트를 기록한다.
6. 테스트 실패나 미실행을 성공으로 기록하지 않는다. 실제 Pencil 평가는 시뮬레이터 검증과 구분한다.
7. 직접 구현을 기본으로 하고 단계 끝에 별도 에이전트 코드 리뷰를 한 번 진행한다.
8. 단계 완료 시 Notion https://app.notion.com/p/3e76538f55f68051a2fad6f22562bd3d 에 결과·판단·검증·제한을 추가한다.
9. 기록은 대화 축약 후에도 유지한다. 사용자 작업을 덮어쓰거나 작업 기록을 삭제하지 않는다.
