# Mulgil 아키텍처

Mulgil(물길)은 소스에서 Gold까지 데이터를 나르는 메달리온 레이크하우스 **패키지**다
(ADR 0004). 버전 고정 BOM, 세 배포 프로필, dbt 템플릿, 통합관리 콘솔로 구성되고,
끝에는 항상 [Sumun(수문)](https://github.com/lukesgood/sumun)이 선다. 고객은
레이크하우스를 먼저 짓지 않아도 된다 — 기존 소스를 Trino 카탈로그로 **연결**하면
Sumun 거버넌스가 등급 B로 즉시 적용되고, 필요한 테이블만 Iceberg Gold로
**적재**해 등급 A로 올린다 (ADR 0005). 이 문서는 "무엇이 어디에 있고, 왜 거기
있는가"를 설명한다. 설치 순서는 02–04, 모델링 규약은 05, 운영은 07에 있다.

## 1. 설계 원칙

1. **Gold만 바깥으로 나간다.** 에이전트와 BI는 Gold를 본다. Bronze·Silver는
   엔지니어가 같은 정책 아래 Trino/Athena로 직접 본다.
2. **포맷은 Iceberg, 카탈로그는 REST.** 엔진을 바꿔도 테이블은 그대로다.
   Trino·Athena·Spark·DuckDB·Snowflake 어느 쪽이든 같은 테이블을 읽는다.
3. **엔진은 하나.** Trino(또는 Athena)가 조회·변환·유지보수를 다 한다.
   Spark는 필요가 증명될 때만 (ADR 0003).
4. **거버넌스는 데이터 쪽에서 집행한다.** 정책의 원본은 Sumun에 있고,
   Mulgil은 그 정책이 엔진 레벨로 내려온 형태(Trino `rules.json`,
   Lake Formation 권한)를 적용한다. 마스킹은 저장 시점이 아니라 조회 시점에,
   호출자별로.
5. **고유 코드는 콘솔 하나, API 하나.** 콘솔(`console/`)과 `mulgil-ops`(`ops/`)는
   데이터 자산(테이블·파이프라인·비용·스토리지·알람)만 다룬다. 파드·로그·SQL
   편집·DAG 작성·사용자 관리는 만들지 않고 링크한다. 스케줄러는 없다 — 유지보수와
   dbt는 Airflow/Step Functions가 돌린다 (ADR 0004).
6. **연결 먼저, 적재는 점진.** 소스 카탈로그(등급 B)는 읽기 전용 발견 접근,
   Iceberg Gold(등급 A)는 운영 접근. 등급 B에서 등급 A로 가는 길은 Trino ELT
   `INSERT INTO iceberg… SELECT FROM 소스…` 한 문장이다 (ADR 0005).
7. **SeaweedFS 고유 기능은 선택.** filer 이벤트·mount·EC·remote.sync는 쓰면
   좋지만 없어도 동작한다. 제품은 어떤 S3 스토어에서도 돌아야 하고, 반기마다
   스토리지 이탈 테스트로 그것을 증명한다 (ADR 0005).

## 2. 논리 아키텍처

```
┌─ 소스 ───────────────────────────────────────────────────────────┐
│ RDBMS · SaaS API · 로그/이벤트 · 파일(S3/SFTP)                    │
└──────┬───────────────────────────────────────────────────────────┘
       │ 수집   RDB: Trino ELT(dbt) · NAS: weed mount · 문서: filer 이벤트 · SaaS: Airbyte · 스트림: Kafka Connect Iceberg Sink
       │        (등급 B) 소스 카탈로그는 적재 없이도 Trino 페더레이션으로 Sumun을 거쳐 질의 가능
       ▼
┌─ Bronze ─────────────────────────────────────────────────────────┐
│ 원본 그대로. append-only. 스키마 느슨. _ingested_at 스탬프.          │
│ 삭제 없음 — 재처리의 출발점.                                        │
└──────┬───────────────────────────────────────────────────────────┘
       │ 정제   dbt: 중복 제거 · 타입 강제 · 키 정합성 · null 정책
       ▼
┌─ Silver ─────────────────────────────────────────────────────────┐
│ 정합된 엔티티(customers, orders …). 1 엔티티 = 1 테이블.             │
│ PII 컬럼은 태깅만(meta.pii). 값은 원문 — 마스킹은 조회 시점에.        │
└──────┬───────────────────────────────────────────────────────────┘
       │ 가공   dbt: 조인 · 집계 · 지표 계산 · 데이터 계약 부착
       ▼
┌─ Gold ───────────────────────────────────────────────────────────┐
│ 지표 테이블. 오너·SLA·계약 버전이 schema.yml meta에.                 │
│ 지표 정의(dbt metrics)가 여기 붙는다 — BI와 에이전트가 같은 정의.     │
└──────┬───────────────────────────────────────────────────────────┘
       │ ← Mulgil의 끝, Sumun의 시작
       ▼
┌─ Sumun ──────────────────────────────────────────────────────────┐
│ RLS · 태그 기반 마스킹 · query_metric · 감사 · 예산               │
└──────┬───────────────────────────────────────────────────────────┘
       ▼
  에이전트 · BI(Superset) · 애플리케이션
```

계층별 허용 변환은 `05-modeling.md`가 정한다. 요지: Bronze는 손대지 않고,
Silver는 "무엇인가"를 정하고, Gold는 "얼마인가"를 정한다.

## 3. 구성요소와 책임

| 구성요소 | 책임 | 하지 않는 것 |
|---|---|---|
| **오브젝트 스토어** (SeaweedFS / S3) | Parquet 데이터 파일, Iceberg 메타데이터 파일 보관 | 권한 판단 (버킷 정책은 최후 방어선일 뿐) |
| **Iceberg 카탈로그** (Polaris 기본 / S3 Tables / SeaweedFS 내장 REST는 소규모) | 테이블 → 현재 메타데이터 포인터, 원자적 커밋, 네임스페이스, 권한·임시 자격증명 | 데이터 변환 |
| **쿼리 엔진** (Trino / Athena) | SQL 실행, dbt 변환 실행, Iceberg 유지보수(`optimize`, `expire_snapshots`), **소스 카탈로그 페더레이션(등급 B)** — `federated` 리소스 그룹으로 격리 | 스케줄링, 정책 원본 보관 |
| **소스 카탈로그** (PostgreSQL·MySQL·Oracle·SQL Server·Kafka·Elasticsearch·Hive 커넥터) | 기존 시스템을 적재 없이 질의 가능하게; dbt ELT의 소스 | 쓰기 (읽기 전용 계정·읽기 복제본 권장) |
| **dbt** | 모델·테스트·문서·지표 정의. 리니지의 원본 | 데이터 이동(수집) |
| **오케스트레이터** (Airflow / Step Functions) | dbt 실행 순서, 유지보수 주기, 실패 알림 | 변환 로직 |
| **수집 경로** (Trino ELT / weed mount / filer 이벤트 / Airbyte / Kafka Connect) | 소스 → Bronze 적재. RDB 기본은 Trino ELT, SaaS만 Airbyte | 정제 (Bronze는 원본) |
| **관측 엔진** (Prometheus·Alertmanager / CloudWatch) | 시계열·알람 평가·라우팅 | 화면 (콘솔이 그림) |
| **콘솔 + mulgil-ops** | 테이블 건강·유지보수, 파이프라인, 비용(치수), 스토리지, 알람 규칙, Sumun 사용량 뷰 | 파드·로그·SQL 편집·DAG 작성·사용자 관리 |
| **Sumun** | 정책 원본, 조회 시점 집행, 감사 | 데이터 변환·적재 |

## 4. 물리 아키텍처 — 세 프로필

### 4.1 `sovereign` — 온프렘 / 폐쇄망 (Kubernetes)

```
┌─ 컨트롤 노드 ×3 ─────────────────────────────────────────────┐
│ SeaweedFS master (Raft)  ·  K8s control plane (별도여도 됨)    │
└──────────────────────────────────────────────────────────────┘
┌─ 메타 노드 ×2 ───────────────────────────────────────────────┐
│ SeaweedFS filer (S3 gateway + Iceberg REST 내장)              │
│ PostgreSQL (filer 메타데이터 스토어)  ← 백업 1순위              │
└──────────────────────────────────────────────────────────────┘
┌─ 데이터 노드 ×N ─────────────────────────────────────────────┐
│ SeaweedFS volume — 로컬 NVMe/SSD, hostPath/local PV           │
│ 복제 010 (랙 간 1복제)                                         │
└──────────────────────────────────────────────────────────────┘
┌─ 컴퓨트 노드 ×M ─────────────────────────────────────────────┐
│ Trino coordinator ×1 · worker ×(M-1)                           │
│ Airflow · dbt runner · Prometheus/Grafana/Loki                 │
└──────────────────────────────────────────────────────────────┘
```

- 데이터 노드와 컴퓨트 노드를 **섞지 않는다.** 컴팩션 I/O와 쿼리 메모리가
  충돌한다.
- 볼륨 스토리지는 로컬 디스크. 네트워크 스토리지(Ceph·NFS) 위에 올리면
  SeaweedFS 복제와 이중이 되어 성능·비용 모두 손해.
- Polaris가 기본 카탈로그다 (ADR 0005). 카탈로그가 스토리지 벤더에 묶이지
  않게 하기 위함. SeaweedFS 내장 REST는 compose 픽스처와 소규모 설치용.
- 선택: `cold_tier: s3` — 콜드 레이어를 `filer.remote.sync`로 S3/Glacier에
  티어링하는 하이브리드 구성. 국내 규제 고객의 현실적 AWS 활용 경로.
- 외부 통신 없음. 이미지는 사설 레지스트리, dbt 패키지는 벤더링.

### 4.2 `aws-serverless` — AWS 전용 경량 프로필

```
S3 Tables (버킷당 Iceberg REST 카탈로그, 자동 컴팩션·스냅샷 만료)
   │
Athena 워크그룹 `mulgil` (엔진 v3 = Trino 기반)
   │        ↑ Lake Formation: 행 필터·컬럼 마스킹 (Sumun이 생성)
dbt-athena ← Step Functions 스케줄 (또는 MWAA, 또는 CI 스케줄)
   │
CloudWatch 메트릭·로그 · Cost Explorer 태그(워크그룹별)
```

- 고정비 ≈ 0. 비용 = 스캔 바이트. 사이징 대신 **파티션 설계**와 워크그룹의
  스캔 상한이 통제 수단이다.
- Athena 동시성 상한(계정·리전별 큐)이 있으므로 에이전트 팜이 커지면
  `aws-trino`로. 승격은 dbt 프로필 변경만이며 데이터는 움직이지 않는다.
- 페더레이션은 Athena Federated Query(Lambda 커넥터)로 **Bronze 적재까지만**.
  등급 B 에이전트 접근은 이 프로필에서 지원하지 않는다 (`federation.agent_access`
  강제 false). 대상: AWS 전용, ~100TB 미만, 낮은 동시성 (ADR 0005).

### 4.3 `aws-trino` — 대규모 / 저지연

```
S3 (범용 버킷)
   │
Polaris on EKS (Iceberg REST, credential vending)
   │
Trino on EKS — coordinator ×1, worker 오토스케일(min/max), Spot 허용
   │   fault-tolerant execution → S3 exchange 버킷
Airflow on EKS · Prometheus/Grafana
```

- 워커 사이징 논리는 `sovereign`과 같다 (`01-sizing.md`).
- FTE를 켜면 Spot 워커가 안전해지지만 대화형 지연이 늘어난다. 배치 전용
  워커 풀과 대화형 풀을 나누는 것이 현실적.

### 4.4 `byop` — 고객 플랫폼 위에서 (Snowflake · Databricks · BigQuery)

물길은 두 층이다. **규약 + dbt 프로젝트**는 플랫폼 중립이고, **배포 프로필**은
교체 가능하다. 고객이 이미 Snowflake·Databricks·BigQuery를 쓰면 프로필을 버리고
dbt 프로젝트와 규약만 가져간다 — `profiles.yml`의 타깃이 바뀔 뿐이다.

| 항목 | Iceberg/Trino 프로필 | Snowflake | Databricks | BigQuery |
|---|---|---|---|---|
| PII 태그 전달 | Iceberg 컬럼 속성 | 객체 태그 (dbt post-hook) | Unity Catalog 태그 | 정책 태그 |
| 신선도 신호 | Iceberg 스냅샷 시각 | `LAST_ALTERED` · 타임트래블 | Delta 버전 | 파티션 갱신 시각 |
| 삭제 절차 | row delete + 스냅샷 만료 | `DELETE` + 타임트래블 보존 단축 | `DELETE` + `VACUUM` | `DELETE` |
| 2계층 정책 | `rules.json` / Lake Formation | 행 접근·마스킹 정책 | Unity 행 필터·컬럼 마스크 | 행 수준 보안 |

마지막 두 줄은 수문의 어댑터 몫이다. 물길의 이식성이 곧 수문의 시장 크기이므로,
규약 문서는 "Iceberg 스냅샷" 대신 "테이블 버전 식별자"처럼 **플랫폼 중립 용어**로
쓴다. byop 프로필은 그 고객이 생길 때 만든다.

### 4.5 프로필 선택 결정 트리

```
고객이 이미 Snowflake·Databricks·BigQuery를 쓴다? ── 예 ──▶ byop (규약 + dbt만)
   │ 아니오
데이터가 폐쇄망·국내 보관 의무? ── 예 ──▶ sovereign
   │ 아니오
월 스캔량 > ~130TB 또는 동시 쿼리 > ~30 또는 p95 < 1초 필요
   또는 기존 RDB·DW를 에이전트가 직접(등급 B) 질의해야 함? ── 예 ──▶ aws-trino
   │ 아니오
                                                                  ▶ aws-serverless (경량)
```

손익분기 근거는 ADR 0002.

### 4.6 수문과의 선후 — Phase 1은 물길이 거의 필요 없다

수문 Phase 1(문서 거버넌스)은 Iceberg를 쓰지 않는다. 등급 B 카탈로그 1개
(PostgreSQL, 읽기 전용)만 Trino `rules.json`으로 얇게 붙여 "연결 먼저" 데모를
보인다. 물길의 Iceberg 테이블·콘솔은 Phase 2a부터, 소스 카탈로그 템플릿·등급 B
정책은 Phase 2b부터다. compose가 두 저장소 공통의 테스트 환경이다.

## 5. 데이터 흐름 — 한 레코드의 여정

주문 한 건이 소스에서 에이전트 답변까지:

1. **수집** — Debezium이 `orders` 테이블 변경을 Kafka로, Iceberg Sink가
   `bronze.orders`에 append. 또는 야간 Airbyte 배치.
2. **Bronze** — 원본 컬럼 그대로 + `_ingested_at`. 같은 주문이 두 번 와도
   둘 다 남는다.
3. **Silver** — dbt가 `order_id` 기준 최신 1건만, 타입 강제, `customer_id`가
   `silver_customers`에 있는지 검사(실패 시 dbt test가 파이프라인을 멈춘다).
   `silver_customers.rrn`은 `meta.pii: rrn` 태그만 달리고 값은 원문.
4. **Gold** — `gold_revenue_daily`에 완료 주문만 일·지역·카테고리로 집계.
   `revenue` 지표 정의가 이 테이블을 가리킨다.
5. **경계** — dbt manifest에서 PII 태그·계약·리니지가, Iceberg 스냅샷에서
   신선도가 Sumun으로 넘어간다.
6. **Sumun** — 에이전트가 `query_metric("revenue", 차원=지역)`을 호출. 호출자
   권한으로 RLS 적용, `as_of`에 스냅샷 시각, 감사 로그에 스냅샷 ID.
7. **답변** — "11월 서울 매출 ₩X (2026-11-08 04:00 기준)". 근거 테이블과
   스냅샷이 감사 로그에서 역추적된다.

## 6. Sumun과의 경계

Mulgil이 만들고 Sumun이 읽는 것. 방향은 한쪽뿐이다 — Sumun은 Mulgil에
쓰지 않는다.

| Mulgil 산출물 | 형식 | Sumun의 용도 |
|---|---|---|
| PII 컬럼 태그 | dbt `meta.pii: <type>` → Iceberg 컬럼 속성 | 태그 → 마스킹 정책 자동 매핑 |
| 데이터 계약 | dbt `meta.owner / sla_hours / contract` | 테이블 신뢰 등급, SLA 위반 라벨 |
| 지표 정의 | dbt `metrics:` | `query_metric` — BI와 같은 정의 |
| 리니지 | dbt `manifest.json` (선택: OpenMetadata) | 감사 로그의 출처 추적 |
| 신선도 | Iceberg 스냅샷 타임스탬프, dbt 실행 상태 | 응답의 `as_of`, stale 라벨/거부 |

반대 방향으로 Sumun이 **생성하고 Mulgil이 적용**하는 것 하나: 엔진 레벨
접근 정책 (`rules.json` 또는 Lake Formation 권한). 원본은 Sumun의 정책
테이블이고, Mulgil은 그 결과물을 엔진에 꽂는다. 정확한 포맷은
`08-sumun-boundary.md`.

## 6.1 문서 랜딩 규약 — 수문이 읽는 버킷

문서 수집 **코드**(스캐너·청킹·임베딩·커넥터 SDK)는 수문에 있다. 물길은 문서가
놓이는 자리와 형식만 정한다. 어떤 커넥터든 — Airbyte, rclone, 고객의 스크립트,
수문 커넥터 SDK 플러그인 — 이 규약을 지키면 수문이 읽는다.

```
s3://<landing-bucket>/docs/<collection>/<source>/<yyyy>/<mm>/<file>
s3://<landing-bucket>/docs/<collection>/<source>/<yyyy>/<mm>/<file>.manifest.json
```

매니페스트 필수 필드:

| 필드 | 뜻 | 수문이 쓰는 곳 |
|---|---|---|
| `source` · `source_key` | 원 시스템과 그 안의 레코드 키 | 테이블 행과 문서 연결, 리니지 |
| `collection` | 수문 컬렉션 (ACL 단위) | 접근 통제 |
| `owner` | 오너 (IdP ID) | 계약·알림 |
| `content_hash` | 본문 해시 | 멱등 수집, 변경 감지 |
| `retention_days` | 보존 기간 | 만료 삭제 |
| `deleted` · `deleted_at` | 삭제 플래그 | 청크·임베딩 삭제 전파 |
| `subject_keys[]` | 포함된 정보주체 식별자(가명) | 삭제 요청 조율 |

테이블 수집과 문서 수집이 같은 소스에서 나오면 `source`·`source_key`가 둘을 잇는다.
상세는 `06-ingestion.md`.

## 6.2 관측 산출물 — 콘솔과 mulgil-ops가 읽는 신호

화면은 물길 콘솔이다 (ADR 0004). 아래 신호를 `mulgil-ops`가 모아 콘솔 7화면
(개요·테이블·파이프라인·비용(치수)·스토리지·알람·거버넌스)으로 그린다. Grafana는
운영자용 선택 설치. Sumun 쪽 사용량은 `GET /usage/export`로만 받는다 — Sumun DB에
붙지 않는다.

| 신호 | 출처 | 형식 |
|---|---|---|
| 자원 상태 — 볼륨 사용률, filer DB, Trino 워커 메모리·큐, 소형 파일 수 | SeaweedFS·Trino 내장 exporter, Iceberg 메타데이터 | Prometheus |
| 파이프라인 이벤트 — dbt 실패, 테스트 실패, SLA 위반 | Airflow 콜백 / Step Functions | webhook (JSON 스펙은 `observability/events/`) |
| 저장 비용 — 테이블별 용량·증가율·스냅샷 묶인 용량 | Iceberg `files`·`snapshots` 메타데이터, S3 Storage Lens | 일 1회 CSV/JSON |
| 컴퓨트 비용 — 쿼리별 스캔 바이트·CPU 시간 | Trino event listener / Athena 쿼리 히스토리 | 쿼리 로그 테이블 |

`observability/`에 exporter 설정, 알람 규칙 번들, 이벤트 페이로드 스펙, 선택용
Grafana 대시보드 JSON을 둔다. 콘솔 명세는 `console/screens/`, API는 `ops/API.md`.

## 7. 보안 모델 — 두 계층

```
경로 A (에이전트·앱)   Sumun ──RLS·마스킹·예산──▶ Trino/Athena ──▶ Gold (등급 A)
                      Sumun ──플러그인(T8)·PII 컬럼 차단·행 한도──▶ Trino ──▶ 소스 카탈로그 (등급 B)
경로 B (엔지니어·BI)   Trino/Athena 직결 ──rules.json / Lake Formation──▶ Bronze·Silver·Gold
                                    ▲
                        같은 정책 테이블에서 생성

등급 B는 설계상 약하다(소스 DB에 RLS를 걸 수 없음) — 발견·탐색 접근이고, 운영
접근은 Gold 적재 후 등급 A에서만. 심의 문서는 이 말을 그대로 쓴다 (sumun ADR 0004).
```

- 두 경로가 **같은 정책 원본**을 쓴다. 정책을 한 번 바꾸면 양쪽에 반영.
- 에이전트는 S3 키·DB 자격증명을 갖지 않는다. 테이블 접근은
  엔진 → 카탈로그(권한·임시 자격증명) → 스토리지 순.
- 스토리지 버킷 정책은 "엔진 서비스 계정만"으로 최소화. 사람이 버킷을 직접
  읽는 경로는 없다.
- 감사: 엔진 쿼리 로그(Trino event listener / Athena 쿼리 히스토리)는
  Sumun 감사 로그와 별개로 보존 — 경로 B의 증적.

## 8. 운영 관심사 (요약, 상세는 07)

| 항목 | 주기 | 안 하면 |
|---|---|---|
| Iceberg `optimize` (컴팩션) | 일 1회 (스트리밍 테이블은 시간 단위) | 소형 파일 폭증 → 쿼리 지연 + filer DB 부하 |
| `expire_snapshots` | 주 1회, 보존 7일 | 스토리지 선형 증가 |
| `remove_orphan_files` | 월 1회 | 실패한 쓰기의 잔존 파일 누적 |
| filer PostgreSQL 백업 | 일 1회 + WAL | **전체 레이크 접근 불가** — 데이터는 있어도 경로를 모름 |
| dbt test | 매 실행 | 오염된 Silver가 Gold로 |
| 스냅샷 기준 신선도 알림 | SLA 기준 | 에이전트가 오래된 숫자를 오늘 것처럼 답함 |

`aws-serverless`에서는 첫 세 줄을 S3 Tables가 자동으로 한다.

## 9. 의도적으로 뺀 것

| 뺀 것 | 이유 | 대신 |
|---|---|---|
| Spark | 운영 부담 최대, Trino로 충분 | ADR 0003 |
| MinIO | AGPL | SeaweedFS (Apache-2.0) |
| Hive Metastore | REST 카탈로그가 표준 | SeaweedFS 내장 / S3 Tables / Polaris |
| 파드·로그 뷰어, SQL 에디터, DAG 편집기, 사용자 관리 UI | 콘솔 범위 밖 — 1.x의 2,300줄 k8s 뷰어 실패 반복 금지 | k9s/Lens · MCP 클라이언트·Trino UI · Airflow · IdP·Polaris (콘솔이 링크) |
| 자체 스케줄러 | Airflow/Step Functions로 충분 | ops 폴러는 수집만, 실행은 DAG 트리거 |
| 스트리밍 엔진(Flink·RisingWave) | 1차 시장 수요 낮음 | Kafka Connect Iceberg Sink로 적재만, 실시간 질의는 범위 밖 |
| 벡터 DB | Sumun(pgvector)의 몫 | — |

## 10. 관련 문서

- `01-sizing.md` — 티어별 노드·비용
- `02-sovereign.md` / `03-aws-serverless.md` / `04-aws-trino.md` — 설치
- `05-modeling.md` — 메달리온 규약, PII 태깅, 계약
- `08-sumun-boundary.md` — 경계 산출물 포맷
- `../license-review.md` — 오픈소스 라이선스 검토
- `console/screens/`, `ops/API.md` — 콘솔·ops 명세
- `docs/adr/` — 결정 기록 (0004 패키지·콘솔, 0005 연결 먼저·SeaweedFS 기능·헷지)
