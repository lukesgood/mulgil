# SeaweedFS 클러스터 상세 아키텍처와 구성 가이드 (`sovereign`)

물길 `sovereign` 프로필의 스토리지 계층이다. SeaweedFS 한 시스템이 오브젝트
스토어(S3 API)와 Iceberg REST 카탈로그를 같이 제공하므로, 이 클러스터가 서면
Trino·dbt·수문이 붙을 자리가 생긴다.

> 상태: 설계 기준 문서. 첫 K8s 설치 후 "걸린 지점"을 이 문서에 그대로 반영한다.
> `[검증 필요]` 표시는 플래그·명령을 실제 버전에서 확인해야 하는 항목이다.
> 기준 버전: SeaweedFS 3.9x 계열 (2026), 공식 Helm 차트 `seaweedfs/seaweedfs`.

## 1. 구성요소와 역할

| 프로세스 | 역할 | 상태 | 수량 |
|---|---|---|---|
| **master** | 볼륨 배치·ID 발급·토폴로지(DC/랙) 관리, Raft 합의 | 작은 메타(볼륨 맵) | 3 (홀수, Raft) |
| **volume** | 실제 데이터. 디스크당 N개의 볼륨 파일(기본 30GB) | 데이터 | 디스크 수 × 서버 수 |
| **filer** | 디렉터리·파일 메타데이터 → 외부 스토어(PostgreSQL). S3 gateway 내장 가능 | PostgreSQL에 위임 | 2+ (무상태, 스토어 공유) |
| **S3 gateway** | S3 API(8333), IAM, 버킷 정책. filer 내장 또는 별도 `weed s3` | 무상태 | filer와 같이 또는 별도 2+ |
| **Iceberg REST catalog** | 테이블 버킷의 Iceberg 메타데이터를 REST(8181)로 | 테이블 버킷 안의 메타데이터 파일 | S3 gateway와 함께 `[검증 필요: 별도 플래그 여부]` |
| **PostgreSQL** | filer 메타데이터 스토어 | **클러스터의 단일 진실** | 1 primary + 1 standby (M 이상) |

핵심 사실 하나: **volume 서버가 전부 살아 있어도 filer DB가 없으면 경로를 모른다.**
백업 순위는 filer DB > 볼륨이다.

## 2. 물리 토폴로지

### 2.1 M 티어 기준 배치 (2–20TB, 동시 쿼리 5–30)

```
                  ┌──────────────── 랙 A ────────────────┐   ┌──────────────── 랙 B ────────────────┐
컨트롤/메타        │ node-c1: master · filer · PG primary  │   │ node-c2: master · filer · PG standby  │   node-c3: master (랙 C 또는 A)
데이터             │ node-d1: volume ×(디스크 수)           │   │ node-d3: volume ×(디스크 수)           │
                  │ node-d2: volume ×(디스크 수)           │   │ node-d4: volume ×(디스크 수)           │   (선택) node-d5…
컴퓨트             │ node-k1: Trino coordinator · Airflow   │   │ node-k2: Trino worker                  │   node-k3: Trino worker
                  └───────────────────────────────────────┘   └───────────────────────────────────────┘
```

- 복제 `010` = **랙 간 1복제**. 랙 A 디스크가 통째로 죽어도 랙 B에 사본.
- master 3개는 서로 다른 장애 도메인(최소 2랙)에.
- PG primary/standby는 다른 랙. filer는 둘 다 primary를 보고, 장애 시 standby 승격.

### 2.2 S 티어 (PoC) — 1노드

`weed mini` 또는 `weed server -s3 -filer -master -volume` 한 프로세스. 복제 없음.
compose 픽스처가 이 구성이다. 운영 금지.

### 2.3 L 티어 — DC 2개

랙 라벨 위에 `-dataCenter` 라벨. 복제 `110` (DC 간 1 + 랙 간 1) 또는 `100` + 비동기
filer 복제. 비용이 두 배이므로 DR 요구가 명시된 경우에만.

### 2.4 노드 사양 (M 티어)

| 노드 | CPU/메모리 | 디스크 | 비고 |
|---|---|---|---|
| node-c1/c2 | 4vCPU/16GB | OS SSD + PG용 NVMe 500GB | PG는 전용 디스크 |
| node-c3 | 2vCPU/4GB | OS SSD | master만 |
| node-d1–d4 | 8vCPU/32GB | **데이터 디스크 4–8개 × 2–4TB NVMe, JBOD** | RAID 없음 — 복제가 RAID 역할. 디스크당 volume 디렉터리 1개 |
| node-k1–k3 | `01-sizing` Trino 행 | OS SSD + 스필용 NVMe 1TB | |

