# mulgil-ops API 명세 (v0)

콘솔이 호출하는 유일한 API입니다. 모든 응답은 JSON, 인증은 OIDC Bearer
토큰(Sumun과 동일 IdP), 역할은 `viewer`(읽기)와 `operator`(쓰기) 둘입니다.
쓰기는 모두 멱등하며 `ops_actions` 테이블에 기록됩니다.

## 범위 선언 (v0)

- **1 콘솔 = 1 프로파일.** 한 ops 인스턴스는 하나의 배포 프로파일만 본다.
  여러 환경을 쓰는 고객은 콘솔을 환경마다 둔다. 환경 선택기는 v0에 없다.
- **테이블 식별자**는 카탈로그 FQN `catalog.schema.table`. dbt manifest에
  있으면 소유자·PII·계약·리니지를 보강하고, 없으면(Airbyte 등이 만든 Bronze)
  카탈로그 정보만으로 표시한다.
- **수집과 스케줄의 구분.** 비즈니스 작업(compaction, dbt 실행)은 Airflow /
  Step Functions가 스케줄한다. 관측 **수집**(건강 점수, 비용 집계, 용량 추이)은
  ops 내부 폴러가 수행한다. 폴러는 외부 상태를 바꾸지 않는다.
- **ops 자체 저장소**: PostgreSQL 스키마 `mulgil_ops` — `ops_actions`(보존
  1년), `table_health_history`(13개월), `cost_daily`(13개월), `rate_card`,
  `collector_state`. 플랫폼 PostgreSQL을 공유하되 별도 role.

## 공통

- 시각은 UTC ISO-8601, 금액은 `{amount, currency}`, 용량은 바이트 정수.
- 페이지네이션: `?limit=&cursor=` → `{items, next_cursor}`.
- 오류: `{code, message, hint}`. `code`는 기계 판독용(`source_unavailable`,
  `not_operator`, `action_in_progress`, `profile_unsupported`).
- 데이터 소스 하나가 죽어도 응답은 반환합니다. 해당 필드는 `null`,
  `_degraded: ["prometheus"]` 배열에 소스명을 넣습니다. 콘솔은 이 배열로
  "일부 데이터 지연" 배너를 띄웁니다.

## 읽기

| 메서드 | 경로 | 용도 | 소스 |
|---|---|---|---|
| GET | `/overview` | 1 개요 화면 전체 | 아래 모두 |
| GET | `/tables` | 테이블 목록 (`?layer=&owner=&health=&q=`) | dbt manifest, Iceberg 메타 |
| GET | `/tables/{id}` | 상세: 스키마, PII 태그, 계약, 스냅샷, 파일 통계, 최근 유지보수 | Iceberg 메타, dbt |
| GET | `/tables/{id}/health` | 건강 점수와 산출 근거 | Iceberg 메타 |
| GET | `/pipelines/runs` | dbt/Airflow 실행 이력 (`?status=&since=`) | Airflow REST / Step Functions, run_results |
| GET | `/pipelines/runs/{run_id}` | 모델별 결과, 로그 링크 | 동일 |
| GET | `/contracts/violations` | SLA·스키마·소유자 위반 목록 | ops 계약 검사기 |
| GET | `/cost/summary` | 기간별 총비용, 프로파일 구성 (`?from=&to=`) | 비용 집계 |
| GET | `/cost/by-table` | 테이블별 저장·스캔 비용 | Iceberg 메타 × 단가, Athena 로그 |
| GET | `/cost/by-caller` | 호출자별 비용 | Sumun `GET /usage/export` |
| GET | `/storage/summary` | 버킷 용량, 노드·볼륨·복제 상태 | SeaweedFS master, S3 API, Prometheus |
| GET | `/storage/nodes` | 노드별 디스크, 볼륨 수, 상태 | 동일 |
| GET | `/metrics/query` | PromQL 프록시 (`?q=&from=&to=&step=`). 쿼리에 등장하는 메트릭명이 모두 `ops/config/metrics_allowlist.yaml`에 있어야 함; 아니면 `422 metric_not_allowed` | Prometheus |
| GET | `/alerts/rules` · `/alerts/history` | 규칙, 발생 이력 | 규칙 파일, Alertmanager API |
| GET | `/governance/callers` · `/governance/usage` | Sumun 호출자, 예산, 마스킹 적용 건수 | **Sumun 집계 API** `GET /usage/export` (sumun ADR 0003). Sumun DB에 직접 붙지 않음 |
| GET | `/actions` | 수행된 쓰기 작업 이력 | ops_actions |

## 쓰기 (operator)

