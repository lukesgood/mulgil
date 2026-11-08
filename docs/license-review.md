# 오픈소스 구성요소와 라이선스 검토

작성일 2026-11-09 · 대상: Mulgil 패키지(BOM)와 Sumun이 함께 배포·의존하는
오픈소스 · 심의 문서 ⑪(sumun `docs/review-package/11-oss-licenses-and-support.md`)의
근거. 라이선스 분류는 *배포 방식*에 따라 의무가 달라지므로, 각 항목에 우리가
그 소프트웨어를 **어떻게 쓰는지**(번들 배포 / 선택 설치 / 고객 보유 / 라이브러리
링크)를 함께 적습니다. 법률 자문이 아니며, 최종 판단은 고객 법무와 솔트웨어
법무가 합니다.

## 요약

| 판정 | 뜻 | 해당 구성요소 |
|---|---|---|
| **그대로 사용** | 허용적 라이선스, 고지만 유지 | SeaweedFS, Trino, Polaris, Iceberg, dbt Core, Airflow, Prometheus, Alertmanager, PostgreSQL, pgvector, Valkey, Keycloak, Kafka, Kafka Connect Iceberg Sink, OpenTelemetry, FastAPI, Next.js, sqlglot, LiteLLM(OSS), Ollama, mssql-jdbc, PostgreSQL JDBC |
| **조건부 사용** | 쓰되 조건을 문서화·준수 | Grafana(AGPL, 무수정 선택 설치), Oracle JDBC(FUTC, 추가 요금 금지), MariaDB/MySQL JDBC(LGPL 또는 GPL+FOSS 예외 — 번들 드라이버 확인), Airbyte 플랫폼(ELv2, 선택 설치) |
| **제외** | 패키지에 넣지 않음 | MinIO(AGPL), Garage(AGPL, 대안 목록에만), dbt Fusion 바이너리(ELv2/상용), Elasticsearch 서버(고객 보유만), Starburst Enterprise(고객 보유만) |
| **AWS 관리형** | 라이선스 아닌 서비스 약관 | Athena, S3 Tables, Lake Formation, Step Functions, Bedrock, CUR |

**결론**: 패키지의 필수 경로(스토리지·카탈로그·엔진·변환·오케스트레이션·관측·DB·
인증)는 전부 Apache-2.0 / PostgreSQL / BSD / MIT 계열이라 **AGPL·SSPL·ELv2
구성요소 없이** 소버린 프로파일을 구성할 수 있습니다. 조건부 항목은 모두
*선택* 또는 *드라이버 수준*이며, 아래 조치로 닫힙니다.

## 구성요소별 검토

### 데이터 계층 (Mulgil)

