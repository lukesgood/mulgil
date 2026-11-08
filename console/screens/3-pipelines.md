# 3. 파이프라인 (Pipelines)

## 목적
dbt 실행이 성공했는지, 어느 모델이 왜 실패했는지, 데이터 계약 SLA가 지켜지는지
보고 실패분을 재실행한다. DAG 작성·편집은 하지 않는다 — Airflow 링크.

## 데이터
- `GET /pipelines/runs` — 실행 목록: run_id, 트리거(schedule/manual/rerun), 시작·종료, 상태, 모델 수(성공/실패/스킵), 소요 시간. 출처는 Airflow REST(sovereign·aws-trino) 또는 Step Functions(aws-serverless) + dbt `run_results.json`.
- `GET /pipelines/runs/{run_id}` — 모델별 결과: 이름, 레이어, 상태, 실행 시간, 행 수, 실패 메시지 첫 줄, 로그 링크(Airflow 태스크 로그 URL).
- `GET /contracts/violations` — 종류 `sla_breach | schema_drift | missing_owner | missing_contract`, 테이블, 발생 시각, 현재 지속 여부.

## 화면 구성
1. **실행 타임라인** — 최근 30회 막대(성공 녹/실패 적/진행 파랑), 길이 = 소요 시간. 클릭 → 상세.
2. **실행 목록 표** — 필터: 상태, 기간, 트리거.
3. **실행 상세 드로어** — 모델 표. 실패 모델 상단 고정. "실패분만 재실행" / "전체 재실행" 버튼.
4. **계약 위반 패널** — 열린 위반 목록, 각 행에 테이블 링크와 소유자.
5. **일정** — 다음 예정 실행, 유지보수 DAG 예정(테이블 화면에서 설정한 것의 읽기 뷰).

## 동작 (operator)
- `POST /pipelines/runs/{run_id}/rerun` `{scope: failed|all}`. 진행 중 run이 있으면 `action_in_progress`.
- 재실행은 새 run으로 목록에 추가되고 원 run과 `rerun_of`로 연결.

## 빈 상태·오류
- 실행 0회: "첫 실행 대기 — Airflow DAG `mulgil_dbt` 활성화 여부 확인" + Airflow 링크.
- 오케스트레이터 API 불가: run_results.json 기반으로 마지막 실행만 표시, 배너.
- aws-serverless에서 모델별 로그 링크 없음(Step Functions): CloudWatch 로그 그룹 링크로 대체.

## 인수 기준
- [ ] 의도적으로 실패시킨 모델이 상세에서 상단에 메시지와 함께 보인다.
- [ ] "실패분만 재실행"이 해당 모델과 하류만 실행한다(dbt `--select result:error+`).
- [ ] Gold 테이블 신선도가 `sla_hours`를 넘으면 10분 내 `sla_breach`가 위반 패널에 나타난다.
- [ ] 소유자 없는 Gold 모델은 `missing_owner`로 잡힌다.
