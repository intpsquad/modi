package com.nomara.modi.server.domain.dashboard.controller;

import com.nomara.modi.server.domain.dashboard.dto.DashboardResponse;
import com.nomara.modi.server.domain.dashboard.service.DashboardService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.time.DayOfWeek;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** specs/0005-홈-대시보드.md 기준 홈 대시보드(S-04) 조회 엔드포인트. */
@RestController
public class DashboardController {

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
        weekStart != null ? weekStart : LocalDate.now().with(DayOfWeek.MONDAY);
    LocalDate resolvedEnd = weekEnd != null ? weekEnd : resolvedStart.plusDays(6);
    return dashboardService.getDashboard(uid(request), roomId, resolvedStart, resolvedEnd);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