네트워크: 노드 간 10GbE. 데이터 노드는 25GbE 권장(복제·컴팩션 트래픽).

## 3. 포트와 통신 경로

| 프로세스 | HTTP | gRPC | 메트릭 | 누가 접근 |
|---|---|---|---|---|
| master | 9333 | 19333 | `-metricsPort` | volume, filer (내부만) |
| volume | 8080 | 18080 | `-metricsPort` | filer, S3 gateway, **클라이언트 직접 읽기** |
| filer | 8888 | 18888 | `-metricsPort` | S3 gateway, 관리자 (내부만) |
| S3 gateway | 8333 | — | — | Trino, dbt, 수문, 수집기 — **유일한 외부 진입점** |
| Iceberg REST | 8181 | — | — | Trino, dbt, 수문 |
| PostgreSQL | 5432 | — | — | filer만 |

방화벽 원칙: 외부(컴퓨트 노드 포함)에서 열리는 건 **8333과 8181뿐**. master·filer·PG는
스토리지 네트워크 세그먼트 안에서만. volume 8080은 S3 gateway가 리다이렉트할 수
있으므로 컴퓨트 노드에서 접근 가능해야 한다 `[검증 필요: S3 경로에서 volume 직접
리다이렉트 여부 — 아니면 닫는다]`.

## 4. master 구성

```
weed master \
  -ip=node-c1 -port=9333 \
  -mdir=/var/lib/seaweedfs/master \
  -peers=node-c1:9333,node-c2:9333,node-c3:9333 \
  -defaultReplication=010 \
  -volumeSizeLimitMB=30000 \
  -volumePreallocate \
  -metricsPort=9327
```

| 플래그 | 값 | 이유 |
|---|---|---|
| `-defaultReplication` | `010` | 랙 간 1복제. 버킷별로 덮어쓸 수 있음 |
| `-volumeSizeLimitMB` | 30000 | 기본. Parquet 파일(수십 MB~1GB)에 적합. 소형 파일이 많으면 그대로, 대형 파일이면 올림 |
| `-volumePreallocate` | 켬 | 단편화 방지, 쓰기 지연 안정 |
| `-garbageThreshold` | 0.3 (기본) | 삭제된 공간 30% 넘으면 vacuum. Iceberg 스냅샷 만료 후 공간 회수에 영향 |

세 master의 `-peers`는 동일하게. 하나씩 올리면 Raft 리더 선출 후 정상.

## 5. volume 구성

디스크당 하나의 `-dir`, 서버당 하나의 프로세스:

```
weed volume \
  -ip=node-d1 -port=8080 \
  -mserver=node-c1:9333,node-c2:9333,node-c3:9333 \
  -dir=/data/disk1,/data/disk2,/data/disk3,/data/disk4 \
  -max=0,0,0,0 \
  -dataCenter=dc1 -rack=rackA \
  -index=leveldb \
  -metricsPort=9327
```

| 플래그 | 값 | 이유 |
|---|---|---|
| `-dir` | 디스크별 마운트 | JBOD. 디스크 하나 죽으면 그 볼륨만 복제에서 복구 |
| `-max` | `0` | 디스크 용량에 맞춰 자동. 명시하려면 (디스크 GB / 30) − 여유 |
| `-dataCenter`, `-rack` | 물리 위치 | **복제가 이 라벨로 사본 위치를 정한다.** 틀리면 같은 랙에 두 사본 |
| `-index` | `leveldb` | 메모리 인덱스 대신. 재시작이 빠르고 메모리 절약. 소형 파일 많을 때 필수 |
| `-compactionMBps` | 50–100 | vacuum이 쿼리 I/O를 먹지 않게 상한 |

파일시스템: XFS, `noatime`. 디스크 사용률 85% 알람, 90%에서 쓰기 거부 전 노드 추가.

## 6. filer 구성 — PostgreSQL 스토어

`/etc/seaweedfs/filer.toml`:

