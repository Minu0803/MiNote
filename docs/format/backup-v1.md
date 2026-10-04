# MiNote 편집 원본 백업 v1

`.minote`는 문서 schema3와 모든 등록 PDF 원본을 보존하는 노트별 백업이다. 배포 PDF와 다르며 Undo 기록·썸네일·폴더는 포함하지 않는다.

컨테이너는 [PKWARE ZIP 규격](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)의 ZIP32 stored(method0) subset이다. little endian local headers, central directory, EOF의 22byte EOCD를 사용한다. 작성기는 UTF-8 flag와 1980-01-01 DOS date를 사용한다. 압축/암호/ZIP64/data descriptor/extra fields/주석/분할 디스크/링크는 지원하지 않는다. 일반 ZIP 파일 전체 호환을 약속하지 않는다.

항목은 `manifest.json`, `document.json`, 정확한 `assets/<대문자 UUID>.pdf`만 허용한다. 경로 중복·절대 경로·backslash·traversal, header 불일치·offset 겹침·틈·CRC/길이 불일치·truncation을 거부한다. 문서와 manifest가 요구하는 항목 집합이 정확히 같아야 한다. CRC는 우발적 손상을 검출하며 인증 서명은 아니다.

manifest 필드는 `archiveVersion:1`, `documentID`, `schemaVersion:3`, `revision`, `entries:[{name,byteCount,crc32}]`다. entries는 document와 자산만 포함하며 manifest 자신은 ZIP CRC로 검증한다. 원본 파일명은 metadata일 뿐 추출 경로로 사용하지 않는다. future schema는 대체하지 않고 오류로 보존한다.

상한: archive640MiB, document128MiB, manifest1MiB, 항목1002개. PDF는 각100MiB/합계500MiB이며 코어 문서의 페이지·metadata 제한도 적용한다. PDF geometry의 실물 검증은 앱 PDFKit 경계에서 복원 전에 수행한다. bulk I/O는64KiB씩 진행하고 Task 취소를 확인한다. JSON은 상한 안에서 메모리 decode한다.

내보내기는 같은 부모의 새 UUID 임시 디렉터리 안에 완성 파일을 만들고 synchronize한 뒤 최종 경로를 교체한다. 실패·취소는 이전 목적 파일을 유지하고 자신의 임시 디렉터리만 제거한다. 검증은 stagingRoot의 새 UUID 자식에 추출하며 실패하면 그 자식만 제거한다. 검증된 staging은 사용 전에 CRC와 문서 값을 다시 확인하고 호출자가 수명 종료 시 정리한다. PDF 원본은 수정하지 않는다.

검증 근거: 실제 PencilKit v3 multi-source fixture/등록 PDF2개 roundtrip의 전체 문서 값 및 PDF bytes 비교, 독립 Python zipfile의 CRC/길이/stored 확인, unsafe ZIP matrix, manifest/future/CRC 오류, 취소/ENOSPC 이전 출력 보존 테스트. 실기기 성능 측정은 별도다.
