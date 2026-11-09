# 1. 개요 (Overview)

> Phase 2a — 2·6 다음에.

## 목적
운영자가 아침에 한 번 열어 "오늘 손댈 것이 있는가"를 30초 안에 판단하는 화면.
숫자는 모두 다른 화면으로 가는 입구이며, 이 화면에서 직접 수행하는 작업은 없다.

## 데이터
`GET /overview` 한 번. 응답 구성:

| 영역 | 필드 | 표시 |
|---|---|---|
| 상태 라인 | `components[]: {name, status: ok\|degraded\|down, since}` — 쿼리 엔진, 소스 카탈로그 n개, 수문 서버, (랜딩존 설치 시) 카탈로그·오케스트레이터·저장소 | 한 줄 점 5개. down이 있으면 라인 전체를 빨간 배경 |
| 용량 | `storage.used_bytes, capacity_bytes, trend_7d[]` | 사용률 게이지 + 7일 스파크라인. 85% 이상 주황, 90% 이상 빨강 |
| 비용 | `cost.mtd, cost.forecast_month, cost.prev_month, by_profile[]` | 이달 누계와 예측, 전월 대비 % |
| 테이블 건강 | `tables.total, by_grade: {good, warn, bad}` | 세 칸 숫자. bad 클릭 → 테이블 화면 `?health=bad` |
| 계약 위반 | `contracts.open_violations, worst: {table, kind, age}` | 숫자 + 최악 1건 요약 |
| 파이프라인 | `pipelines.last_run: {status, finished_at, failed_models}` , `next_run_at` | 마지막 실행 결과와 다음 예정 |
| 알람 | `alerts.firing[]: {name, severity, since}` 최대 5건 | 심각도 순 |
| 최근 작업 | `actions.recent[]` 5건 | 누가 무엇을 언제 |

## 동작
- 각 카드 클릭 → 해당 화면으로 이동(필터 포함).
- 자동 새로고침 60초. `_degraded`가 비어 있지 않으면 상단에 "일부 데이터 지연: Prometheus" 배너.

## 빈 상태·오류
- 설치 직후(테이블 0개): 건강·계약·비용 카드 대신 "첫 dbt 실행을 기다리는 중 — `scripts/seed.sh`" 안내.
- ops API 자체 불가: 전체 화면 대신 마지막 성공 응답 시각과 재시도 버튼.
- 비용 단가표 미입력(trino-k8s 온프렘, 단가표): 비용 카드는 금액 대신 "자원량만 표시 — 단가표 입력" 링크.

## 인수 기준
- [ ] 다섯 컴포넌트 중 하나를 내리면 60초 내 상태 라인에 반영된다.
- [ ] 소스 하나(Prometheus)를 내려도 나머지 카드는 정상 표시되고 배너가 뜬다.
- [ ] bad 등급 숫자 클릭 시 테이블 화면이 `health=bad` 필터로 열린다.
- [ ] 첫 로드 2초 이내(캐시된 overview 응답).
