# 시스템 사양과 사이징

사이징은 데이터량보다 **쿼리 패턴**이 정한다. 같은 10TB도 야간 배치만 도는 곳과
에이전트 50개가 낮에 두드리는 곳은 노드 수가 두 배 다르다. 아래 숫자는 설계
기준치이고 첫 고객 실측 후 보정한다 (작성 조건: 첫 고객 제안 시점).

## 1. 입력 세 축

| 축 | 묻는 것 | 결정하는 것 |
|---|---|---|
| 저장 | Bronze 누적량(압축 후), 월 증가량, 보존 기간 | 볼륨 노드 수·디스크 |
| 변환 | dbt 일일 처리량, 가장 큰 조인의 중간 결과 크기 | Trino 워커 메모리 |
| 조회 | 동시 쿼리 수(에이전트+BI+사람), p95 목표 지연, 일 스캔량 | Trino 워커 수 / Athena 비용 |

Iceberg(Parquet 압축)는 원본 대비 **1/4–1/6**이다. 고객이 말하는 "10TB"가 원본이면
저장은 2TB 안팎이다. 문서(PDF·docx)는 압축이 거의 없다 — 원본 용량 그대로.

## 2. `sovereign` — 노드 역할

| 역할 | 구성 | 원칙 |
|---|---|---|
| 컨트롤 | SeaweedFS master ×3 (Raft) | 작음. K8s control plane과 같은 노드여도 됨 |
| 메타 | SeaweedFS filer ×2 + PostgreSQL | **파일 수**에 비례. PG 백업 1순위 |
| 데이터 | SeaweedFS volume ×N | 로컬 NVMe/SSD. 네트워크 스토리지 금지 (복제 이중) |
| 컴퓨트 | Trino coordinator ×1 + worker ×M, Airflow, dbt 러너 | 메모리가 전부 |
| 카탈로그·관측·콘솔 | Polaris · Prometheus(보존 90일) · Alertmanager · mulgil-ops + 콘솔 · (선택) Grafana·Loki | 컴퓨트와 분리. 콘솔·ops는 소형(2 vCPU·4GB) |

**데이터 노드와 컴퓨트 노드를 섞지 않는다.** 컴팩션 I/O와 쿼리 메모리가 충돌한다.

## 3. `sovereign` 티어

| | S — PoC·부서 | M — 중견 전사 | L — 대규모 |
|---|---|---|---|
| 저장 데이터 (압축 후) | ≤ 2TB | 2–20TB | 20–100TB |
| 동시 쿼리 | ≤ 5 | 5–30 | 30–100 |
| SeaweedFS master | 1 (또는 3 소형) | 3 × 2vCPU/4GB | 3 × 2vCPU/4GB |
| SeaweedFS filer + PG | 1 × 4vCPU/8GB | 2 × 4vCPU/16GB, PG 8GB 전용 | 3 × 8vCPU/32GB, PG 16GB 전용 |
| SeaweedFS volume | 1 × 8vCPU/16GB, 4TB SSD | 3 × 8vCPU/32GB, 각 8–16TB NVMe | 6–12 × 16vCPU/64GB, 각 16–32TB |
| Trino coordinator | 4vCPU/16GB | 8vCPU/32GB | 16vCPU/64GB |
| Trino worker | 1 × 8vCPU/32GB | 3 × 16vCPU/64GB | 8–16 × 32vCPU/128GB |
| Airflow + PG | 2vCPU/4GB | 4vCPU/8GB | 8vCPU/16GB, HA |
| 관측 | 2vCPU/4GB | 4vCPU/8GB | 8vCPU/16GB |
| **합계 (대략)** | **~26 vCPU / 80GB / 4TB** | **~90 vCPU / 350GB / 24–48TB** | **~400+ vCPU / 1.5TB+ / 200–400TB** |
| 복제 | 없음 | `010` (랙 간 1복제) → 실용량 ½ | `010` 또는 `001` + 백업 |
| 수문 (docs-only) | 같은 노드 | 2 × 4vCPU/16GB + pgvector PG 16GB | 3 × 8vCPU/32GB + PG 32GB |
| 수문 임베딩·LLM (sovereign) | GPU 1 (24GB) | GPU 2 (24–48GB) | GPU 4+ |

마지막 두 줄은 수문의 몫이지만 폐쇄망 견적에 빠지면 안 되므로 함께 둔다. GPU는
임베딩 모델과 로컬 LLM용이고, 수문 docs-only Phase 1에서도 필요하다.

### Trino 메모리 규칙
- 워커 힙 = 노드 메모리의 ~70%. `query.max-memory-per-node` ≈ 힙의 ~30%.
  64GB 노드 → 쿼리당 ~13GB.
- 가장 큰 dbt 조인의 중간 결과가 (워커 수 × 13GB)를 넘으면 스필 또는 워커 추가.
- Fault-tolerant execution을 켜면 S3 exchange를 쓰므로 메모리 압박은 줄고 지연은
  는다. **배치 전용 설정**이고 대화형 풀은 끈다. M 이상은 배치 풀과 대화형 풀을
  분리한다.

### Filer DB — 숨은 병목
SeaweedFS 메타데이터는 파일 수에 비례한다. Iceberg는 소형 파일을 양산하므로
(스트리밍 수집 시 하루 수만 개) 컴팩션 주기를 지키지 않으면 PG가 먼저 죽는다.
M 티어부터 PG 전용 노드, 매일 백업 + WAL.

