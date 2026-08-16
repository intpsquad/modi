package com.nomara.modi.server.domain.dashboard.controller;

import com.nomara.modi.server.domain.dashboard.dto.DashboardResponse;
import com.nomara.modi.server.domain.dashboard.service.DashboardService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.ZoneId;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** specs/0005-홈-대시보드.md 기준 홈 대시보드(S-04) 조회 엔드포인트. */
@RestController
public class DashboardController {

  /**
   * 주간 캘린더의 기준 "이번 주"는 <b>한국 시간</b> 기준이다. 2026-08-16 추가 — 그전에는 무인자 {@code LocalDate.now()} 라 UTC 로
   * 도는 운영 JVM 에서 KST 월요일 00:00~09:00 사이 요청이 <b>지난 주</b> 월요일을 돌려줬다({@code Sunday.with(MONDAY)} 는 같은
   * ISO 주의 월요일 = 6일 전).
   *
   * <p>앱은 항상 {@code weekStart} 를 직접 보내므로(app/lib/features/home/home_api.dart) 이 기본값은 실제로 쓰이지 않지만,
   * 기본값이 틀린 채 남아 있으면 다른 클라이언트가 그대로 밟는다.
   */
  private static final ZoneId KST = ZoneId.of("Asia/Seoul");

  private final DashboardService dashboardService;

  public DashboardController(DashboardService dashboardService) {
    this.dashboardService = dashboardService;
  }

  @GetMapping("/rooms/{roomId}/dashboard")
  public DashboardResponse getDashboard(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
          LocalDate weekStart,
      @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
          LocalDate weekEnd) {
    LocalDate resolvedStart =
        weekStart != null ? weekStart : LocalDate.now(KST).with(DayOfWeek.MONDAY);
    LocalDate resolvedEnd = weekEnd != null ? weekEnd : resolvedStart.plusDays(6);
    return dashboardService.getDashboard(uid(request), roomId, resolvedStart, resolvedEnd);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
