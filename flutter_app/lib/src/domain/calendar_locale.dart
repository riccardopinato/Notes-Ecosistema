class CalendarLocaleConfig {
  const CalendarLocaleConfig({
    required this.locale,
    required this.firstWeekday,
    required this.weekdayNarrow,
  });

  final String locale;
  final int firstWeekday;
  final List<String> weekdayNarrow;

  DateTime startOfWeek(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final delta = (day.weekday - firstWeekday + 7) % 7;
    return day.subtract(Duration(days: delta));
  }

  List<DateTime> weekDays(DateTime date) {
    final start = startOfWeek(date);
    return List<DateTime>.generate(
      7,
      (index) => start.add(Duration(days: index)),
      growable: false,
    );
  }

  List<DateTime> monthGrid(DateTime month) {
    final first = DateTime(month.year, month.month);
    final start = startOfWeek(first);
    return List<DateTime>.generate(
      42,
      (index) => start.add(Duration(days: index)),
      growable: false,
    );
  }

  static const italian = CalendarLocaleConfig(
    locale: 'it_IT',
    firstWeekday: DateTime.monday,
    weekdayNarrow: ['L', 'M', 'M', 'G', 'V', 'S', 'D'],
  );
}

const appCalendar = CalendarLocaleConfig.italian;