### 디스크 산정
```
실디스크 = 압축후 데이터 × 복제계수 × (1 + 스냅샷 보존 비율 0.2) × 여유 1.3
예: M 티어 10TB × 2 × 1.2 × 1.3 ≈ 31TB

Erasure Coding 변형 (ADR 0005, 콜드 레이어 선택): 복제계수 2 → 1.4
예: Bronze·audit 6TB를 EC로 두면 6 × 1.4 × 1.2 × 1.3 ≈ 13TB (복제 시 19TB)

하이브리드 콜드 티어 (`cold_tier: s3`): 콜드 레이어는 온프렘 디스크 산정에서
제외하고 S3/Glacier 비용으로 계산. 핫 레이어만 위 식.
```

### 페더레이션(등급 B) 시 소스 부하 한도
Trino `federated` 리소스 그룹 기본값: 동시 4, CPU 30분/시간 상한. 소스 DB에는
읽기 전용 계정·읽기 복제본을 전제하고, 커넥터별 `max-splits`·
`query.max-execution-time`을 보수적으로 둔다. 소스 쿼리 시간·커넥션 수가 반복
알람이면 그 소스는 Bronze ELT로 전환한다 — 사이징이 아니라 설계로 푼다.

## 4. AWS 프로필

| | `aws-serverless` | `aws-trino` |
|---|---|---|
| 사이징 대상 | **없음** — 스캔량만 관리 | Trino 워커 수 = 3장 논리 그대로 |
| 통제 변수 | Athena 워크그룹 스캔 바이트 상한(쿼리당·일별), 파티션·정렬 | EKS 노드그룹 오토스케일(min/max), Spot 워커(FTE 켜면 안전) |
| 고정비 | ≈ $0 (Step Functions 스케줄 시) · MWAA 쓰면 ≈ $350/월 | ≈ $650–750/월 (m6i.xlarge ×3 + EKS + NAT) |
| 변동비 | $5/TB 스캔 + S3 Tables 저장·컴팩션 | 워커당 ≈ $170/월 추가 |
| 월 스캔 10TB | ≈ $50 | ≈ $700+ |
| 월 스캔 200TB | ≈ $1,000 | ≈ $1,200 (워커 5) |
| 손익분기 | — | 월 ≈ 130TB 스캔 |

aws-serverless에서 실질적 "사이징"은 **파티션 설계**다. Gold를 날짜·지역으로
파티션하고 `query_metric`이 항상 파티션 컬럼을 필터에 넣으면 스캔량이 1/100로
준다. 수문 요구사항 T2에 "지표 정의의 `time_column`은 파티션 컬럼이어야 하며
기간 필터 없는 호출에 기본 기간(최근 90일) 강제"가 들어가는 이유다.

## 5. 네트워크·보안 사양 (sovereign)

| 항목 | 사양 |
|---|---|
| 외부 통신 | 없음. 이미지는 사설 레지스트리, dbt 패키지 벤더링, 모델 가중치 오프라인 반입 |
| 노드 간 | 10GbE 이상 (볼륨 복제·Trino 교환). 25GbE는 L 티어 |
| 스토리지 암호화 | SeaweedFS 볼륨 암호화 + 디스크 암호화. 키는 고객 KMS/HSM |
| 전송 암호화 | S3 gateway·Trino·Iceberg REST 전부 TLS. 사설 CA |
| 인증 | 사람·서비스 모두 IdP(Keycloak/AD). S3 키는 서비스 계정에만, 사람에게는 없음 |
| 버킷 정책 | 엔진 서비스 계정만. 사람의 버킷 직접 접근 경로 없음 |
| 감사 | Trino event listener → 쿼리 로그 테이블(보존 1년+), S3 접근 로그 |

## 6. 가용성 목표

| 티어 | 목표 | 수단 |
|---|---|---|
| S | 업무시간 복구 (RTO 4h) | 단일 노드, 일 백업 |
| M | RTO 1h, RPO 1h | master 3 Raft, filer 2, volume `010`, PG WAL 아카이브 |
| L | RTO 15m, RPO 5m | + Trino coordinator 대기, PG 스트리밍 복제, 크로스 DC filer 동기화 |

Iceberg 테이블은 메타데이터+데이터 전부 오브젝트라 **버킷 복제로 DR이 끝난다.**
다만 filer DB가 없으면 경로를 모르므로 filer DB 백업이 DR의 전부다.

## 7. 산정 절차 (제안서용)

1. 세 축 입력을 고객에게 받는다 (1장). 없으면 "소스 DB 총 용량, 일 쿼리 수, 사람
   사용자 수" 세 숫자로 추정.
2. 압축 후 용량 = 원본 / 5. 문서는 그대로.
3. 티어 결정 (3장). 경계면 한 단계 위.
4. 디스크 산정 공식 (3장).
5. 프로필 결정 트리 (`00-architecture` 4.5).
6. 수문·GPU 행을 더한다 — 폐쇄망이면 빠뜨리지 않는다.
7. 월 비용: sovereign은 하드웨어 감가 3년 + 운영 인력, AWS는 4장 표.

계산기(xlsx)는 첫 제안 때 만들고 여기 링크한다.