```toml
[postgres2]
enabled = true
createTable = """
  CREATE TABLE IF NOT EXISTS "%s" (
    dirhash   BIGINT,
    name      VARCHAR(65535),
    directory VARCHAR(65535),
    meta      bytea,
    PRIMARY KEY (dirhash, name)
  );
"""
hostname = "pg-primary.storage.svc"
port = 5432
username = "seaweedfs"
password = ""            # 환경변수 WEED_POSTGRES2_PASSWORD 로 주입
database = "seaweedfs"
schema = ""
sslmode = "require"
connection_max_idle = 100
connection_max_open  = 100
connection_max_lifetime_seconds = 0
enableUpsert = true
upsertQuery = """INSERT INTO "%[1]s" (dirhash,name,directory,meta) VALUES($1,$2,$3,$4)
  ON CONFLICT (dirhash,name) DO UPDATE SET meta = EXCLUDED.meta WHERE "%[1]s".meta != EXCLUDED.meta"""
```

```
weed filer \
  -ip=node-c1 -port=8888 \
  -master=node-c1:9333,node-c2:9333,node-c3:9333 \
  -defaultReplicaPlacement=010 \
  -s3 -s3.port=8333 \
  -s3.config=/etc/seaweedfs/s3config.json \
  -s3.allowEmptyFolder=false \
  -metricsPort=9327
```

- filer 둘은 **같은 PG**를 본다. 무상태라 로드밸런서 뒤에 둬도 된다.
- PG 사이징: 파일 1천만 개당 메타 수 GB. M 티어 16GB 메모리, `shared_buffers` 4GB,
  `max_connections` ≥ filer 수 × `connection_max_open` + 여유.
- PG 백업: `pg_basebackup` 일 1회 + WAL 아카이브 연속. **이것이 클러스터 백업이다.**
- 대안 스토어: Redis(빠르지만 메모리 상주, 백업 어려움), TiKV(L 티어 수평 확장).
  M 티어는 PG가 맞다.

## 7. S3 gateway — IAM과 버킷

`/etc/seaweedfs/s3config.json`:

```json
{
  "identities": [
    { "name": "trino",   "credentials": [{ "accessKey": "…", "secretKey": "…" }],
      "actions": ["Read:lakehouse", "Write:lakehouse", "List:lakehouse", "Tagging:lakehouse",
                  "Read:trino-exchange", "Write:trino-exchange", "List:trino-exchange"] },
    { "name": "dbt",     "credentials": [{ "accessKey": "…", "secretKey": "…" }],
      "actions": ["Read:lakehouse", "Write:lakehouse", "List:lakehouse"] },
    { "name": "sumun",   "credentials": [{ "accessKey": "…", "secretKey": "…" }],
      "actions": ["Read:lakehouse", "Read:landing", "List:landing", "Write:landing"] },
    { "name": "ingest",  "credentials": [{ "accessKey": "…", "secretKey": "…" }],
      "actions": ["Write:landing", "List:landing", "Write:bronze-raw"] },
    { "name": "admin",   "credentials": [{ "accessKey": "…", "secretKey": "…" }],
      "actions": ["Admin"] }
  ]
}
```

| 버킷 | 용도 | 복제 | 보존 |
|---|---|---|---|
| `lakehouse` | **테이블 버킷** — Iceberg 테이블(Bronze/Silver/Gold) | `010` | Iceberg 스냅샷 정책 |
| `landing` | 문서 랜딩 (`00-architecture` 6.1 규약) | `010` | 매니페스트 `retention_days` |
| `bronze-raw` | 수집기가 떨구는 원본 파일(CSV·JSON), Bronze 적재 전 | `000` 가능 | 7–30일 |
| `trino-exchange` | Trino FTE 교환 데이터 | `000` | 자동 (일시) |
| `audit-export` | 수문 감사 로그 NDJSON 내보내기 | `010` + **Object Lock** `[검증 필요: SeaweedFS Object Lock 지원 범위]` | 법정 보존 |

원칙:
- **사람에게는 S3 키를 주지 않는다.** 엔진·서비스 계정만. 사람의 데이터 접근은
  Trino/Athena 경로(2계층 정책) 또는 수문.
- 키는 Vault/K8s Secret에서 주입. `s3config.json`에 평문으로 커밋하지 않는다
  (compose 픽스처만 예외).
- OIDC 연동(`-s3.config`의 OIDC 섹션 또는 IAM API)은 수문 I1 이후 `[검증 필요]`.

TLS: S3 gateway 앞에 TLS 종단(ingress 또는 `-s3.cert.file/-s3.key.file`). 사설 CA
인증서를 Trino·dbt·수문의 트러스트스토어에 배포.