| 구성요소 | 라이선스 | 우리 사용 방식 | 의무·주의 | 판정 |
|---|---|---|---|---|
| SeaweedFS | Apache-2.0 | 번들 배포, 무수정 | NOTICE 유지. 메인테이너 집중 리스크는 라이선스 아닌 지속성 문제(ADR 0005 이탈 테스트) | 사용 |
| Apache Iceberg (라이브러리·REST 스펙) | Apache-2.0 | Trino·Polaris·Sink 내부 | — | 사용 |
| Apache Polaris | Apache-2.0 | 번들 배포(기본 카탈로그) | 인큐베이팅 → 졸업 상태 확인 분기 1회 | 사용 |
| Trino | Apache-2.0 | 번들 배포 + 자체 플러그인(T8) 링크 | 플러그인은 SPI에 링크하는 별도 모듈 — Apache-2.0은 파생물 공개 의무 없음. 상표: "Trino"를 제품명에 쓰지 않음(ADR 0005) | 사용 |
| Trino JDBC 커넥터 번들 드라이버 | PostgreSQL JDBC: BSD-2 · mssql-jdbc: MIT · **Oracle ojdbc: Oracle FUTC** · **MySQL: Connector/J GPL-2.0 + Universal FOSS Exception 또는 MariaDB Connector/J LGPL-2.1 (Trino 버전별 번들 드라이버 확인 필요)** | Trino 이미지에 포함돼 재배포됨 | FUTC: 재배포 허용이나 **"프로그램 사용에 대해 최종 사용자에게 추가 요금을 부과하지 않을 것"** — Mulgil 패키지·구축 서비스 가격에 드라이버 항목이 없음을 명시. GPL+FOSS 예외/LGPL: Trino(Apache-2.0)가 예외 대상이며 우리는 수정하지 않음 | 조건부 |
| dbt Core (1.x, 2.0) | Apache-2.0 | 번들(dbt-runner 이미지) | dbt Labs–Fivetran 합병 후 Fusion 코드가 Core 2.0에 Apache-2.0으로 편입됨(2026-06). **Fusion 바이너리·dbt platform은 ELv2/상용 — 번들 금지.** `dbt-core` 패키지만 사용 | 사용 |
| dbt-trino, dbt-athena | Apache-2.0 | 번들 | — | 사용 |
| Apache Airflow | Apache-2.0 | 번들(sovereign·aws-trino) | 프로바이더 패키지도 Apache | 사용 |
| Kafka Connect Iceberg Sink | Apache-2.0 (Apache Iceberg 저장소로 이관) | 선택 | 구 Tabular 배포본 대신 Iceberg 공식 배포본 사용 | 사용 |
| Apache Kafka | Apache-2.0 | 고객 보유 또는 선택 | — | 사용 |
| Airbyte | 플랫폼 **ELv2**, 커넥터 MIT | **선택 설치, SaaS 소스만** | ELv2: 관리형 서비스로 제3자에 제공 금지. 고객 사내 설치는 허용. MSP 운영 대행이 "관리형 서비스 제공"으로 해석될 여지 → 운영 계약 시 법무 확인. 번들하지 않고 가이드 링크만 | 조건부 |
| Prometheus, Alertmanager | Apache-2.0 | 번들 | — | 사용 |
| Grafana | **AGPL-3.0** | **선택 설치, 무수정 공식 이미지**, 대시보드 JSON만 제공 | AGPL: 수정 후 네트워크 서비스 제공 시 소스 공개. 무수정 사용은 의무 없음. 대시보드 JSON은 우리 저작물(Apache-2.0). Grafana 임베드(iframe)로 콘솔에 넣지 않음 | 조건부 |
| PostgreSQL | PostgreSQL License | 번들 | — | 사용 |
| OpenTelemetry Collector | Apache-2.0 | 번들 | — | 사용 |
| node_exporter, postgres_exporter, JMX exporter | Apache-2.0 | 번들 | — | 사용 |
| Ceph RGW / Garage | LGPL-2.1·GPL / **AGPL-3.0** | 이탈 테스트 대상·대안 목록만 | 패키지에 포함하지 않음 | 제외(목록) |
| MinIO | **AGPL-3.0** | 포함 안 함(고객 보유 라이선스 시 bring-your-own) | 1.x에서 제외한 결정 유지 | 제외 |

### 거버넌스 계층 (Sumun)

| 구성요소 | 라이선스 | 사용 방식 | 의무·주의 | 판정 |
|---|---|---|---|---|
| PostgreSQL + pgvector | PostgreSQL License | 번들 | — | 사용 |
| Valkey | BSD-3-Clause | 번들 | Redis(RSALv2/SSPL)는 쓰지 않음 | 사용 |
| LiteLLM | MIT (OSS 부분) | 번들 | **enterprise/ 디렉터리는 상용 라이선스** — 이미지에서 enterprise 기능 미사용·미활성 확인. 의존성 많음 → SBOM 필수 | 사용(확인) |
| Keycloak | Apache-2.0 | 선택(고객 IdP 없을 때) | — | 사용 |
| Ollama | MIT | sovereign 선택 | 모델 가중치는 각 모델 라이선스(Llama 커뮤니티 라이선스, Qwen Apache-2.0, Gemma 약관 등) — **모델별 고지 별도** | 사용(모델 확인) |
| FastAPI, Pydantic, SQLAlchemy, sqlglot, httpx | MIT / BSD | 라이브러리 | — | 사용 |
| Next.js, React | MIT | 콘솔·운영자 UI | — | 사용 |
| MCP SDK | MIT | 라이브러리 | — | 사용 |
| Apache Polaris 클라이언트 | Apache-2.0 | 어댑터 | — | 사용 |
| Trino SPI (T8 플러그인) | Apache-2.0 | 컴파일 의존 | — | 사용 |

