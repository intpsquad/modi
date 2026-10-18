import Foundation

enum ShareRoomDraftError: Error, Equatable {
  case nameRequired
  case nameTooLong
  case goalRequired
  case endDateBeforeToday

  var message: String {
    switch self {
    case .nameRequired: return "방 이름을 입력해 주세요"
    case .nameTooLong: return "방 이름은 \(ShareRoomDraft.nameMaxLength)자 이내로 입력해 주세요"
    case .goalRequired: return "방 목표를 입력해 주세요"
    case .endDateBeforeToday: return "종료 날짜를 오늘 이후로 골라 주세요"
    }
  }
}

/// 공유하기에서 만드는 새 방의 입력값(이슈 #108).
///
/// 🔴 **앱의 방 만들기 화면(`create_room_screen.dart`)과 같은 규칙이다.** 한쪽을 바꾸면 다른 쪽도
/// 바꾼다 — 이름 30자·목표 필수·시작일은 오늘·종료일 기본값 4주 뒤·고를 수 있는 끝은 5년 뒤 1월 1일.
/// 대표 이미지와 목표 상세는 공유하기에서 받지 않는다(나중에 앱에서 수정).
///
/// 서버(`POST /rooms`)는 이름 길이를 따로 검사하지 않으므로 여기서 막는다.
struct ShareRoomDraft: Equatable {
  static let nameMaxLength = 30
  private static let defaultDurationDays = 28
  private static let selectableYears = 5

  let name: String
  let goal: String
  /// 그날 0시(`calendar` 의 시간대 기준).
  let endDate: Date

  /// 기기 시간대의 서력 달력. 기기 달력이 불기·일본력이어도 앱과 같은 날짜 계산을 하게 한다.
  static var deviceCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  static func defaultEndDate(today: Date, calendar: Calendar) -> Date {
    let start = calendar.startOfDay(for: today)
    return calendar.date(byAdding: .day, value: defaultDurationDays, to: start) ?? start
  }

  static func selectableEndDates(today: Date, calendar: Calendar) -> ClosedRange<Date> {
    let start = calendar.startOfDay(for: today)
    let year = calendar.component(.year, from: start)
    let last = calendar.date(from: DateComponents(year: year + selectableYears, month: 1, day: 1))
    return start...max(start, last ?? start)
  }

  static func validate(
    name: String,
    goal: String,
    endDate: Date,
    today: Date,
    calendar: Calendar
  ) -> Result<ShareRoomDraft, ShareRoomDraftError> {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return .failure(.nameRequired) }
    guard name.count <= nameMaxLength else { return .failure(.nameTooLong) }
    guard !goal.isEmpty else { return .failure(.goalRequired) }

    // 날짜를 고른 뒤 자정을 넘겨 제출하면 "오늘"이 어제가 된다. 서버가 400 으로 거절하기 전에 알려준다.
    let end = calendar.startOfDay(for: endDate)
    guard end >= calendar.startOfDay(for: today) else { return .failure(.endDateBeforeToday) }
    return .success(ShareRoomDraft(name: name, goal: goal, endDate: end))
  }

  /// `POST /rooms` 의 본문(`CreateRoomRequest`). 시작일은 오늘이다.
  func requestBody(today: Date, calendar: Calendar) -> [String: String] {
    [
      "name": name,
      "goal": goal,
      "startDate": Self.serverDay(today, in: calendar),
      "endDate": Self.serverDay(endDate, in: calendar),
    ]
  }

  /// 서버의 `LocalDate`(`yyyy-MM-dd`). 시간대는 `calendar` 를 따르고 연도는 늘 서력이다.
  private static func serverDay(_ date: Date, in calendar: Calendar) -> String {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    let parts = gregorian.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
