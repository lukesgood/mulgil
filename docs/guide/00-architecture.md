# Mulgil 아키텍처

Mulgil(물길)은 소스에서 Gold까지 데이터를 나르는 레퍼런스 메달리온 레이크하우스다.
제품이 아니라 구성이며, 끝에는 항상 [Sumun(수문)](https://github.com/lukesgood/sumun)이
선다. 이 문서는 "무엇이 어디에 있고, 왜 거기 있는가"를 설명한다. 설치 순서는
02–04, 모델링 규약은 05, 운영은 07에 있다.

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
5. **Mulgil 고유 코드는 없다.** API·UI·스케줄러가 필요하면 상류 프로젝트나
   Sumun으로 (ADR 0001).

## 2. 논리 아키텍처

```
┌─ 소스 ───────────────────────────────────────────────────────────┐
│ RDBMS · SaaS API · 로그/이벤트 · 파일(S3/SFTP)                    │
└──────┬───────────────────────────────────────────────────────────┘
       │ 수집   배치: Airbyte / dbt seed · CDC: Debezium→Kafka→Iceberg Sink · 파일: 버킷 스캔
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
| **Iceberg 카탈로그** (SeaweedFS 내장 REST / S3 Tables / Polaris) | 테이블 → 현재 메타데이터 포인터, 원자적 커밋, 네임스페이스 | 데이터 변환 |
| **쿼리 엔진** (Trino / Athena) | SQL 실행, dbt 변환 실행, Iceberg 유지보수(`optimize`, `expire_snapshots`) | 스케줄링, 정책 원본 보관 |
| **dbt** | 모델·테스트·문서·지표 정의. 리니지의 원본 | 데이터 이동(수집) |
| **오케스트레이터** (Airflow / Step Functions) | dbt 실행 순서, 유지보수 주기, 실패 알림 | 변환 로직 |
| **수집기** (Airbyte / Kafka Connect / DMS) | 소스 → Bronze 적재 | 정제 (Bronze는 원본) |
| **관측** (Prometheus·Grafana·Loki / CloudWatch) | 메트릭·로그·알림 | — |
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
- Polaris는 기본 꺼짐. Sumun의 credential vending이 필요하거나 두 번째
  엔진이 카탈로그를 공유할 때 켠다. 그 전까지는 SeaweedFS 내장 REST 카탈로그.
- 외부 통신 없음. 이미지는 사설 레지스트리, dbt 패키지는 벤더링.

### 4.2 `aws-serverless` — AWS 기본

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
  `aws-trino`로.

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

### 4.4 프로필 선택 결정 트리

```
데이터가 폐쇄망·국내 보관 의무? ── 예 ──▶ sovereign
   │ 아니오
월 스캔량 > ~130TB 또는 동시 쿼리 > ~30 또는 p95 < 1초 필요? ── 예 ──▶ aws-trino
   │ 아니오
                                                                  ▶ aws-serverless
```

손익분기 근거는 ADR 0002.

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

## 7. 보안 모델 — 두 계층

```
경로 A (에이전트·앱)   Sumun ──RLS·마스킹·예산──▶ Trino/Athena ──▶ Gold
경로 B (엔지니어·BI)   Trino/Athena 직결 ──rules.json / Lake Formation──▶ Bronze·Silver·Gold
                                    ▲
                        같은 정책 테이블에서 생성
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
| 자체 UI | 제품이 아님 | dbt docs · Airflow · Grafana · (선택) OpenMetadata · Sumun 콘솔 |
| 스트리밍 엔진(Flink·RisingWave) | 1차 시장 수요 낮음 | Kafka Connect Iceberg Sink로 적재만, 실시간 질의는 범위 밖 |
| 벡터 DB | Sumun(pgvector)의 몫 | — |

## 10. 관련 문서

- `01-sizing.md` — 티어별 노드·비용
- `02-sovereign.md` / `03-aws-serverless.md` / `04-aws-trino.md` — 설치
- `05-modeling.md` — 메달리온 규약, PII 태깅, 계약
- `08-sumun-boundary.md` — 경계 산출물 포맷
- `docs/adr/` — 결정 기록