| 메서드 | 경로 | 동작 | 실행 방식 |
|---|---|---|---|
| POST | `/tables/{id}/maintenance` | `{action: optimize\|expire_snapshots\|remove_orphan_files, params, dry_run}` | sovereign/aws-trino: Airflow DAG `mulgil_maintenance` 트리거. aws-serverless: Athena `OPTIMIZE`/`VACUUM` 문 실행. 동일 테이블·동일 action이 진행 중이면 `action_in_progress` |
| PUT | `/tables/{id}/maintenance/schedule` | `{optimize_cron, expire_older_than_days, retain_last}` | DAG 변수 갱신. 스케줄러는 Airflow |
| POST | `/pipelines/runs/{run_id}/rerun` | 실패 모델만 또는 전체 | Airflow DAG 재실행 / Step Functions 재시작 |
| PUT | `/alerts/rules/{name}` · DELETE | 임계값·심각도·채널 | rule 파일 렌더 → Prometheus reload, Alertmanager 라우트 갱신 |
| POST | `/alerts/{fingerprint}/silence` | 기간·사유 | Alertmanager silence |
| PUT | `/cost/rate-card` | `{currency, node_month: [{role, amount}], storage_tb_month, cpu_hour, updated_by}` — sovereign만; 저장 시 `cost_daily` 재계산 작업 생성 | mulgil_ops.rate_card |

쓰기 응답은 `{action_id, status: accepted, track: "/actions/{action_id}"}`.
`dry_run: true`는 영향 범위(대상 파일 수·바이트·스냅샷 수)만 반환합니다.

사용자 규칙(`PUT /alerts/rules/{name}`, 출처 `custom`)의 PromQL도 저장 전에
`metrics_allowlist.yaml`로 정적 검사합니다. 허용 목록은 Mulgil 컴포넌트의
exporter 메트릭만 담고, Sumun과 다른 네임스페이스의 메트릭은 포함하지 않습니다.

### `ops_actions` 레코드 (모든 쓰기)
| 필드 | 내용 |
|---|---|
| `action_id`, `kind` | UUID, `maintenance\|schedule\|rerun\|alert_rule\|silence\|rate_card` |
| `actor`, `actor_ip`, `user_agent` | OIDC `sub`와 표시명, 요청 IP |
| `target` | 테이블 FQN / run_id / 규칙명 |
| `params` | 요청 본문 전체 |
| `dry_run_result` | 실행 직전의 dry run 결과(파일 수·바이트·스냅샷 수). 없으면 실행 거부 |
| `executor_ref` | Airflow dag_run_id / Athena query id / Alertmanager silence id |
| `outcome` | `accepted\|running\|succeeded\|failed\|cancelled` + 오류 메시지 |
| `started_at`, `finished_at` | |

`ops_actions`는 append-only(UPDATE는 `outcome`·`finished_at`만, DELETE 없음).

## 금지

사용자 대신 SQL 실행, 파드·컨테이너 조작, 로그 스트리밍, 사용자·권한 변경,
Sumun 정책 변경. 해당 요청은 `403 out_of_scope`.

## 수집 주기와 비용 (폴러)

| 수집 | 주기 | 방법 |
|---|---|---|
| 테이블 건강 | **일 1회 + dbt 실행 완료 직후** | Iceberg `metadata.json`과 manifest 파일을 오브젝트 스토리지에서 **직접** 읽어 계산. 엔진(Trino/Athena)을 거치지 않으므로 Athena 스캔 비용 0. `$snapshots`/`$files` 쿼리는 상세 화면의 수동 새로고침에만 사용 |
| 비용 집계 | 일 1회 (CUR 도착 시각 이후) | Athena 쿼리 로그(`bytes_scanned`), CUR(v1: aws 프로파일), 단가표 |
| 용량·복제 | 5분 | SeaweedFS master API / S3 inventory, Prometheus |
| 파이프라인 | 이벤트 + 5분 폴링 | Airflow REST / Step Functions |
| Sumun 사용량 | 1시간 | `GET /usage/export?since=` |

Prometheus 보존은 **최소 90일**(BOM `prometheus.retention: 90d`). 90일 추이와
소진 예상일이 이 보존에 의존한다.

## 건강 점수 산식 (v0)

100점에서 감점. 소형 파일 비율(128MB 미만 파일 바이트 비율) 50% 초과 −30,
20% 초과 −15 · 스냅샷 100개 초과 −20, 30개 초과 −10 · 마지막 compaction
30일 초과 −10 · 신선도가 계약 SLA 초과 −30 · 파티션 최대/중위 크기 비 10배
초과 −10. 등급: 80 이상 `good`, 50 이상 `warn`, 미만 `bad`. 근거는
`/tables/{id}/health`에 항목별로 반환해 콘솔이 그대로 보여줍니다.

## 비용 산식 (v0)

- `aws-serverless`: Athena 스캔 바이트 × $5/TB + S3 Tables 저장·요청 요금
  (CUR) + 유지보수 compaction 요금.
- `aws-trino`: CUR의 EKS·EC2·S3 비용을 테이블 바이트 비율로 배분.
- `sovereign`: 온프렘 단가표(`ops/config/rate_card.yaml` — 노드 월 환산액,
  TB·월 저장 단가)를 테이블 바이트·쿼리 CPU 시간 비율로 배분. 단가표는 고객이
  입력하며 비어 있으면 금액 대신 자원량만 표시.
- 호출자 귀속: Sumun 감사 행의 `bytes_scanned`, `model_tokens`,
  `estimated_cost`를 합산. 플랫폼 고정비는 귀속하지 않고 "미귀속"으로 표시.
