# Mulgil 구축 가이드

가이드는 한국어로 쓴다 — 1차 독자가 국내 고객과 솔트웨어 엔지니어다.
README·ADR·코드 주석은 영어.

실제로 해본 것만 쓴다. 아직 못 쓴 문서는 "작성 조건"만 적어둔다.

| 문서 | 독자 | 상태 | 작성 조건 |
|---|---|---|---|
| [00-architecture](00-architecture.md) | 의사결정자 + 엔지니어 | 초안 | — |
| [01-sizing](01-sizing.md) | 의사결정자 | 초안 (기준치) | 첫 고객 실측 후 보정 |
| [02-sovereign](02-sovereign.md) | 엔지니어 | 초안 — SeaweedFS 클러스터 상세 (`[검증 필요]` 표시 포함) | K8s 첫 설치 후 걸린 지점 반영 |
| 03-aws-serverless | 엔지니어 | 미작성 | 첫 AWS 엔게이지먼트 |
| 04-aws-trino | 엔지니어 | 미작성 | aws-trino 첫 구축 |
| 05-modeling | 엔지니어·분석가 | 미작성 | dbt 프로젝트가 compose에서 한 번 돈 뒤 |
| 06-ingestion | 엔지니어 | 미작성 | CDC 경로를 한 번 붙인 뒤 |
| 07-operations | 운영자 | 미작성 | 운영 1개월 후 |
| 08-sumun-boundary | Sumun·Mulgil 양쪽 엔지니어 | 미작성 | Sumun T2·T3 구현과 함께 |
| 09-migration | 엔지니어 | 미작성 | sovereign↔aws 이동 테스트(Sumun O4) 통과 후 |
| runbooks/ | 운영자 | 미작성 | 장애를 한 번 겪은 뒤, 겪은 것만 |