### 고객 보유 소스 (등급 B, 우리가 배포하지 않음)

Oracle DB, SQL Server, MySQL, Elasticsearch(AGPL/SSPL/ELv2 삼중), Snowflake,
Databricks, Starburst Enterprise — **고객의 라이선스**. 우리는 접속만 하며
접속 드라이버 의무만 위 표에 따릅니다. Elasticsearch는 서버가 아닌 Trino
커넥터(Apache)만 번들합니다.

### AWS 관리형 서비스
Athena, S3 Tables, Lake Formation, Step Functions, Bedrock, CUR — AWS 서비스
약관. 오픈소스 라이선스 범위 밖. Bedrock 모델은 각 모델 제공자 약관(Anthropic,
Amazon Nova 등)이 추가 적용.

## 우리가 내는 것의 라이선스

| 산출물 | 라이선스 | 비고 |
|---|---|---|
| Mulgil 전체(distro, dbt, ops, docs) | Apache-2.0 | ADR 0004 |
| Mulgil `console/` | Apache-2.0 **별도 LICENSE 파일** | 추후 BSL 등 소스 공개 라이선스 전환 가능성 보존(ADR 0005 헷지) |
| Sumun core | Apache-2.0 | |
| Sumun `ee/` | 상용 | token exchange, 다중 테넌트, 고급 감사 export |
| 심의 문서 패키지 | 상용(고객 계약 부속) | 공개 저장소에 템플릿 목차만 |
| Grafana 대시보드 JSON | Apache-2.0 | Grafana 자체는 AGPL이나 JSON은 독립 저작물 |

Apache-2.0 산출물에 GPL/AGPL 코드를 **링크·포함하지 않습니다.** Grafana·MinIO·
Garage는 프로세스 분리(네트워크 호출)만 허용.

## 조치 사항

1. `THIRD_PARTY_NOTICES.md`에 Oracle FUTC, MySQL/MariaDB 드라이버, Airbyte
   ELv2, LiteLLM enterprise 제외, Ollama 모델별 고지 항목 추가 — 이 문서와 함께 반영
2. CI `license-check`: 이미지·pip·npm SBOM(Syft) 생성 → **금지 목록**
   (AGPL-3.0, SSPL, ELv2, BSL, RSAL, 상용)이 번들 경로에 있으면 실패. Grafana는
   선택 설치이므로 번들 이미지 목록에 없음을 같은 검사로 확인
3. Trino 버전별 MySQL 번들 드라이버 확인 후 표의 "확인 필요" 제거(BOM 핀 시)
4. 운영 대행(MSP) 계약서에 Airbyte ELv2 "관리형 서비스 제공 금지" 조항 해석을
   법무 검토 항목으로 등재
5. 가격표·제안서 템플릿에 "제3자 드라이버·오픈소스에 대한 별도 요금 없음" 문구
   (Oracle FUTC 조건)
6. Ollama 사용 시 모델 라이선스 매트릭스(`docs/model-licenses.md`)를 설치 시
   선택 모델에 맞춰 생성
7. 분기 1회: Polaris 졸업 상태, SeaweedFS 릴리스 간격, dbt Core 2.0 GA 여부,
   Grafana·Airbyte 라이선스 변경 모니터링 — release 에이전트 체크리스트에

## 출처
- dbt 라이선스 FAQ 및 Core 2.0 발표 (dbt Labs, 2026-06): Core는 Apache-2.0, Fusion은 ELv2/상용
- Oracle Free Use Terms and Conditions (ojdbc Maven POM)
- MariaDB Connector/J 라이선스 안내 (LGPL-2.1)
- 각 프로젝트 저장소 LICENSE 파일 (BOM 핀 시 재확인)
