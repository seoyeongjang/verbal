class CalendarHoliday {
  const CalendarHoliday({
    required this.date,
    required this.title,
    required this.countryCode,
    required this.countryLabel,
  });

  final DateTime date;
  final String title;
  final String countryCode;
  final String countryLabel;
}

enum HolidayCountry {
  none('none', '표시 안 함'),
  korea('KR', '대한민국'),
  unitedStates('US', '미국'),
  japan('JP', '일본'),
  china('CN', '중국');

  const HolidayCountry(this.code, this.label);

  final String code;
  final String label;

  static HolidayCountry fromCode(String? code) {
    final normalized = (code ?? '').trim();
    if (normalized.toLowerCase() == HolidayCountry.none.code) {
      return HolidayCountry.none;
    }
    final upperCode = normalized.toUpperCase();
    return values.firstWhere(
      (country) => country.code == upperCode,
      orElse: () => HolidayCountry.korea,
    );
  }
}

class HolidayCalendar {
  HolidayCalendar._();

  static List<CalendarHoliday> holidaysForRange(
    HolidayCountry country,
    DateTime start,
    DateTime end,
  ) {
    if (country == HolidayCountry.none) {
      return const [];
    }
    final years = <int>{};
    for (var year = start.year; year <= end.year; year++) {
      years.add(year);
    }
    final holidays = <CalendarHoliday>[
      for (final year in years) ..._holidaysForYear(country, year),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return holidays
        .where(
          (holiday) =>
              !holiday.date.isBefore(_dateOnly(start)) &&
              !holiday.date.isAfter(_dateOnly(end)),
        )
        .toList(growable: false);
  }

  static List<CalendarHoliday> holidaysForDay(
    HolidayCountry country,
    DateTime day,
  ) {
    return holidaysForRange(country, day, day);
  }

  static List<CalendarHoliday> _holidaysForYear(
    HolidayCountry country,
    int year,
  ) {
    return switch (country) {
      HolidayCountry.korea => _korea(year),
      HolidayCountry.unitedStates => _unitedStates(year),
      HolidayCountry.japan => _japan(year),
      HolidayCountry.china => _china(year),
      HolidayCountry.none => const [],
    };
  }

  static List<CalendarHoliday> _korea(int year) {
    final holidays = <CalendarHoliday>[
      _holiday(year, 1, 1, '신정', HolidayCountry.korea),
      _holiday(year, 3, 1, '삼일절', HolidayCountry.korea),
      _holiday(year, 5, 1, '근로자의 날', HolidayCountry.korea),
      _holiday(year, 5, 5, '어린이날', HolidayCountry.korea),
      _holiday(year, 6, 6, '현충일', HolidayCountry.korea),
      _holiday(year, 8, 15, '광복절', HolidayCountry.korea),
      _holiday(year, 10, 3, '개천절', HolidayCountry.korea),
      _holiday(year, 10, 9, '한글날', HolidayCountry.korea),
      _holiday(year, 12, 25, '성탄절', HolidayCountry.korea),
      ..._datedTable(year, HolidayCountry.korea, {
        2026: const [
          (2, 16, '설날 연휴'),
          (2, 17, '설날'),
          (2, 18, '설날 연휴'),
          (5, 24, '부처님오신날'),
          (5, 25, '부처님오신날 대체공휴일'),
          (9, 24, '추석 연휴'),
          (9, 25, '추석'),
          (9, 26, '추석 연휴'),
          (9, 28, '추석 대체공휴일'),
        ],
      }),
    ];
    _addKoreanSubstitutes(holidays, year);
    return _dedupe(holidays);
  }

  static List<CalendarHoliday> _unitedStates(int year) {
    return [
      _observedFixed(year, 1, 1, "New Year's Day", HolidayCountry.unitedStates),
      _holidayDate(
        _nthWeekday(year, 1, DateTime.monday, 3),
        'Martin Luther King Jr. Day',
        HolidayCountry.unitedStates,
      ),
      _holidayDate(
        _nthWeekday(year, 2, DateTime.monday, 3),
        "Washington's Birthday",
        HolidayCountry.unitedStates,
      ),
      _holidayDate(
        _lastWeekday(year, 5, DateTime.monday),
        'Memorial Day',
        HolidayCountry.unitedStates,
      ),
      _observedFixed(year, 6, 19, 'Juneteenth', HolidayCountry.unitedStates),
      _observedFixed(
        year,
        7,
        4,
        'Independence Day',
        HolidayCountry.unitedStates,
      ),
      _holidayDate(
        _nthWeekday(year, 9, DateTime.monday, 1),
        'Labor Day',
        HolidayCountry.unitedStates,
      ),
      _holidayDate(
        _nthWeekday(year, 10, DateTime.monday, 2),
        'Columbus Day',
        HolidayCountry.unitedStates,
      ),
      _observedFixed(year, 11, 11, 'Veterans Day', HolidayCountry.unitedStates),
      _holidayDate(
        _nthWeekday(year, 11, DateTime.thursday, 4),
        'Thanksgiving Day',
        HolidayCountry.unitedStates,
      ),
      _observedFixed(
        year,
        12,
        25,
        'Christmas Day',
        HolidayCountry.unitedStates,
      ),
    ];
  }

  static List<CalendarHoliday> _japan(int year) {
    final holidays = <CalendarHoliday>[
      _holiday(year, 1, 1, '元日', HolidayCountry.japan),
      _holidayDate(
        _nthWeekday(year, 1, DateTime.monday, 2),
        '成人の日',
        HolidayCountry.japan,
      ),
      _holiday(year, 2, 11, '建国記念の日', HolidayCountry.japan),
      _holiday(year, 2, 23, '天皇誕生日', HolidayCountry.japan),
      _holiday(year, 3, _vernalEquinoxDay(year), '春分の日', HolidayCountry.japan),
      _holiday(year, 4, 29, '昭和の日', HolidayCountry.japan),
      _holiday(year, 5, 3, '憲法記念日', HolidayCountry.japan),
      _holiday(year, 5, 4, 'みどりの日', HolidayCountry.japan),
      _holiday(year, 5, 5, 'こどもの日', HolidayCountry.japan),
      _holidayDate(
        _nthWeekday(year, 7, DateTime.monday, 3),
        '海の日',
        HolidayCountry.japan,
      ),
      _holiday(year, 8, 11, '山の日', HolidayCountry.japan),
      _holidayDate(
        _nthWeekday(year, 9, DateTime.monday, 3),
        '敬老の日',
        HolidayCountry.japan,
      ),
      _holiday(
        year,
        9,
        _autumnalEquinoxDay(year),
        '秋分の日',
        HolidayCountry.japan,
      ),
      _holidayDate(
        _nthWeekday(year, 10, DateTime.monday, 2),
        'スポーツの日',
        HolidayCountry.japan,
      ),
      _holiday(year, 11, 3, '文化の日', HolidayCountry.japan),
      _holiday(year, 11, 23, '勤労感謝の日', HolidayCountry.japan),
    ];
    _addJapaneseCitizenHolidays(holidays, year);
    _addJapaneseSubstitutes(holidays, year);
    return _dedupe(holidays);
  }

  static List<CalendarHoliday> _china(int year) {
    return _datedTable(
      year,
      HolidayCountry.china,
      {
        2026: const [
          (1, 1, '元旦'),
          (1, 2, '元旦假期'),
          (1, 3, '元旦假期'),
          (2, 15, '春节假期'),
          (2, 16, '春节假期'),
          (2, 17, '春节'),
          (2, 18, '春节假期'),
          (2, 19, '春节假期'),
          (2, 20, '春节假期'),
          (2, 21, '春节假期'),
          (2, 22, '春节假期'),
          (2, 23, '春节假期'),
          (4, 4, '清明节'),
          (4, 5, '清明节假期'),
          (4, 6, '清明节假期'),
          (5, 1, '劳动节'),
          (5, 2, '劳动节假期'),
          (5, 3, '劳动节假期'),
          (5, 4, '劳动节假期'),
          (5, 5, '劳动节假期'),
          (6, 19, '端午节'),
          (6, 20, '端午节假期'),
          (6, 21, '端午节假期'),
          (9, 25, '中秋节'),
          (9, 26, '中秋节假期'),
          (9, 27, '中秋节假期'),
          (10, 1, '国庆节'),
          (10, 2, '国庆节假期'),
          (10, 3, '国庆节假期'),
          (10, 4, '国庆节假期'),
          (10, 5, '国庆节假期'),
          (10, 6, '国庆节假期'),
          (10, 7, '国庆节假期'),
        ],
      },
      fallback: [
        _holiday(year, 1, 1, '元旦', HolidayCountry.china),
        _holiday(year, 5, 1, '劳动节', HolidayCountry.china),
        _holiday(year, 10, 1, '国庆节', HolidayCountry.china),
        _holiday(year, 10, 2, '国庆节假期', HolidayCountry.china),
        _holiday(year, 10, 3, '国庆节假期', HolidayCountry.china),
      ],
    );
  }

  static CalendarHoliday _holiday(
    int year,
    int month,
    int day,
    String title,
    HolidayCountry country,
  ) {
    return _holidayDate(DateTime(year, month, day), title, country);
  }

  static CalendarHoliday _holidayDate(
    DateTime date,
    String title,
    HolidayCountry country,
  ) {
    return CalendarHoliday(
      date: _dateOnly(date),
      title: title,
      countryCode: country.code,
      countryLabel: country.label,
    );
  }

  static CalendarHoliday _observedFixed(
    int year,
    int month,
    int day,
    String title,
    HolidayCountry country,
  ) {
    final actual = DateTime(year, month, day);
    final observed = switch (actual.weekday) {
      DateTime.saturday => actual.subtract(const Duration(days: 1)),
      DateTime.sunday => actual.add(const Duration(days: 1)),
      _ => actual,
    };
    return _holidayDate(observed, title, country);
  }

  static List<CalendarHoliday> _datedTable(
    int year,
    HolidayCountry country,
    Map<int, List<(int, int, String)>> table, {
    List<CalendarHoliday> fallback = const [],
  }) {
    final items = table[year];
    if (items == null) {
      return fallback;
    }
    return [
      for (final item in items)
        _holiday(year, item.$1, item.$2, item.$3, country),
    ];
  }

  static void _addKoreanSubstitutes(List<CalendarHoliday> holidays, int year) {
    final eligible = holidays
        .where((holiday) {
          return holiday.date.year == year &&
              holiday.date.weekday == DateTime.sunday &&
              (holiday.title == '삼일절' ||
                  holiday.title == '어린이날' ||
                  holiday.title == '광복절' ||
                  holiday.title == '개천절' ||
                  holiday.title == '한글날' ||
                  holiday.title == '성탄절');
        })
        .toList(growable: false);
    final occupied = holidays.map((holiday) => holiday.date).toSet();
    for (final holiday in eligible) {
      var substitute = holiday.date.add(const Duration(days: 1));
      while (occupied.contains(substitute)) {
        substitute = substitute.add(const Duration(days: 1));
      }
      occupied.add(substitute);
      holidays.add(
        _holidayDate(
          substitute,
          '${holiday.title} 대체공휴일',
          HolidayCountry.korea,
        ),
      );
    }
  }

  static void _addJapaneseCitizenHolidays(
    List<CalendarHoliday> holidays,
    int year,
  ) {
    final dates = holidays.map((holiday) => holiday.date).toSet();
    for (
      var date = DateTime(year, 1, 2);
      date.year == year;
      date = date.add(const Duration(days: 1))
    ) {
      if (dates.contains(date)) {
        continue;
      }
      final previous = date.subtract(const Duration(days: 1));
      final next = date.add(const Duration(days: 1));
      if (dates.contains(previous) && dates.contains(next)) {
        holidays.add(_holidayDate(date, '国民の休日', HolidayCountry.japan));
        dates.add(date);
      }
    }
  }

  static void _addJapaneseSubstitutes(
    List<CalendarHoliday> holidays,
    int year,
  ) {
    final dates = holidays.map((holiday) => holiday.date).toSet();
    final sundayHolidays = holidays
        .where(
          (holiday) =>
              holiday.date.year == year &&
              holiday.date.weekday == DateTime.sunday,
        )
        .toList(growable: false);
    for (final holiday in sundayHolidays) {
      var substitute = holiday.date.add(const Duration(days: 1));
      while (dates.contains(substitute)) {
        substitute = substitute.add(const Duration(days: 1));
      }
      dates.add(substitute);
      holidays.add(_holidayDate(substitute, '振替休日', HolidayCountry.japan));
    }
  }

  static List<CalendarHoliday> _dedupe(List<CalendarHoliday> holidays) {
    final seen = <String>{};
    final deduped = <CalendarHoliday>[];
    for (final holiday in holidays..sort((a, b) => a.date.compareTo(b.date))) {
      final key =
          '${holiday.countryCode}:${holiday.date.toIso8601String()}:${holiday.title}';
      if (seen.add(key)) {
        deduped.add(holiday);
      }
    }
    return deduped;
  }

  static DateTime _nthWeekday(int year, int month, int weekday, int nth) {
    var date = DateTime(year, month);
    while (date.weekday != weekday) {
      date = date.add(const Duration(days: 1));
    }
    return date.add(Duration(days: 7 * (nth - 1)));
  }

  static DateTime _lastWeekday(int year, int month, int weekday) {
    var date = DateTime(year, month + 1, 0);
    while (date.weekday != weekday) {
      date = date.subtract(const Duration(days: 1));
    }
    return date;
  }

  static int _vernalEquinoxDay(int year) {
    if (year == 2026) {
      return 20;
    }
    return (20.8431 + 0.242194 * (year - 1980) - ((year - 1980) ~/ 4)).floor();
  }

  static int _autumnalEquinoxDay(int year) {
    if (year == 2026) {
      return 23;
    }
    return (23.2488 + 0.242194 * (year - 1980) - ((year - 1980) ~/ 4)).floor();
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