## 8. Iceberg REST 카탈로그 — 테이블 버킷

SeaweedFS는 S3 Tables 호환 **테이블 버킷**을 지원하고, 그 안의 Iceberg 메타데이터를
REST 카탈로그(8181)로 서빙한다. 엔진은 카탈로그 서비스를 따로 띄우지 않는다.

```
# 테이블 버킷 생성 (weed shell)  [검증 필요: 정확한 서브커맨드]
> s3.bucket.create -name lakehouse -tableBucket
> s3.bucket.quota -name lakehouse -sizeMB 20000000
```

Trino 카탈로그 (`compose/trino/etc/catalog/iceberg.properties`가 같은 설정):

```
connector.name=iceberg
iceberg.catalog.type=rest
iceberg.rest-catalog.uri=https://s3.storage.internal:8181
iceberg.rest-catalog.warehouse=s3://lakehouse
iceberg.rest-catalog.security=SIGV4
iceberg.rest-catalog.signing-name=s3tables
iceberg.unique-table-location=true
fs.native-s3.enabled=true
s3.endpoint=https://s3.storage.internal:8333
s3.path-style-access=true
s3.region=us-east-1
```

- `unique-table-location=true` 유지 — 테이블 drop/recreate 시 잔존 파일 충돌 방지.
- 네임스페이스 = dbt 스키마(`bronze`, `silver`, `gold`). dbt가 만든다.
- Polaris로 바꿀 때: 같은 테이블 버킷을 Polaris가 카탈로그로 가리키고, Trino의
  `rest-catalog.uri`만 Polaris로. 데이터 이동 없음.

## 9. 배포

### 9.1 Kubernetes (공식 Helm 차트) — 권장

`helm/mulgil/values-sovereign.yaml`의 `seaweedfs` 블록이 공식 차트
`seaweedfs/seaweedfs`의 values로 매핑된다. 핵심 설정:

```yaml
master:
  replicas: 3
  defaultReplication: "010"
  volumeSizeLimitMB: 30000
  nodeSelector: { role: storage-control }
  affinity: # 세 파드를 서로 다른 랙(topology.kubernetes.io/zone)에
    podAntiAffinity: { requiredDuringSchedulingIgnoredDuringExecution: [ { topologyKey: topology.kubernetes.io/zone } ] }
volume:
  replicas: 4
  dataCenter: dc1
  rack: "$(NODE_RACK)"          # 노드 라벨에서 주입 [검증 필요: 차트의 rack 주입 방식]
  dataDirs:
    - { name: disk1, type: hostPath, hostPath: /data/disk1, maxVolumes: 0 }
    - { name: disk2, type: hostPath, hostPath: /data/disk2, maxVolumes: 0 }
  index: leveldb
  nodeSelector: { role: storage-data }
  resources: { requests: { cpu: 4, memory: 16Gi } }
filer:
  replicas: 2
  defaultReplicaPlacement: "010"
  extraEnvironmentVars: { WEED_POSTGRES2_ENABLED: "true", WEED_POSTGRES2_HOSTNAME: pg-primary.storage.svc, … }
  s3:
    enabled: true
    port: 8333
    existingConfigSecret: seaweedfs-s3-config
  nodeSelector: { role: storage-control }
```

- volume 파드는 `hostPath`/`local` PV로 **로컬 디스크**에. 네트워크 PV 금지.
- 노드 라벨: `role=storage-control|storage-data|compute`, `topology.kubernetes.io/zone=rackA|rackB`.
- PostgreSQL은 CloudNativePG 또는 Zalando operator로 primary/standby. 차트 내장 PG는 PoC만.
- Ingress: S3(8333)·Iceberg(8181)만 노출. master·filer는 ClusterIP.

### 9.2 베어메탈 / VM (systemd)

K8s가 없는 폐쇄망에서. 바이너리 하나(`weed`)를 노드마다 두고 systemd 유닛 4종
(master·volume·filer·s3). 4–7장의 플래그를 `EnvironmentFile`로. 업그레이드는
바이너리 교체 + 롤링 재시작(master → volume → filer 순). 이 경로의 유닛 파일은
`helm/mulgil/systemd/`에 둔다 `[작성 예정]`.

## 10. 기동 순서와 검증

