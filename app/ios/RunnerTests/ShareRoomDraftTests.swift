import XCTest

@testable import Runner

/// 공유하기에서 새 방을 만들 때의 입력 규칙(이슈 #108).
///
/// 앱의 방 만들기 화면(`create_room_screen.dart`)과 같은 규칙이어야 한다 — 이름 30자·목표 필수·
/// 시작일은 오늘·종료일 기본값은 4주 뒤·고를 수 있는 범위는 오늘부터 5년 뒤 1월 1일까지.
///
/// ⚠️ **CI 는 이 파일을 돌리지 않는다** — `ShareContentTests.swift` 머리말 참고. 사람이 돌린다:
/// `xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
final class ShareRoomDraftTests: XCTestCase {
  private let seoul = TimeZone(identifier: "Asia/Seoul")!

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = seoul
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  private var today: Date { date(2026, 10, 17) }

  private func validate(
    name: String = "주말 러닝",
    goal: String = "매주 10km",
    endDate: Date? = nil
  ) -> Result<ShareRoomDraft, ShareRoomDraftError> {
    ShareRoomDraft.validate(
      name: name, goal: goal, endDate: endDate ?? date(2026, 11, 14),
      today: today, calendar: calendar)
  }

  // MARK: - 날짜

  func testDefaultEndDateIsFourWeeksFromToday() {
    XCTAssertEqual(
      ShareRoomDraft.defaultEndDate(today: today, calendar: calendar),
      calendar.startOfDay(for: date(2026, 11, 14))
    )
  }

  /// 앱의 날짜 선택기와 같은 범위다(`firstDate: today`, `lastDate: DateTime(today.year + 5)`).
  func testSelectableRangeIsTodayToJanuaryFirstFiveYearsLater() {
    let range = ShareRoomDraft.selectableEndDates(today: today, calendar: calendar)

    XCTAssertEqual(range.lowerBound, calendar.startOfDay(for: today))
    XCTAssertEqual(range.upperBound, calendar.startOfDay(for: date(2031, 1, 1)))
  }

  // MARK: - 입력 검사

  func testTrimsNameAndGoal() {
    XCTAssertEqual(
      validate(name: "  주말 러닝 \n", goal: "\t매주 10km  "),
      .success(
        ShareRoomDraft(
          name: "주말 러닝", goal: "매주 10km",
          endDate: calendar.startOfDay(for: date(2026, 11, 14))))
    )
  }

  func testRequiresName() {
    XCTAssertEqual(validate(name: "   "), .failure(.nameRequired))
  }

  func testRequiresGoal() {
    XCTAssertEqual(validate(goal: "  "), .failure(.goalRequired))
  }

  func testAllowsThirtyCharacterName() {
    let name = String(repeating: "가", count: 30)

    XCTAssertEqual(try validate(name: name).get().name, name)
  }

  func testRejectsNameLongerThanThirtyCharacters() {
    XCTAssertEqual(
      validate(name: String(repeating: "가", count: 31)), .failure(.nameTooLong))
  }

  /// 자정을 넘겨 제출하면 아까 고른 "오늘"이 어제가 된다. 서버는 그걸 400 으로 거절한다
  /// ("시작일은 종료일보다 늦을 수 없어요") — 보내기 전에 알려준다.
  func testRejectsEndDateBeforeToday() {
    XCTAssertEqual(validate(endDate: date(2026, 10, 16)), .failure(.endDateBeforeToday))
  }

  func testAllowsEndingToday() {
    XCTAssertEqual(
      try validate(endDate: date(2026, 10, 17, hour: 23)).get().endDate,
      calendar.startOfDay(for: today)
    )
  }

  func testEachErrorHasMessage() {
    XCTAssertEqual(ShareRoomDraftError.nameRequired.message, "방 이름을 입력해 주세요")
    XCTAssertEqual(ShareRoomDraftError.nameTooLong.message, "방 이름은 30자 이내로 입력해 주세요")
    XCTAssertEqual(ShareRoomDraftError.goalRequired.message, "방 목표를 입력해 주세요")
    XCTAssertEqual(ShareRoomDraftError.endDateBeforeToday.message, "종료 날짜를 오늘 이후로 골라 주세요")
  }

  // MARK: - 서버로 보낼 값

  /// `POST /rooms` 의 `CreateRoomRequest`. 대표 이미지·목표 상세는 공유하기에서 받지 않는다.
  func testBuildsCreateRoomBodyWithTodayAsStartDate() throws {
    let draft = try validate().get()

    XCTAssertEqual(
      draft.requestBody(today: today, calendar: calendar),
      [
        "name": "주말 러닝",
        "goal": "매주 10km",
        "startDate": "2026-10-17",
        "endDate": "2026-11-14",
      ]
    )
  }

  /// 서울 새벽 0시 30분은 UTC 로 전날이다. 날짜는 사용자가 보는 달력 기준이어야 한다.
  func testFormatsDatesInLocalTimeZone() throws {
    let justAfterMidnight = date(2026, 10, 17, hour: 0).addingTimeInterval(30 * 60)
    let draft = ShareRoomDraft(
      name: "방", goal: "목표", endDate: calendar.startOfDay(for: date(2026, 10, 18)))

    let body = draft.requestBody(today: justAfterMidnight, calendar: calendar)

    XCTAssertEqual(body["startDate"], "2026-10-17")
    XCTAssertEqual(body["endDate"], "2026-10-18")
  }

  /// 기기 달력이 불기·일본력이어도 서버에는 서력 날짜가 가야 한다.
  func testFormatsDatesInGregorianEvenIfDeviceUsesAnotherCalendar() throws {
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = seoul
    let draft = ShareRoomDraft(name: "방", goal: "목표", endDate: date(2026, 11, 14))

    let body = draft.requestBody(today: today, calendar: buddhist)

    XCTAssertEqual(body["startDate"], "2026-10-17")
    XCTAssertEqual(body["endDate"], "2026-11-14")
  }
}
