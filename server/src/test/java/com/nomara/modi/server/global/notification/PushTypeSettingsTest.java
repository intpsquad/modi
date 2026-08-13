package com.nomara.modi.server.global.notification;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import com.nomara.modi.server.domain.user.entity.User;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * 알림 <b>스위치와 알림 종류의 연결</b>을 못 박는다.
 *
 * <p>🔴 <b>왜 필요한가.</b> 2026-08-06 에 설정 화면의 「재촉 (노크)」 토글이 <b>아무것도 막지 않는 스위치</b>였다는 것을 발견했다 — 컬럼도 있고,
 * API 도 있고, 화면에 보이기까지 했는데 그 값을 읽는 {@link PushType} 이 없었다. 사용자가 꺼도 알림은 그대로 왔다.
 *
 * <p>그런 실수는 단위 테스트로 안 잡힌다. 각 알림 기능은 자기 테스트를 통과하고, <b>연결이 없다는 사실 자체</b>는 아무도 안 본다. 그래서 여기서 두 방향을 모두
 * 고정한다 — 알림 종류마다 진짜 스위치가 있는가, 그리고 스위치마다 그걸 읽는 알림이 있는가.
 */
class PushTypeSettingsTest {

  /**
   * 알림 종류와 짝이 없어도 되는 필드.
   *
   * <ul>
   *   <li>{@code allEnabled} — 개별 알림 종류를 막는 스위치가 아니라, 개별 7종이 전부 켜졌는지를 나타내는 파생값이다(2026-08-08 결정). 발송
   *       여부 판단에는 쓰이지 않는다.
   * </ul>
   *
   * <p>{@code knockEnabled}는 2026-08-09 컬럼·DTO·{@code PokeType.KNOCK}과 함께 완전히 제거됐다(`V27`) — 필드 자체가
   * 없어져 리플렉션 대상에서도 자연히 빠지므로 더 이상 이 목록에 둘 이유가 없다.
   */
  private static final Set<String> NOT_A_PUSH_SWITCH = Set.of("allEnabled");

  @Test
  @DisplayName("알림 종류마다 그것만 끄는 스위치가 있다")
  void every_push_type_is_wired_to_exactly_one_switch() {
    for (PushType type : PushType.values()) {
      List<String> switchesThatSilenceIt =
          booleanFieldNames().stream().filter(field -> silences(type, field)).toList();

      // 0개면 스위치가 없는 알림(= 끌 수 없다), 2개 이상이면 남의 스위치까지 읽는 것이다.
      assertThat(switchesThatSilenceIt).as("%s 를 끄는 설정 필드", type).hasSize(1);
    }
  }

  @Test
  @DisplayName("스위치마다 그것을 읽는 알림이 있다 — 죽은 스위치를 만들지 않는다")
  void every_switch_silences_some_push_type() {
    Set<String> wired = new LinkedHashSet<>();
    for (PushType type : PushType.values()) {
      booleanFieldNames().stream().filter(field -> silences(type, field)).forEach(wired::add);
    }

    List<String> deadSwitches =
        booleanFieldNames().stream()
            .filter(field -> !NOT_A_PUSH_SWITCH.contains(field))
            .filter(field -> !wired.contains(field))
            .toList();

    // 🔴 여기가 빨개지면 "끌 수 있는데 아무것도 안 막는 스위치"를 방금 만든 것이다.
    // 설정 화면에 토글까지 달면 사용자가 껐다고 믿는데 알림은 계속 온다 — 노크가 그랬다.
    assertThat(deadSwitches)
        .as("이 설정을 읽는 PushType 이 없다 — 알림 종류를 추가하거나, 스위치를 지우거나, 이유를 적고 예외 목록에 넣을 것")
        .isEmpty();
  }

  @Test
  @DisplayName("자료 분석 알림은 새 스위치를 읽는다")
  void archive_analysis_reads_its_own_switch() {
    // 위 두 테스트는 "연결이 있다"만 본다. 이번에 추가한 것이 **의도한 그 필드**인지도 못 박는다.
    assertThat(silences(PushType.ARCHIVE_ANALYSIS_DONE, "archiveAnalysisDoneEnabled")).isTrue();
    assertThat(PushType.ARCHIVE_ANALYSIS_DONE.isEnabled(allOn())).isTrue();
  }

  /** {@code field} 하나만 끈 설정에서 {@code type} 이 꺼지는가. */
  private static boolean silences(PushType type, String field) {
    NotificationSetting setting = allOn();
    ReflectionTestUtils.setField(setting, field, false);
    return !type.isEnabled(setting);
  }

  private static NotificationSetting allOn() {
    // 생성자가 모든 스위치를 true 로 채운다 — 새 필드를 추가하면서 거기 빠뜨리면
    // 위 테스트들이 "그 필드는 원래 false" 로 오해하지 않도록 생성자를 그대로 쓴다.
    return new NotificationSetting(new User("uid-push-type", "닉네임", null));
  }

  private static List<String> booleanFieldNames() {
    return Arrays.stream(NotificationSetting.class.getDeclaredFields())
        .filter(f -> f.getType() == boolean.class)
        .filter(f -> !Modifier.isStatic(f.getModifiers()))
        // isNew 는 영속 여부 표시(@Transient)라 알림 설정이 아니다.
        .filter(f -> !"isNew".equals(f.getName()))
        .map(Field::getName)
        .toList();
  }
}
