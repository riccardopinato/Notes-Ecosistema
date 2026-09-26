import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/calendar_locale.dart';

void main() {
  test('default calendar is Italian and Monday-first', () {
    expect(appCalendar.locale, 'it_IT');
    expect(appCalendar.firstWeekday, DateTime.monday);
    expect(appCalendar.weekdayNarrow, ['L', 'M', 'M', 'G', 'V', 'S', 'D']);
  });

  test('weekDays starts on Monday and ends on Sunday', () {
    final days = appCalendar.weekDays(DateTime(2026, 9, 27));

    expect(days, hasLength(7));
    expect(days.first, DateTime(2026, 9, 21));
    expect(days.first.weekday, DateTime.monday);
    expect(days.last, DateTime(2026, 9, 27));
    expect(days.last.weekday, DateTime.sunday);
  });

  test('monthGrid preserves Monday-first convention', () {
    final days = appCalendar.monthGrid(DateTime(2026, 9, 15));

    expect(days, hasLength(42));
    expect(days.first, DateTime(2026, 8, 31));
    expect(days.first.weekday, DateTime.monday);
    expect(days.last, DateTime(2026, 10, 11));
    expect(days.last.weekday, DateTime.sunday);
  });

  test('calendar convention is reusable for another first weekday', () {
    const sundayFirst = CalendarLocaleConfig(
      locale: 'en_US',
      firstWeekday: DateTime.sunday,
      weekdayNarrow: ['S', 'M', 'T', 'W', 'T', 'F', 'S'],
    );

    final days = sundayFirst.weekDays(DateTime(2026, 9, 27));
    expect(days.first, DateTime(2026, 9, 27));
    expect(days.first.weekday, DateTime.sunday);
  });
}
