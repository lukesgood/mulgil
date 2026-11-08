# 6. 알람 (Alerts)

## 목적
임계값 규칙과 알림 채널을 콘솔에서 관리하고, 지금 울리는 것과 과거 이력을 본다.
평가와 라우팅은 Prometheus/Alertmanager가 하고, 콘솔은 규칙을 쓰고 상태를 읽는다.

## 데이터
- `GET /alerts/rules` — 규칙: 이름, 표현식(PromQL 또는 ops 내장 규칙 ID), 조건 요약(사람 읽는 형태), 지속 시간, 심각도, 채널, 활성 여부, 출처(`bundled` / `custom`).
- `GET /alerts/history?from&to` — 발생: 규칙, 시작·종료, 심각도, 라벨(테이블·노드), 처리(silenced/resolved), 사유.
- Alertmanager API — 현재 firing, silence 목록.

## 번들 규칙 (설치 시 포함, `observability/alerts/*.yaml`)
인프라 가이드 10.2와 동일: 디스크 85/90%, 복제 부족 볼륨, 마스터 리더 부재, filer 무응답, PostgreSQL 커넥션·복제 지연·WAL 실패, 볼륨당 파일 수 급증, NTP 오프셋. 추가로 데이터 규칙: 계약 SLA 위반, dbt 실행 실패, 테이블 건강 bad 전환, 월 비용 예측이 전월 120% 초과.

## 화면 구성
1. **지금 울리는 알람** — 심각도 순 카드. 각 카드: 규칙, 대상 라벨, 지속 시간, "일시 중지" 버튼, 관련 화면 링크(테이블/스토리지/파이프라인).
2. **규칙 표** — 번들/사용자 구분, 활성 토글, 편집. 번들 규칙은 임계값·심각도·채널만 편집 가능, 표현식은 잠금.
3. **규칙 편집 드로어** — 내장 규칙: 폼(임계값, 지속, 심각도, 채널). 사용자 규칙: PromQL 입력 + 미리보기(최근 24시간 평가 결과 그래프).
4. **채널** — Slack webhook, 이메일(SMTP), 웹훅. 테스트 발송 버튼.
5. **이력** — 기간 필터, 규칙별 발생 빈도 막대.

## 동작 (operator)
- `PUT /alerts/rules/{name}` → rule 파일 렌더, Prometheus reload, Alertmanager 라우트 갱신. 적용 결과(reload 성공/실패) 즉시 표시.
- `POST /alerts/{fingerprint}/silence` `{duration, reason}` — 사유 필수, 최대 7일.
- 채널 비밀값(webhook URL, SMTP 비밀번호)은 콘솔에 표시하지 않음. Kubernetes Secret / `.env` 참조명만.

## 빈 상태·오류
- Alertmanager 불가: 규칙 편집은 가능하되 "적용 보류" 표시, firing 목록은 Prometheus `/api/v1/alerts`로 대체.
- 채널 미설정: 상단 배너 "알람이 아무 데도 가지 않습니다".

## 인수 기준
- [ ] 디스크 임계값을 85→80으로 바꾸면 60초 내 Prometheus rule에 반영된다(reload 확인).
- [ ] 테스트 발송이 Slack 채널에 도착한다.
- [ ] silence 후 해당 알람이 firing 목록에서 "일시 중지(사유)"로 바뀌고 채널 발송이 멈춘다.
- [ ] 번들 규칙의 표현식 필드는 UI와 API 모두에서 수정이 거부된다.
