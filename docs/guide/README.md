# Mulgil 구축 가이드

가이드는 한국어로 쓴다 — 1차 독자가 국내 고객과 솔트웨어 엔지니어다.
README·ADR·코드 주석은 영어.

실제로 해본 것만 쓴다. 아직 못 쓴 문서는 "작성 조건"만 적어둔다.

| 문서 | 독자 | 상태 | 작성 조건 |
|---|---|---|---|
| [00-architecture](00-architecture.md) | 의사결정자 + 엔지니어 | 초안 | — |
| [01-sizing](01-sizing.md) | 의사결정자 | 초안 (기준치) | 첫 고객 실측 후 보정 |
| 02-engine (`trino-k8s`) | 엔지니어 | 미작성 — 엔진 배포·리소스 그룹·OPA·이벤트 리스너 | Phase 2a 첫 설치 후 |
| [../../storage/seaweedfs/GUIDE](../../storage/seaweedfs/GUIDE.md) | 인프라 엔지니어 | 초안 — **저장소 선택지 A** SeaweedFS 클러스터 (`[검증 필요]` 표시 포함) | 저장소 없는 고객 첫 구축 후 |
| 03-athena | 엔지니어 | 미작성 | 첫 AWS 엔게이지먼트 |
| 04-landing-zone | 엔지니어 | 미작성 — 선택 모듈 설치, BYO 저장소 연결 | Phase 2b |
| 05-modeling | 엔지니어·분석가 | 미작성 | dbt 프로젝트가 compose에서 한 번 돈 뒤 |
| 06-ingestion | 엔지니어 | 미작성 | Trino ELT·filer 이벤트·weed mount 경로를 각 한 번 붙인 뒤 |
| 07-operations | 운영자 | 미작성 (콘솔 명세는 `console/screens/`) | 운영 1개월 후 |
| 08-sumun-boundary | Sumun·Mulgil 양쪽 엔지니어 | 미작성 | Sumun T2·T3 구현과 함께 |
| 09-migration | 엔지니어 | 미작성 | athena↔trino-k8s 이동 테스트(Sumun O4)·스토리지 이탈 테스트(M3) 통과 후 |
| 10-federation | 엔지니어 | 미작성 — **2a 핵심 문서**: 소스 카탈로그 연결, 등급 B 운영 수칙, 소스 부하 한도 | 고객 RDB 1종 연결 후 |
| [../license-review](../license-review.md) | 의사결정자·법무 | 작성 (2026-11-09) | BOM 핀마다 갱신 |
| runbooks/ | 운영자 | 미작성 | 장애를 한 번 겪은 뒤, 겪은 것만 |
