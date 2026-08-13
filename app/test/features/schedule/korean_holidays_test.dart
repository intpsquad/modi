import 'package:app/features/schedule/korean_holidays.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KoreanHolidays', () {
    test('2026 고정 공휴일을 알아본다', () {
      expect(KoreanHolidays.isHoliday(DateTime(2026, 1, 1)), isTrue);
      expect(KoreanHolidays.isHoliday(DateTime(2026, 3, 1)), isTrue);
      expect(KoreanHolidays.isHoliday(DateTime(2026, 6, 6)), isTrue);
      expect(KoreanHolidays.isHoliday(DateTime(2026, 8, 15)), isTrue);
      expect(KoreanHolidays.isHoliday(DateTime(2026, 12, 25)), isTrue);
    });

    test('2026 설 연휴 3일이 모두 공휴일이다', () {
      expect(KoreanHolidays.nameOf(DateTime(2026, 2, 16)), '설 연휴');
      expect(KoreanHolidays.nameOf(DateTime(2026, 2, 17)), '설날');
      expect(KoreanHolidays.nameOf(DateTime(2026, 2, 18)), '설 연휴');
      // 연휴 앞뒤는 평일이다.
      expect(KoreanHolidays.isHoliday(DateTime(2026, 2, 19)), isFalse);
    });

    test('2026 추석 연휴 3일이 모두 공휴일이다', () {
      expect(KoreanHolidays.nameOf(DateTime(2026, 9, 24)), '추석 연휴');
      expect(KoreanHolidays.nameOf(DateTime(2026, 9, 25)), '추석');
      expect(KoreanHolidays.nameOf(DateTime(2026, 9, 26)), '추석 연휴');
      expect(KoreanHolidays.isHoliday(DateTime(2026, 9, 23)), isFalse);
    });

    test('2026 대체공휴일이 표에 들어 있다', () {
      expect(KoreanHolidays.nameOf(DateTime(2026, 3, 2)), '대체공휴일(삼일절)');
      expect(KoreanHolidays.nameOf(DateTime(2026, 5, 25)), '대체공휴일(부처님오신날)');
      expect(KoreanHolidays.nameOf(DateTime(2026, 8, 17)), '대체공휴일(광복절)');
      expect(KoreanHolidays.nameOf(DateTime(2026, 10, 5)), '대체공휴일(개천절)');
    });

    test('2026년 법 개정으로 살아난 제헌절·노동절이 공휴일이다', () {
      // 2026-02-10·04-09 「공휴일에 관한 법률」 개정. 옛 달력을 베끼면 빠지는 두 날이다.
      expect(KoreanHolidays.nameOf(DateTime(2026, 7, 17)), '제헌절');
      expect(KoreanHolidays.nameOf(DateTime(2026, 5, 1)), '노동절');
    });

    test('2027 음력 공휴일과 대체공휴일이 표에 들어 있다', () {
      expect(KoreanHolidays.nameOf(DateTime(2027, 2, 7)), '설날');
      expect(KoreanHolidays.nameOf(DateTime(2027, 2, 9)), '대체공휴일(설날)');
      expect(KoreanHolidays.nameOf(DateTime(2027, 5, 13)), '부처님오신날');
      expect(KoreanHolidays.nameOf(DateTime(2027, 9, 15)), '추석');
      expect(KoreanHolidays.nameOf(DateTime(2027, 12, 27)), '대체공휴일(성탄절)');
    });

    test('공휴일 인접 평일은 공휴일이 아니다', () {
      expect(KoreanHolidays.isHoliday(DateTime(2026, 7, 16)), isFalse);
      expect(KoreanHolidays.isHoliday(DateTime(2026, 7, 18)), isFalse);
      expect(KoreanHolidays.isHoliday(DateTime(2026, 12, 24)), isFalse);
      expect(KoreanHolidays.isHoliday(DateTime(2026, 12, 26)), isFalse);
    });

    test('시각이 붙어 있어도 날짜만 본다', () {
      expect(
        KoreanHolidays.isHoliday(DateTime(2026, 12, 25, 13, 30, 45)),
        isTrue,
      );
      expect(
        KoreanHolidays.isHoliday(DateTime(2026, 12, 24, 23, 59, 59)),
        isFalse,
      );
    });

    test('표에 없는 연도는 공휴일을 표시하지 않는다', () {
      // 조용히 틀린 날을 칠하느니 아무것도 안 칠한다 — 일요일 빨간색은 표와 무관하게 계속 동작한다.
      expect(KoreanHolidays.supportedYears, {2026, 2027});
      expect(KoreanHolidays.datesIn(2028), isEmpty);
      expect(KoreanHolidays.isHoliday(DateTime(2028, 1, 1)), isFalse);
      expect(KoreanHolidays.isHoliday(DateTime(2025, 12, 25)), isFalse);
    });

    // 표 전체 스냅샷 — 날짜가 빠지거나 엉뚱한 날이 끼어들면 둘 다 여기서 걸린다.
    // 표를 고칠 땐 반드시 출처를 다시 확인하고 이 목록도 같이 고친다.
    test('2026 표 전체', () {
      expect(KoreanHolidays.datesIn(2026), {
        '01-01', '02-16', '02-17', '02-18', '03-01', '03-02', //
        '05-01', '05-05', '05-24', '05-25', '06-03', '06-06', //
        '07-17', '08-15', '08-17', '09-24', '09-25', '09-26', //
        '10-03', '10-05', '10-09', '12-25',
      });
    });

    test('2027 표 전체', () {
      expect(KoreanHolidays.datesIn(2027), {
        '01-01', '02-06', '02-07', '02-08', '02-09', '03-01', //
        '05-01', '05-03', '05-05', '05-13', '06-06', '07-17', //
        '07-19', '08-15', '08-16', '09-14', '09-15', '09-16', //
        '10-03', '10-04', '10-09', '10-11', '12-25', '12-27',
      });
      // 2027-06-07(현충일 대체)은 출처가 엇갈려 일부러 뺐다 — specs/OPEN.md 참고.
      expect(KoreanHolidays.isHoliday(DateTime(2027, 6, 7)), isFalse);
    });
  });
}
