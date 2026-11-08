# 2. 테이블 (Tables)

> Phase 2 — 첫 번째로 구현.

## 목적
플랫폼이 가진 데이터 자산의 단일 목록. 소유자·PII·계약·건강을 한 줄에 보여주고,
Iceberg 유지보수를 여기서 실행·예약한다. 콘솔에서 가장 많이 쓰이는 화면.

## 목록 (`GET /tables`)
| 열 | 출처 | 비고 |
|---|---|---|
| 이름 | dbt manifest `name`, 카탈로그 `schema.table` | 레이어 배지 Bronze/Silver/Gold |
| 소유자 | schema.yml `meta.owner` | 없으면 "미지정" 빨간 배지 (Gold는 계약 위반) |
| PII | `meta.pii` 태그 수 | 호버 시 컬럼·태그 목록 (`rrn`, `phone`, …) |
| 계약 | Gold만. `meta.contract`, `meta.sla_hours` | 있음/없음, 위반 시 빨강 |
| 신선도 | 마지막 스냅샷 시각 | SLA 대비 % 바 |
| 크기 | Iceberg `$files` 합 | 바이트 + 파일 수 |
| 건강 | `/tables/{id}/health` 등급 | good/warn/bad 점. 호버에 감점 사유 |
| 마지막 유지보수 | `ops_actions` | 종류와 시각 |

필터: 레이어, 소유자, 건강 등급, PII 포함 여부, 계약 위반, 텍스트 검색.
정렬 기본값: 건강 bad → warn → good, 그 안에서 크기 내림차순.

## 상세 (`GET /tables/{id}`)
탭 네 개.
1. **개요** — 스키마(컬럼·타입·PII 태그·설명), 소유자, 계약 본문, 상류 모델(dbt 리니지 1단계), 하류 모델.
2. **건강** — 점수와 항목별 감점 근거(소형 파일 비율, 스냅샷 수, 마지막 compaction, 신선도, 파티션 편중). 각 항목 옆에 권장 action.
3. **스냅샷** — `$snapshots` 목록(ID, 시각, 작업 종류, 추가/삭제 파일 수). 보존 정책 표시.
4. **유지보수** — 실행 이력(`/actions?table=`), 예약 설정, 실행 패널.

## 동작 (operator)
- **유지보수 실행**: action 선택(optimize / expire_snapshots / remove_orphan_files) → 파라미터(expire: `older_than_days`, `retain_last`; optimize: `where` 선택) → **dry run 필수** → 영향 범위(파일 수·바이트·스냅샷 수) 확인 → 실행. 진행 중이면 버튼 비활성 + 진행 링크.
- **예약**: optimize cron, expire 보존 일수·최소 보존 수. 저장 시 DAG 변수 갱신, 다음 실행 예정 시각 표시.
- viewer는 패널을 보되 버튼 비활성, 툴팁 "operator 권한 필요".

## 빈 상태·오류
- 테이블 0개: "dbt 모델이 아직 실행되지 않았습니다" + seed 명령.
- Iceberg 메타 조회 실패(엔진 다운): 목록은 manifest 기반으로 표시, 크기·건강 열은 "—"와 배너.
- aws-serverless에서 remove_orphan_files: `profile_unsupported` → 버튼 숨기고 "S3 Tables가 자동 처리" 안내.

## 인수 기준
- [ ] 시드 데이터 기준 7개 모델이 레이어·소유자·PII와 함께 목록에 뜬다.
- [ ] 소형 파일 60%인 테이블이 bad로 표시되고 근거에 "소형 파일 비율 60% (−30)"가 보인다.
- [ ] dry run 없이 실행 버튼이 활성화되지 않는다.
- [ ] optimize 실행 후 DAG 실행이 생성되고, 완료 후 건강 점수가 재계산된다.
- [ ] viewer 토큰으로 POST 시 403 `not_operator`.