```
1. PostgreSQL primary/standby 기동, seaweedfs DB·사용자 생성
2. master ×3 기동 → http://node-c1:9333/cluster/status 에서 리더 확인
3. volume ×N 기동 → master UI에서 DC/랙별 볼륨 수 확인
4. filer ×2 기동 → http://node-c1:8888/ 디렉터리 생성 테스트
5. S3 gateway → aws --endpoint-url https://…:8333 s3 ls
6. 테이블 버킷 생성, Iceberg REST → curl https://…:8181/v1/config
7. Trino 기동 → SHOW SCHEMAS FROM iceberg
8. dbt seed/run (scripts/seed.sh) → gold_revenue_daily 조회
```

검증 체크리스트:
- [ ] `weed shell` → `volume.list`: 모든 볼륨이 `010`대로 **다른 랙**에 사본
- [ ] 랙 A의 volume 서버 하나 정지 → S3 읽기 계속됨 → 복구 후 `volume.fix.replication`
- [ ] filer 하나 정지 → S3 계속됨
- [ ] PG standby 승격 리허설 → filer 재연결
- [ ] master 하나 정지 → 리더 재선출, 쓰기 계속됨
- [ ] 10MB Parquet 1만 개 쓰기 → filer PG 크기·지연 기록 (소형 파일 기준선)
- [ ] 메트릭이 Prometheus에 수집됨 (`observability/prometheus/`)

## 11. 운영

| 작업 | 주기 | 명령 / 방법 |
|---|---|---|
| filer PG 백업 | 일 1회 + WAL 연속 | `pg_basebackup`, WAL 아카이브를 **다른 랙**의 스토리지로 |
| 볼륨 밸런스 | 주 1회 또는 노드 추가 후 | `weed shell` → `volume.balance -force` |
| 복제 수선 | 디스크·노드 장애 후 | `volume.fix.replication` |
| vacuum | 자동(임계 0.3) | Iceberg `expire_snapshots` 직후 공간 회수 확인 |
| 디스크 교체 | 고장 시 | 해당 `-dir` 제거 → 프로세스 재시작 → `fix.replication` → 새 디스크 추가 |
| 노드 추가 | 85% 도달 전 | volume 프로세스 추가 → `volume.balance` |
| 업그레이드 | 분기 | master → volume → filer → s3 순 롤링. 메이저 전 PG 백업 |
| 인증서 갱신 | 만료 30일 전 | ingress 또는 `-s3.cert.file` 교체, 클라이언트 트러스트스토어 |

알람 임계값(Prometheus, `observability/prometheus/alerts.yml`):
- 디스크 사용률 > 85% (warning), > 90% (critical)
- 복제 부족 볼륨 > 0 (5분 지속, critical)
- filer PG 커넥션 > 80% `max_connections`
- master 리더 없음 (1분, critical)
- 볼륨당 파일 수 급증(소형 파일 폭증 신호) → 컴팩션 점검

## 12. 수문·물길 관점의 연결

| 수문/물길 요소 | SeaweedFS에서의 대응 |
|---|---|
| 문서 랜딩 규약 (`00-architecture` 6.1) | `landing` 버킷, `sumun` 신원은 읽기, `ingest` 신원은 쓰기 |
| Iceberg 테이블 | `lakehouse` 테이블 버킷 + REST 8181 |
| 감사 로그 WORM 내보내기 | `audit-export` 버킷 + Object Lock `[검증 필요]` |
| 삭제 조율 (row delete → 스냅샷 만료) | vacuum이 실제 디스크 공간을 회수하는 시점까지가 "삭제 완료". ops 모듈이 추적 |
| 호출자별 비용 | S3 접근 로그 + volume 메트릭 → `observability/cost/` |
| Trino FTE | `trino-exchange` 버킷, 복제 `000` |

## 13. 설치 전 체크리스트

- [ ] 노드 라벨(역할·랙) 부여, 데이터 노드 디스크 XFS `noatime` 마운트
- [ ] PG primary/standby, 백업 대상 스토리지 확보
- [ ] 사설 CA, S3/REST 인증서
- [ ] `s3config.json`의 신원 5개와 키를 Vault/Secret에
- [ ] 복제 문자열 결정 (`010` 기본), 버킷별 예외
- [ ] 방화벽: 외부 → 8333·8181만
- [ ] Prometheus 스크레이프 대상 등록
- [ ] 10장 검증 체크리스트를 통과한 뒤에만 Trino를 붙인다
