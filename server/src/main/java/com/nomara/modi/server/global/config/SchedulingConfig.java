package com.nomara.modi.server.global.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * 이 프로젝트 최초의 배치({@code @Scheduled}) 도입점(2026-08-05, 알림 트리거 6종 작업). 지금까지는 방 {@code ENDED} 자동 전환도, 방
 * 삭제 유예도 전부 "요청 시점 lazy 체크"로 배치 없이 처리해왔다(specs/OPEN.md, 2026-07-30 확정 — "별도 배치 인프라가 불필요해졌다"). 일정
 * 전날/디데이 알림만은 그 패턴으로 대체할 수 없다 — 아무도 앱을 열지 않아도 정해진 시각(08:00 KST)에 푸시가 나가야 하기 때문이다.
 *
 * <p>그래서 이 기능(schedule 도메인의 {@code ScheduleReminderService})에 한해 스케줄러를 도입한다. 기존 두 확정 기록을 무효화하는 게
 * 아니다 — "상태 전환"류는 여전히 lazy 체크로 충분하고, "예정된 시각에 알림을 능동적으로 밀어야 하는" 기능에만 배치가 필요하다는 뜻이다.
 */
@Configuration
@EnableScheduling
public class SchedulingConfig {}
