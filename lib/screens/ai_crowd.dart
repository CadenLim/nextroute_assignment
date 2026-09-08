import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

enum _RankingPeriod { overall, month, day }

enum _Tab5View { ranking, compare }

typedef _StationRidershipRow = ({
String station,
double avgRidership,
int totalRidership,
int recordCount,
DateTime? minDate,
DateTime? maxDate,
});

typedef _WeekdayWeekendStats = ({
double? weekdayAvg,
double? weekendAvg,
int weekdayCount,
int weekendCount,
});

typedef _HeatmapDayCell = ({int day, DateTime date, double? ridership});

typedef _HeatmapSelection = ({DateTime date, double? ridership});

class _MonthlyLineChartPainter extends CustomPainter {
  final List<double> values;
  final int highestIndex;
  final int lowestIndex;

  _MonthlyLineChartPainter({
    required this.values,
    required this.highestIndex,
    required this.lowestIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n = values.length;
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);
    const topPad = 10.0;
    const bottomPad = 10.0;
    final chartHeight = size.height - topPad - bottomPad;
    final slotWidth = size.width / n;

    Offset pointAt(int i) {
      final x = slotWidth * i + slotWidth / 2;
      final normalized = (values[i] - minVal) / range;
      final y = topPad + chartHeight - (normalized * chartHeight);
      return Offset(x, y);
    }

    final path = Path();
    for (int i = 0; i < n; i++) {
      final p = pointAt(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    if (n > 1) {
      final linePaint = Paint()
        ..color = Colors.blueGrey.withValues(alpha: 0.65)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, linePaint);

      final fillPath = Path.from(path)
        ..lineTo(pointAt(n - 1).dx, size.height)
        ..lineTo(pointAt(0).dx, size.height)
        ..close();
      canvas.drawPath(fillPath, Paint()..color = const Color(0xFF4F46E5).withValues(alpha: 0.06));
    }

    for (int i = 0; i < n; i++) {
      final p = pointAt(i);
      final isHighest = i == highestIndex;
      final isLowest = i == lowestIndex && lowestIndex != highestIndex;

      final t = maxVal == minVal ? 1.0 : ((values[i] - minVal) / range).clamp(0.0, 1.0);
      final color = Color.lerp(const Color(0xFF16A34A), const Color(0xFFDC2626), t)!;
      if (isHighest || isLowest) {
        canvas.drawCircle(p, 7, Paint()..color = color.withValues(alpha: 0.15));
      }
      canvas.drawCircle(p, isHighest || isLowest ? 4.5 : 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyLineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.highestIndex != highestIndex ||
        oldDelegate.lowestIndex != lowestIndex;
  }
}

class _FullDayCrowdLineChartPainter extends CustomPainter {
  final List<int> occupancies;
  final List<Color> pointColors;
  final int peakIndex;

  _FullDayCrowdLineChartPainter({
    required this.occupancies,
    required this.pointColors,
    required this.peakIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (occupancies.isEmpty) return;
    final n = occupancies.length;
    const topPad = 10.0;
    const bottomPad = 10.0;
    final chartHeight = size.height - topPad - bottomPad;
    final slotWidth = size.width / n;

    Offset pointAt(int i) {
      final x = slotWidth * i + slotWidth / 2;
      final normalized = (occupancies[i] / 100.0).clamp(0.0, 1.0);
      final y = topPad + chartHeight - (normalized * chartHeight);
      return Offset(x, y);
    }

    final path = Path();
    for (int i = 0; i < n; i++) {
      final p = pointAt(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    if (n > 1) {
      final linePaint = Paint()
        ..color = const Color(0xFF4F46E5).withValues(alpha: 0.55)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, linePaint);

      final fillPath = Path.from(path)
        ..lineTo(pointAt(n - 1).dx, size.height)
        ..lineTo(pointAt(0).dx, size.height)
        ..close();
      canvas.drawPath(fillPath, Paint()..color = const Color(0xFF4F46E5).withValues(alpha: 0.06));
    }

    for (int i = 0; i < n; i++) {
      final p = pointAt(i);
      final isPeak = i == peakIndex;
      final color = pointColors[i];
      if (isPeak) {
        canvas.drawCircle(p, 7, Paint()..color = color.withValues(alpha: 0.18));
      }
      canvas.drawCircle(p, isPeak ? 4.5 : 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _FullDayCrowdLineChartPainter oldDelegate) {
    return oldDelegate.occupancies != occupancies ||
        oldDelegate.pointColors != pointColors ||
        oldDelegate.peakIndex != peakIndex;
  }
}

class StationSearchField extends StatelessWidget {
  final String label;
  final List<String> stations;
  final String? value;
  final ValueChanged<String?> onChanged;

  const StationSearchField({
    super.key,
    required this.label,
    required this.stations,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {

    return Autocomplete<String>(
      key: ValueKey(value),
      initialValue: TextEditingValue(text: value ?? ''),
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return stations;
        return stations.where((s) => s.toLowerCase().contains(query));
      },
      displayStringForOption: (s) => s,
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: const Icon(Icons.search, size: 20),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, minWidth: 280),
              child: list.isEmpty
                  ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No matching stations', style: TextStyle(color: Colors.black45)),
              )
                  : ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final option = list[index];
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

enum CrowdLevel { low, moderate, high, critical }

extension CrowdLevelX on CrowdLevel {
  String get label {
    switch (this) {
      case CrowdLevel.low:
        return 'LOW';
      case CrowdLevel.moderate:
        return 'MODERATE';
      case CrowdLevel.high:
        return 'HIGH';
      case CrowdLevel.critical:
        return 'CRITICAL';
    }
  }

  Color get color {
    switch (this) {
      case CrowdLevel.low:
        return const Color(0xFF16A34A);
      case CrowdLevel.moderate:
        return const Color(0xFFD97706);
      case CrowdLevel.high:
        return const Color(0xFFDC2626);
      case CrowdLevel.critical:
        return const Color(0xFF991B1B);
    }
  }

  String get queueEstimate {
    switch (this) {
      case CrowdLevel.low:
        return '2 min';
      case CrowdLevel.moderate:
        return '5 min';
      case CrowdLevel.high:
        return '10 min';
      case CrowdLevel.critical:
        return '15+ min';
    }
  }
}

class CrowdResult {
  final CrowdLevel level;
  final int occupancy;
  CrowdResult(this.level, this.occupancy);
}

enum TimeCategory { earlyMorning, morningPeak, midday, eveningPeak, night }

extension TimeCategoryX on TimeCategory {
  String get label {
    switch (this) {
      case TimeCategory.earlyMorning:
        return 'Early Morning';
      case TimeCategory.morningPeak:
        return 'Morning Peak';
      case TimeCategory.midday:
        return 'Midday';
      case TimeCategory.eveningPeak:
        return 'Evening Peak';
      case TimeCategory.night:
        return 'Night';
    }
  }

  String get rangeLabel {
    switch (this) {
      case TimeCategory.earlyMorning:
        return '06:00–07:00';
      case TimeCategory.morningPeak:
        return '07:00–09:00';
      case TimeCategory.midday:
        return '09:00–17:00';
      case TimeCategory.eveningPeak:
        return '17:00–19:30';
      case TimeCategory.night:
        return '19:30–06:00';
    }
  }

  Color get color {
    switch (this) {
      case TimeCategory.earlyMorning:
        return const Color(0xFF0EA5E9);
      case TimeCategory.morningPeak:
        return const Color(0xFFDC2626);
      case TimeCategory.midday:
        return const Color(0xFFD97706);
      case TimeCategory.eveningPeak:
        return const Color(0xFF991B1B);
      case TimeCategory.night:
        return const Color(0xFF4338CA);
    }
  }
}

TimeCategory timeCategoryFor(int minutesOfDay) {
  final h = minutesOfDay / 60.0;
  if (h >= 6.0 && h < 7.0) return TimeCategory.earlyMorning;
  if (h >= 7.0 && h < 9.0) return TimeCategory.morningPeak;
  if (h >= 9.0 && h < 17.0) return TimeCategory.midday;
  if (h >= 17.0 && h < 19.5) return TimeCategory.eveningPeak;
  return TimeCategory.night;
}

const List<String> kWeekdayLabels = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

int _baselineOccupancy(int weekday, int minutesOfDay) {
  final isWeekend =
      weekday == DateTime.saturday || weekday == DateTime.sunday;
  final h = minutesOfDay / 60.0;

  if (isWeekend) {
    if (h < 9.0) return 15;
    if (h < 12.0) return 25;
    if (h < 15.0) return 32;
    if (h < 18.0) return 38;
    if (h < 20.0) return 35;
    if (h < 22.0) return 25;
    return 15;
  }

  if (h < 7.0) return 15;
  if (h < 7.5) return 35;
  if (h < 8.0) return 55;
  if (h < 8.5) return 70;
  if (h < 9.0) return 65;

  if (h < 12.0) return 45;
  if (h < 15.0) return 42;
  if (h < 17.0) return 45;

  if (h < 17.5) return 55;
  if (h < 18.0) return 65;
  if (h < 19.0) return 75;

  if (h < 21.0) return 45;
  if (h < 22.0) return 30;
  return 15;
}

CrowdLevel _levelForOccupancy(int occupancy) {
  if (occupancy >= 80) return CrowdLevel.critical;
  if (occupancy >= 55) return CrowdLevel.high;
  if (occupancy >= 28) return CrowdLevel.moderate;
  return CrowdLevel.low;
}

CrowdResult predictCrowd(int weekday, int minutesOfDay, double magnitudeFactor) {
  final baseline = _baselineOccupancy(weekday, minutesOfDay);
  final occupancy = (baseline * magnitudeFactor).round().clamp(4, 99);
  return CrowdResult(_levelForOccupancy(occupancy), occupancy);
}

String getAiInsight(String station, CrowdLevel level, TimeOfDay time, int weekday) {
  final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;
  final t = time.format24Hour();
  final dayContext = isWeekend ? 'weekend' : 'weekday';
  switch (level) {
    case CrowdLevel.critical:
      return 'Very high crowd levels are expected at $station around $t on this $dayContext. Significant crowding is likely, so plan for extra time and possible waits to board.';
    case CrowdLevel.high:
      return 'Higher crowd levels are expected at $station around $t on this $dayContext. Noticeable crowding is likely on platforms, so boarding may require waiting for the next train.';
    case CrowdLevel.moderate:
      return 'Moderate crowd levels are expected at $station around $t on this $dayContext. Some crowding may occur, but conditions should remain manageable.';
    case CrowdLevel.low:
      return 'Crowd levels are expected to be low at $station around $t on this $dayContext. Comfortable boarding and ample seating should be available.';
  }
}

extension on TimeOfDay {
  String format24Hour() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class AiCrowdScreen extends StatefulWidget {
  const AiCrowdScreen({super.key});

  @override
  State<AiCrowdScreen> createState() => _AiCrowdScreenState();
}

class _AiCrowdScreenState extends State<AiCrowdScreen> {
  final ApiService _api = ApiService();

  List<String> _stations = [];
  Set<String> _stationsWithOdData = {};
  bool _statsReady = false;
  double _networkAverage = 1;
  String? _loadError;

  String? _station;
  int? _weekday;
  TimeOfDay? _time;
  CrowdResult? _crowdResult;
  double? _crowdResultDayAvg;
  double? _crowdResultFactor;
  int? _crowdResultRecordCount;
  String? _crowdValidationMsg;

  String? _peakStation;
  int? _peakWeekday;
  List<MapEntry<int, CrowdResult>>? _peakSlots;
  double? _peakDayAvg;
  double? _peakFactor;
  String? _peakValidationMsg;
  int? _fullDayHoverIndex;

  String? _historyStation;
  List<RidershipRecord>? _historyData;
  DateTime? _historyMonthFilter;
  String? _historyValidationMsg;

  int? _heatmapAllMonthsIndex;
  _HeatmapSelection? _heatmapSelectedDay;

  String? _connStation;
  List<MapEntry<String, int>>? _connTopDestinations;
  List<MapEntry<String, int>>? _connTopOrigins;
  int? _connOutgoing;
  int? _connIncoming;
  List<MapEntry<String, int>>? _connBusiestNetwork;
  bool _loadingConnections = false;

  int _connLoadingSeconds = 0;
  Timer? _connLoadingTimer;
  String? _connValidationMsg;

  bool _loadingRanking = false;
  String? _rankingError;
  List<({String station, double avgRidership, int totalRidership, int recordCount, DateTime? minDate, DateTime? maxDate})>?
  _rankingData;
  _RankingPeriod _rankingPeriod = _RankingPeriod.overall;
  DateTime? _rankingMonth;
  DateTime? _rankingDay;

  DateTime? _rankingDatasetMinDate;
  DateTime? _rankingDatasetMaxDate;

  _Tab5View _tab5View = _Tab5View.ranking;

  String? _compareStationA;
  String? _compareStationB;
  _RankingPeriod _comparePeriod = _RankingPeriod.overall;
  DateTime? _compareMonth;
  DateTime? _compareDay;
  bool _loadingCompare = false;
  String? _compareError;
  _StationRidershipRow? _compareDataA;
  _StationRidershipRow? _compareDataB;

  static const double _sectionGap = 20.0;
  static const double _sectionCardPadding = 16.0;
  static const double _sectionCardRadius = 12.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _connLoadingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({int attempt = 0}) async {
    try {
      final stations = await _api.getStationList();
      final odStations = await _api.getStationsWithOutgoingData();
      final networkAvg = await _api.getNetworkAverageRidership();
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _stationsWithOdData = odStations.toSet();
        _networkAverage = networkAvg;

        _statsReady = stations.isNotEmpty;
        if (stations.isEmpty) _loadError = 'No station records found in the local dataset.';
      });

      if (stations.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _runStationRanking();
        });
      }
    } catch (e) {
      if (!mounted) return;

      final isTimeout = e.toString().contains('57014') || e.toString().contains('statement timeout');
      if (isTimeout && attempt < 2) {
        await Future.delayed(Duration(milliseconds: 1000 * (attempt + 1)));
        if (!mounted) return;
        return _loadData(attempt: attempt + 1);
      }

      setState(() => _loadError = 'Could not load ridership data from Supabase:\n$e');
    }
  }

  double _magnitudeFactor(double dayAvg) {
    final ratio = dayAvg / _networkAverage;
    return ratio.clamp(0.4, 1.8);
  }

  (String, Color, IconData) _demandInterpretation(double factor) {
    if (factor > 1.05) {
      return ('Above Network Average', Colors.red.shade700, Icons.trending_up);
    } else if (factor < 0.95) {
      return ('Below Network Average', Colors.green.shade700, Icons.trending_down);
    }
    return ('Around Network Average', Colors.blueGrey, Icons.trending_flat);
  }

  ({double currentAvg, double previousAvg, double percentChange})? _computeRidershipTrend(
      List<RidershipRecord> records) {
    if (records.length < 2) return null;
    final mid = records.length ~/ 2;
    final previousPeriod = records.sublist(0, mid);
    final currentPeriod = records.sublist(mid);
    if (previousPeriod.isEmpty || currentPeriod.isEmpty) return null;
    final previousAvg =
        previousPeriod.map((e) => e.ridership).reduce((a, b) => a + b) / previousPeriod.length;
    final currentAvg =
        currentPeriod.map((e) => e.ridership).reduce((a, b) => a + b) / currentPeriod.length;
    final percentChange = previousAvg == 0 ? 0.0 : ((currentAvg - previousAvg) / previousAvg) * 100;
    return (currentAvg: currentAvg, previousAvg: previousAvg, percentChange: percentChange);
  }

  (String, Color, IconData) _ridershipInsight(
      ({double currentAvg, double previousAvg, double percentChange}) trend) {
    final pct = trend.percentChange;
    if (pct > 5) {
      return (
      'Ridership has increased by ${pct.toStringAsFixed(1)}% versus the previous period, based on the real records shown above.',
      Colors.red.shade700,
      Icons.trending_up,
      );
    } else if (pct < -5) {
      return (
      'Ridership has decreased by ${pct.abs().toStringAsFixed(1)}% versus the previous period, based on the real records shown above.',
      Colors.green.shade700,
      Icons.trending_down,
      );
    }
    return (
    'Ridership has stayed roughly stable (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%) versus the previous period, based on the real records shown above.',
    Colors.blueGrey,
    Icons.trending_flat,
    );
  }

  List<({int weekday, double avg, int count})> _computeWeeklyPattern(
      List<RidershipRecord> records) {
    final Map<int, List<num>> byWeekday = {};
    for (final r in records) {
      byWeekday.putIfAbsent(r.date.weekday, () => []).add(r.ridership);
    }
    final result = byWeekday.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return (weekday: e.key, avg: avg, count: e.value.length);
    }).toList()
      ..sort((a, b) => a.weekday.compareTo(b.weekday));
    return result;
  }

  _WeekdayWeekendStats _computeWeekdayWeekendComparison(
      List<RidershipRecord> records) {
    final weekdayValues = <num>[];
    final weekendValues = <num>[];
    for (final r in records) {
      final isWeekend =
          r.date.weekday == DateTime.saturday || r.date.weekday == DateTime.sunday;
      (isWeekend ? weekendValues : weekdayValues).add(r.ridership);
    }
    return (
    weekdayAvg: weekdayValues.isEmpty
        ? null
        : weekdayValues.reduce((a, b) => a + b) / weekdayValues.length,
    weekendAvg: weekendValues.isEmpty
        ? null
        : weekendValues.reduce((a, b) => a + b) / weekendValues.length,
    weekdayCount: weekdayValues.length,
    weekendCount: weekendValues.length,
    );
  }

  List<({DateTime month, double avg, int count})> _computeMonthlyTrend(
      List<RidershipRecord> records) {
    final Map<DateTime, List<num>> byMonth = {};
    for (final r in records) {
      final key = DateTime(r.date.year, r.date.month);
      byMonth.putIfAbsent(key, () => []).add(r.ridership);
    }
    final result = byMonth.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return (month: e.key, avg: avg, count: e.value.length);
    }).toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return result;
  }

  (String, Color, IconData) _weeklyPatternInsight(
      List<({int weekday, double avg, int count})> pattern) {
    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    if (pattern.isEmpty) {
      return ('No records available to compute a weekly pattern.', Colors.blueGrey, Icons.info_outline);
    }
    final sorted = [...pattern]..sort((a, b) => b.avg.compareTo(a.avg));
    final highest = sorted.first;
    final lowest = sorted.last;
    if (highest.weekday == lowest.weekday) {
      return (
      '${dayNames[highest.weekday - 1]} is the only day with data for the selected month.',
      Colors.blueGrey,
      Icons.info_outline,
      );
    }
    return (
    '${dayNames[highest.weekday - 1]} has the highest average ridership (${highest.avg.round()} trips/day). '
        '${dayNames[lowest.weekday - 1]} has the lowest (${lowest.avg.round()} trips/day).',
    Colors.indigo,
    Icons.calendar_view_week,
    );
  }

  bool get _isOutsideOperatingHours => _time != null && _time!.hour < 6;

  Future<void> _runCrowdEstimate() async {
    final station = _station;
    final weekday = _weekday;
    final time = _time;

    final missing = <String>[
      if (station == null) 'a station',
      if (weekday == null) 'a day',
      if (time == null) 'a time',
    ];
    if (missing.isNotEmpty) {
      setState(() {
        _crowdValidationMsg = 'Please select ${_joinMissing(missing)} to see the crowd estimate.';
        _crowdResult = null;
      });
      return;
    }
    if (_isOutsideOperatingHours) {
      setState(() => _crowdValidationMsg = null);
      return;
    }
    final dayAvg = await _api.getStationAverageForWeekday(station!, weekday!);

    final dailyTotals = await _api.getDailyTotalsForStation(station);
    if (!mounted) return;
    final recordCount = dailyTotals.where((e) => e.key.weekday == weekday).length;
    final minutes = time!.hour * 60 + time.minute;
    final factor = _magnitudeFactor(dayAvg);
    setState(() {
      _crowdValidationMsg = null;
      _crowdResult = predictCrowd(weekday, minutes, factor);
      _crowdResultDayAvg = dayAvg;
      _crowdResultFactor = factor;
      _crowdResultRecordCount = recordCount;
    });
  }

  String _joinMissing(List<String> missing) {
    if (missing.length == 1) return missing.first;
    if (missing.length == 2) return '${missing[0]} and ${missing[1]}';
    return '${missing.sublist(0, missing.length - 1).join(', ')}, and ${missing.last}';
  }

  Future<void> _runPeakHours() async {
    final station = _peakStation;
    final weekday = _peakWeekday;
    final missing = <String>[
      if (station == null) 'a station',
      if (weekday == null) 'a day',
    ];
    if (missing.isNotEmpty) {
      setState(() {
        _peakValidationMsg = 'Please select ${_joinMissing(missing)} to see the peak pattern.';
        _peakSlots = null;
      });
      return;
    }
    final dayAvg = await _api.getStationAverageForWeekday(station!, weekday!);
    if (!mounted) return;

    final hours = List.generate(19, (i) => 6 + i);
    final factor = _magnitudeFactor(dayAvg);
    final slots = hours
        .map((h) => MapEntry(h, predictCrowd(weekday, h * 60, factor)))
        .toList();
    setState(() {
      _peakValidationMsg = null;
      _peakSlots = slots;
      _peakDayAvg = dayAvg;
      _peakFactor = factor;
    });
  }

  Future<void> _runHistory() async {
    final station = _historyStation;
    if (station == null) {
      setState(() => _historyValidationMsg = 'Please select a station to load ridership history.');
      return;
    }
    final data = await _api.getStationTotalRecords(station);
    if (!mounted) return;
    setState(() {
      _historyValidationMsg = null;
      _historyData = data;
      _historyMonthFilter = null;
      _heatmapSelectedDay = null;
      _heatmapAllMonthsIndex = null;
    });
  }

  Future<void> _runConnections() async {
    final station = _connStation;
    if (station == null) {
      setState(() => _connValidationMsg = 'Please select a station to show its connections.');
      return;
    }
    setState(() {
      _connValidationMsg = null;
      _loadingConnections = true;
      _connLoadingSeconds = 0;
    });

    _connLoadingTimer?.cancel();
    _connLoadingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _connLoadingSeconds++);
    });
    try {
      final topDest = await _api.getTopDestinationsFrom(station, limit: 5);
      final topOrig = await _api.getTopOriginsInto(station, limit: 5);
      final outgoing = await _api.getTotalOutgoing(station);
      final incoming = await _api.getTotalIncoming(station);
      final busiest = await _api.getBusiestConnections(limit: 10);
      if (!mounted) return;
      setState(() {
        _connTopDestinations = topDest;
        _connTopOrigins = topOrig;
        _connOutgoing = outgoing;
        _connIncoming = incoming;
        _connBusiestNetwork = busiest;
        _loadingConnections = false;
      });
    } finally {
      _connLoadingTimer?.cancel();
      _connLoadingTimer = null;
    }
  }

  Future<void> _runStationRanking({bool forceRefresh = false}) async {
    if (_loadingRanking) return;

    DateTime? startDate;
    DateTime? endDate;
    switch (_rankingPeriod) {
      case _RankingPeriod.overall:
        break;
      case _RankingPeriod.month:
        if (_rankingMonth == null) return;
        startDate = DateTime(_rankingMonth!.year, _rankingMonth!.month, 1);
        endDate = DateTime(_rankingMonth!.year, _rankingMonth!.month + 1, 0);
        break;
      case _RankingPeriod.day:
        if (_rankingDay == null) return;
        startDate = _rankingDay;
        endDate = _rankingDay;
        break;
    }

    setState(() {
      _loadingRanking = true;
      _rankingError = null;
    });
    try {
      final results = await _api.getStationRidershipTotals(
        startDate: startDate,
        endDate: endDate,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;

      if (startDate == null && endDate == null) {
        _captureRankingDatasetBounds(results);
      }
      setState(() {
        _rankingData = results.where((r) => r.recordCount > 0).toList();
        _loadingRanking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rankingError = 'Could not load the station ranking right now:\n$e';
        _loadingRanking = false;
      });
    }
  }

  void _captureRankingDatasetBounds(
      List<({String station, double avgRidership, int totalRidership, int recordCount, DateTime? minDate, DateTime? maxDate})>
      results) {
    if (_rankingDatasetMinDate != null && _rankingDatasetMaxDate != null) return;
    DateTime? minDate;
    DateTime? maxDate;
    for (final r in results) {
      if (r.minDate != null && (minDate == null || r.minDate!.isBefore(minDate))) minDate = r.minDate;
      if (r.maxDate != null && (maxDate == null || r.maxDate!.isAfter(maxDate))) maxDate = r.maxDate;
    }
    _rankingDatasetMinDate = minDate;
    _rankingDatasetMaxDate = maxDate;
  }

  List<DateTime> _rankingAvailableMonths() {
    final min = _rankingDatasetMinDate;
    final max = _rankingDatasetMaxDate;
    if (min == null || max == null) return [];
    final months = <DateTime>[];
    var cursor = DateTime(min.year, min.month);
    final end = DateTime(max.year, max.month);
    while (!cursor.isAfter(end)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return months;
  }

  void _onRankingPeriodChanged(_RankingPeriod period) {
    setState(() {
      _rankingPeriod = period;

      final needsSelection = (period == _RankingPeriod.month && _rankingMonth == null) ||
          (period == _RankingPeriod.day && _rankingDay == null);
      if (needsSelection) {
        _rankingData = null;
        _rankingError = null;
      }
    });

    if (period == _RankingPeriod.overall ||
        (period == _RankingPeriod.month && _rankingMonth != null) ||
        (period == _RankingPeriod.day && _rankingDay != null)) {
      _runStationRanking();
    }
  }

  void _onRankingMonthChanged(DateTime? month) {
    setState(() => _rankingMonth = month);
    if (month != null) _runStationRanking();
  }

  Future<void> _pickRankingDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _rankingDay ?? _rankingDatasetMaxDate ?? now,
      firstDate: _rankingDatasetMinDate ?? DateTime(2020),
      lastDate: _rankingDatasetMaxDate ?? now,
    );
    if (picked != null) {
      setState(() => _rankingDay = picked);
      _runStationRanking();
    }
  }

  Future<void> _runCompare() async {
    final stationA = _compareStationA;
    final stationB = _compareStationB;
    if (stationA == null || stationB == null) return;

    DateTime? startDate;
    DateTime? endDate;
    switch (_comparePeriod) {
      case _RankingPeriod.overall:
        break;
      case _RankingPeriod.month:
        if (_compareMonth == null) return;
        startDate = DateTime(_compareMonth!.year, _compareMonth!.month, 1);
        endDate = DateTime(_compareMonth!.year, _compareMonth!.month + 1, 0);
        break;
      case _RankingPeriod.day:
        if (_compareDay == null) return;
        startDate = _compareDay;
        endDate = _compareDay;
        break;
    }

    setState(() {
      _loadingCompare = true;
      _compareError = null;
    });
    try {
      final results = await _api.getStationRidershipTotals(startDate: startDate, endDate: endDate);
      if (!mounted) return;
      setState(() {
        _compareDataA = _findStationRow(results, stationA);
        _compareDataB = _findStationRow(results, stationB);
        _loadingCompare = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _compareError = 'Could not load the comparison right now:\n$e';
        _loadingCompare = false;
      });
    }
  }

  _StationRidershipRow? _findStationRow(List<_StationRidershipRow> rows, String station) {
    for (final r in rows) {
      if (r.station == station) return r;
    }
    return null;
  }

  void _onComparePeriodChanged(_RankingPeriod period) {
    setState(() {
      _comparePeriod = period;

      final needsSelection = (period == _RankingPeriod.month && _compareMonth == null) ||
          (period == _RankingPeriod.day && _compareDay == null);
      if (needsSelection) {
        _compareDataA = null;
        _compareDataB = null;
        _compareError = null;
      }
    });
    if (period == _RankingPeriod.overall ||
        (period == _RankingPeriod.month && _compareMonth != null) ||
        (period == _RankingPeriod.day && _compareDay != null)) {
      _runCompare();
    }
  }

  void _onCompareMonthChanged(DateTime? month) {
    setState(() => _compareMonth = month);
    if (month != null) _runCompare();
  }

  Future<void> _pickCompareDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _compareDay ?? _rankingDatasetMaxDate ?? now,
      firstDate: _rankingDatasetMinDate ?? DateTime(2020),
      lastDate: _rankingDatasetMaxDate ?? now,
    );
    if (picked != null) {
      setState(() => _compareDay = picked);
      _runCompare();
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: _time ?? const TimeOfDay(hour: 7, minute: 30));
    if (picked != null) {
      setState(() {
        _time = picked;
        _crowdResult = null;
        _crowdValidationMsg = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI Crowd Intelligence')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _loadError = null);
                    _loadData();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_statsReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          titleSpacing: 20,
          title: const Text('AI Crowd & Ridership Insights',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19, height: 1.2)),
          backgroundColor: const Color(0xFF1E3A8A),
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const TabBar(
                  isScrollable: false,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: EdgeInsets.all(4),
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  labelColor: Color(0xFF1E3A8A),
                  unselectedLabelColor: Colors.white,
                  labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: TextStyle(fontSize: 10),
                  tabs: [
                    Tab(text: 'Crowd', icon: Icon(Icons.bar_chart, size: 15)),
                    Tab(text: 'Peak', icon: Icon(Icons.schedule, size: 15)),
                    Tab(text: 'Connections', icon: Icon(Icons.alt_route, size: 15)),
                    Tab(text: 'History', icon: Icon(Icons.show_chart, size: 15)),
                    Tab(text: 'Ranking', icon: Icon(Icons.leaderboard, size: 15)),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  _buildCrowdEstimateTab(),
                  _buildPeakHoursTab(),
                  _buildConnectionsTab(),
                  _buildHistoryTab(),
                  _buildTab5(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(String title, {IconData? icon, String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: Colors.black54),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87, letterSpacing: 0.4),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
        ],
      ],
    );
  }

  Widget _sectionCard({required String title, IconData? icon, String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_sectionCardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(_sectionCardRadius),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(title, icon: icon, subtitle: subtitle),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _emptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.black38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54, fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  Widget _validationMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 12.5, color: Colors.deepOrange, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildCrowdEstimateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Station Crowd Estimate',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Estimated crowd level based on historical ridership patterns.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: _sectionGap),

          _sectionCard(
            title: 'STATION & PREDICTION INPUTS',
            icon: Icons.tune,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StationSearchField(
                  label: 'Station',
                  stations: _stations,
                  value: _station,
                  onChanged: (val) => setState(() { _station = val; _crowdResult = null; _crowdValidationMsg = null; }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _weekday,
                  hint: const Text('Select Day'),
                  decoration: InputDecoration(
                      labelText: 'Day', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: List.generate(7, (i) => i + 1)
                      .map((w) => DropdownMenuItem(value: w, child: Text(kWeekdayLabels[w - 1])))
                      .toList(),
                  onChanged: (val) => setState(() { _weekday = val; _crowdResult = null; _crowdValidationMsg = null; }),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickTime,
                  child: InputDecorator(
                    decoration: InputDecoration(
                        labelText: 'Time', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text(
                      _time != null ? _time!.format(context) : 'Select Time',
                      style: TextStyle(fontSize: 16, color: _time != null ? Colors.black87 : Colors.black45),
                    ),
                  ),
                ),
                if (_time != null) ...[
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final category = timeCategoryFor(_time!.hour * 60 + _time!.minute);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: category.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: category.color.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: category.color),
                          const SizedBox(width: 6),
                          Text('Time Category: ',
                              style: TextStyle(fontSize: 12, color: category.color, fontWeight: FontWeight.w500)),
                          Text(category.label,
                              style: TextStyle(fontSize: 12, color: category.color, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Text('(${category.rangeLabel})',
                              style: TextStyle(fontSize: 11, color: category.color.withValues(alpha: 0.75))),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 16),
                if (_isOutsideOperatingHours) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.do_not_disturb_on_outlined, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Service Unavailable — Rapid KL rail services operate from 6:00 AM to 12:00 AM. '
                                'Choose a time within operating hours to get a crowd prediction.',
                            style: TextStyle(fontSize: 12.5, color: Colors.red, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.analytics, color: Colors.white),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _runCrowdEstimate,
                    label: const Text('Predict Crowd', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                  if (_crowdValidationMsg != null) ...[
                    const SizedBox(height: 12),
                    _validationMessage(_crowdValidationMsg!),
                  ],
                ],
              ],
            ),
          ),

          if (_crowdResult != null) ...[
            const SizedBox(height: _sectionGap),

            _sectionCard(
              title: 'CROWD PREDICTION SUMMARY',
              icon: Icons.groups_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('EXPECTED CROWD',
                                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('${_crowdResult!.occupancy}',
                                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black87)),
                                const Text('%', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: _crowdResult!.level.color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Text(_crowdResult!.level.label,
                                      style: TextStyle(color: _crowdResult!.level.color, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            Container(
                              height: 4, width: double.infinity,
                              decoration: BoxDecoration(color: _crowdResult!.level.color, borderRadius: BorderRadius.circular(2)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('EST. QUEUE',
                                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                            Text(_crowdResult!.level.queueEstimate,
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _crowdResult!.level.color.withValues(alpha: 0.05),
                      border: Border.all(color: _crowdResult!.level.color.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      getAiInsight(_station!, _crowdResult!.level, _time!, _weekday!),
                      style: TextStyle(color: _crowdResult!.level.color, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _sectionGap),

            _sectionCard(
              title: 'STATION DEMAND PROFILE',
              icon: Icons.insights_outlined,
              child: _buildStationDemandProfile(),
            ),
            const SizedBox(height: _sectionGap),

            _buildCalculationBreakdownCard(),
          ],

          const SizedBox(height: _sectionGap),
          _sectionCard(
            title: 'CROWD LEVEL LEGEND',
            icon: Icons.palette_outlined,
            child: _buildCrowdLegend(),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculationBreakdownCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(_sectionCardRadius),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: _sectionCardPadding, vertical: 2),
          childrenPadding:
          const EdgeInsets.fromLTRB(_sectionCardPadding, 0, _sectionCardPadding, _sectionCardPadding),
          leading: const Icon(Icons.calculate_outlined, size: 18, color: Colors.black54),
          title: const Text('How is this estimated?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
          children: [_buildCalculationBreakdown()],
        ),
      ),
    );
  }

  Widget _buildCalculationBreakdown() {
    final dayAvg = _crowdResultDayAvg ?? 0;
    final factor = _crowdResultFactor ?? 0;
    final dayLabel = kWeekdayLabels[_weekday! - 1];
    final baseline = _baselineOccupancy(_weekday!, _time!.hour * 60 + _time!.minute);
    final occupancy = _crowdResult!.occupancy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.2)),
          ),
          child: const Text(
            'Estimated crowd = time-of-day pattern × network comparison',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF4F46E5)),
          ),
        ),
        const SizedBox(height: 12),

        _breakdownStep(
          step: 1,
          title: 'Historical ridership',
          lines: [
            '$dayLabel average: ${dayAvg.round()} trips/day',
          ],
        ),
        _breakdownStep(
          step: 2,
          title: 'Compared with network average',
          lines: [
            '${dayAvg.round()} ÷ ${_networkAverage.round()} = ${factor.toStringAsFixed(2)}x',
          ],
        ),
        _breakdownStep(
          step: 3,
          title: 'Time-of-day pattern',
          lines: [
            '${_time!.format(context)} estimated baseline: $baseline%',
          ],
        ),
        _breakdownStep(
          step: 4,
          title: 'Final estimate',
          lines: [
            '$baseline% × ${factor.toStringAsFixed(2)} = $occupancy%',
          ],
          isLast: true,
        ),

        const Divider(height: 18),
        _breakdownRow(
          'Estimated Crowd',
          '$occupancy%',
          emphasize: true,
          valueColor: _crowdResult!.level.color,
        ),
      ],
    );
  }

  Widget _breakdownStep({
    required int step,
    required String title,
    required List<String> lines,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$step',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 2),
                ...lines.map((l) => Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(l, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, String value, {bool emphasize = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.black87,
                  fontWeight: emphasize ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  color: valueColor ?? Colors.black87,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStationDemandProfile() {
    final factor = _crowdResultFactor ?? 1.0;
    final dayLabel = kWeekdayLabels[_weekday! - 1];
    final (status, color, icon) = _demandInterpretation(factor);
    final comparisonWord = factor < 0.95
        ? 'lower'
        : factor > 1.05
        ? 'higher'
        : 'similar';
    final comparisonPhrase = comparisonWord == 'similar'
        ? 'ridership similar to the average station'
        : '$comparisonWord ridership than the average station';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text('$status (${factor.toStringAsFixed(2)}×)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$_station typically has $comparisonPhrase on ${dayLabel}s.',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildCrowdLegend() {
    final entries = [
      ('Low', '0–27%', CrowdLevel.low.color),
      ('Moderate', '28–54%', CrowdLevel.moderate.color),
      ('High', '55–79%', CrowdLevel.high.color),
      ('Critical', '80–100%', CrowdLevel.critical.color),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: entries.map((e) {
        final (name, range, color) = e;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('$name: ', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
            Text(range, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildPeakHoursTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Peak Demand Analysis',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Identify the busiest predicted time periods based on historical ridership patterns.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: _sectionGap),

          _sectionCard(
            title: 'STATION & DAY SELECTION',
            icon: Icons.tune,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StationSearchField(
                  label: 'Station',
                  stations: _stations,
                  value: _peakStation,
                  onChanged: (val) => setState(() { _peakStation = val; _peakSlots = null; _peakDayAvg = null; _peakFactor = null; _peakValidationMsg = null; }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _peakWeekday,
                  hint: const Text('Select Day'),
                  decoration: InputDecoration(
                      labelText: 'Day', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: List.generate(7, (i) => i + 1)
                      .map((w) => DropdownMenuItem(value: w, child: Text(kWeekdayLabels[w - 1])))
                      .toList(),
                  onChanged: (val) => setState(() { _peakWeekday = val; _peakSlots = null; _peakDayAvg = null; _peakFactor = null; _peakValidationMsg = null; }),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.schedule, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _runPeakHours,
                  label: const Text('Show Peak Pattern', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
                if (_peakValidationMsg != null) ...[
                  const SizedBox(height: 12),
                  _validationMessage(_peakValidationMsg!),
                ],
              ],
            ),
          ),

          if (_peakSlots != null) ...[
            const SizedBox(height: _sectionGap),

            _sectionCard(
              title: 'FULL-DAY CROWD PATTERN',
              icon: Icons.show_chart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFullDayCrowdChart(),
                ],
              ),
            ),
            const SizedBox(height: _sectionGap),

            _sectionCard(
              title: 'PEAK ANALYSIS SUMMARY',
              icon: Icons.summarize_outlined,
              child: _buildPeakSummaryCard(),
            ),
            const SizedBox(height: _sectionGap),

            _sectionCard(
              title: 'TOP 3 PREDICTED TIME PERIODS',
              icon: Icons.leaderboard_outlined,
              child: _buildTopPeakPeriods(),
            ),
            const SizedBox(height: _sectionGap),

            _sectionCard(
              title: 'PEAK VS OFF-PEAK COMPARISON',
              icon: Icons.compare_arrows,
              child: _buildPeakVsOffPeak(),
            ),
            const SizedBox(height: _sectionGap),

            _buildPeakMethodologyCard(),
          ],
        ],
      ),
    );
  }

  String _hourLabel(int hour) {
    final h = hour % 24;
    return h == 12 ? '12pm' : h > 12 ? '${h - 12}pm' : h == 0 ? '12am' : '${h}am';
  }

  Widget _buildPeakSummaryCard() {
    final peak = _peakSlots!.reduce((a, b) => a.value.occupancy >= b.value.occupancy ? a : b);
    final category = timeCategoryFor(peak.key * 60);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _breakdownRow('Peak Period', category.label),
        _breakdownRow('Peak Time', _hourLabel(peak.key)),
        _breakdownRow('Peak Occupancy', '${peak.value.occupancy}%',
            valueColor: peak.value.level.color),
        _breakdownRow('Crowd Level', peak.value.level.label,
            valueColor: peak.value.level.color),
      ],
    );
  }

  Widget _buildTopPeakPeriods() {
    final sorted = [..._peakSlots!]
      ..sort((a, b) => b.value.occupancy.compareTo(a.value.occupancy));
    final top3 = sorted.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: top3.asMap().entries.map((e) {
        final rank = e.key + 1;
        final entry = e.value;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('$rank',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                ),
              ),
              const SizedBox(width: 10),
              Text(_hourLabel(entry.key), style: const TextStyle(fontSize: 13, color: Colors.black87)),
              const Spacer(),
              Text('${entry.value.occupancy}%',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: entry.value.level.color)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPeakVsOffPeak() {
    final peak = _peakSlots!.reduce((a, b) => a.value.occupancy >= b.value.occupancy ? a : b);
    final offPeak = _peakSlots!.reduce((a, b) => a.value.occupancy <= b.value.occupancy ? a : b);
    final diff = peak.value.occupancy - offPeak.value.occupancy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _breakdownRow('Peak Occupancy (${_hourLabel(peak.key)})', '${peak.value.occupancy}%',
            valueColor: peak.value.level.color),
        _breakdownRow('Off-Peak Occupancy (${_hourLabel(offPeak.key)})', '${offPeak.value.occupancy}%',
            valueColor: offPeak.value.level.color),
        const Divider(height: 18),
        _breakdownRow('Difference', '+$diff%', emphasize: true, valueColor: const Color(0xFF4F46E5)),
      ],
    );
  }

  Widget _buildPeakMethodologyCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(_sectionCardRadius),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: _sectionCardPadding, vertical: 2),
          childrenPadding:
          const EdgeInsets.fromLTRB(_sectionCardPadding, 0, _sectionCardPadding, _sectionCardPadding),
          leading: const Icon(Icons.calculate_outlined, size: 18, color: Colors.black54),
          title: const Text('How is this estimated?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
          children: [_buildPeakMethodologyContent()],
        ),
      ),
    );
  }

  Widget _buildPeakMethodologyContent() {
    final dayAvg = _peakDayAvg ?? 0;
    final factor = _peakFactor ?? 0;
    final dayLabel = _peakWeekday != null ? kWeekdayLabels[_peakWeekday! - 1] : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.2)),
          ),
          child: const Text(
            'Estimated crowd = time-of-day baseline × station factor',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF4F46E5)),
          ),
        ),
        const SizedBox(height: 12),

        _breakdownStep(
          step: 1,
          title: 'Historical ridership',
          lines: [
            '$dayLabel average: ${dayAvg.round()} trips/day',
          ],
        ),
        _breakdownStep(
          step: 2,
          title: 'Compared with network average',
          lines: [
            '${dayAvg.round()} ÷ ${_networkAverage.round()} = ${factor.toStringAsFixed(2)}x',
          ],
        ),
        _breakdownStep(
          step: 3,
          title: 'Time-of-day baseline',
          lines: [
            'Each time of day has a modelled baseline %, with different patterns for weekdays and '
                'weekends. The one for $dayLabel is multiplied by the ${factor.toStringAsFixed(2)}x factor '
                'above to get the estimate shown in the chart.',
          ],
          isLast: true,
        ),
        const SizedBox(height: 10),
        _buildFullBaselineRanges(),
        const SizedBox(height: 10),
        const Text(
          'These are modelled estimates, not observed hourly ridership. The source dataset contains daily '
              'totals only.',
          style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _buildFullBaselineRanges() {
    final weekday = _peakWeekday!;
    final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;
    final factor = _peakFactor ?? 0;
    final accent = const Color(0xFF4F46E5);
    TextStyle colStyle(bool selected) => TextStyle(
        fontSize: 12,
        color: selected ? accent : Colors.black45,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal);

    final hours = List.generate(19, (i) => 6 + i);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                  flex: 2,
                  child: Text('Hour',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54))),
              Expanded(
                  flex: 3,
                  child: Text('Weekday',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isWeekend ? Colors.black54 : accent))),
              Expanded(
                  flex: 3,
                  child: Text('Weekend',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isWeekend ? accent : Colors.black54))),
              const Expanded(
                  flex: 3,
                  child: Text('Estimated',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54))),
            ],
          ),
          const Divider(height: 10),
          ...hours.map((hour) {
            final minutes = hour * 60;
            final weekdayBaseline = _baselineOccupancy(DateTime.monday, minutes);
            final weekendBaseline = _baselineOccupancy(DateTime.saturday, minutes);
            final estimated = predictCrowd(weekday, minutes, factor);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                      flex: 2,
                      child: Text(_hourLabel(hour), style: const TextStyle(fontSize: 12, color: Colors.black87))),
                  Expanded(
                      flex: 3,
                      child: Text('$weekdayBaseline%', textAlign: TextAlign.right, style: colStyle(!isWeekend))),
                  Expanded(
                      flex: 3,
                      child: Text('$weekendBaseline%', textAlign: TextAlign.right, style: colStyle(isWeekend))),
                  Expanded(
                      flex: 3,
                      child: Text('${estimated.occupancy}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold, color: estimated.level.color))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFullDayCrowdChart() {
    final weekday = _peakWeekday!;
    final factor = _peakFactor ?? 0;

    final hours = List.generate(19, (i) => 6 + i);
    final results = hours.map((h) => predictCrowd(weekday, h * 60, factor)).toList();
    final occupancies = results.map((r) => r.occupancy).toList();
    final pointColors = results.map((r) => r.level.color).toList();
    var peakIndex = 0;
    for (int i = 1; i < occupancies.length; i++) {
      if (occupancies[i] > occupancies[peakIndex]) peakIndex = i;
    }

    const slotWidth = 40.0;
    final totalWidth = hours.length * slotWidth;
    final effectiveWidth = totalWidth < 280 ? 280.0 : totalWidth;

    final hoverIdx = _fullDayHoverIndex;
    final hoverValid = hoverIdx != null && hoverIdx >= 0 && hoverIdx < hours.length;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          SizedBox(
            height: 18,
            child: hoverValid
                ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_hourLabel(hours[hoverIdx])}: ${results[hoverIdx].occupancy}% (${results[hoverIdx].level.label})',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: results[hoverIdx].level.color),
              ),
            )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: effectiveWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 120,
                    width: effectiveWidth,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size(effectiveWidth, 120),
                          painter: _FullDayCrowdLineChartPainter(
                            occupancies: occupancies,
                            pointColors: pointColors,
                            peakIndex: peakIndex,
                          ),
                        ),

                        Row(
                          children: List.generate(hours.length, (i) {
                            final result = results[i];
                            return Expanded(
                              child: MouseRegion(
                                onEnter: (_) => setState(() => _fullDayHoverIndex = i),
                                onExit: (_) => setState(() {
                                  if (_fullDayHoverIndex == i) _fullDayHoverIndex = null;
                                }),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(
                                          () => _fullDayHoverIndex = _fullDayHoverIndex == i ? null : i),
                                  child: Tooltip(
                                    message:
                                    '${_hourLabel(hours[i])}: ${result.occupancy}% (${result.level.label})',
                                    waitDuration: const Duration(milliseconds: 200),
                                    child: Container(color: Colors.transparent),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: hours.map((h) {
                      return SizedBox(
                        width: totalWidth < 280 ? 280 / hours.length : slotWidth,
                        child: Text(
                          _hourLabel(h),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9.5, color: Colors.black54),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Ridership History',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Real daily ridership records for the selected station.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: _sectionGap),

          _sectionCard(
            title: 'STATION SELECTION',
            icon: Icons.pin_drop_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StationSearchField(
                  label: 'Station',
                  stations: _stations,
                  value: _historyStation,
                  onChanged: (val) => setState(() {
                    _historyStation = val;
                    _historyData = null;
                    _historyMonthFilter = null;
                    _heatmapSelectedDay = null;
                    _heatmapAllMonthsIndex = null;
                    _historyValidationMsg = null;
                  }),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.show_chart, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _runHistory,
                  label: const Text('Load History', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
                if (_historyValidationMsg != null) ...[
                  const SizedBox(height: 12),
                  _validationMessage(_historyValidationMsg!),
                ],
              ],
            ),
          ),

          if (_historyData != null && _historyData!.isEmpty) ...[
            const SizedBox(height: _sectionGap),
            _emptyState('No records found for this station in the local dataset.'),
          ],
          if (_historyData != null && _historyData!.isNotEmpty) ...[
            Builder(builder: (context) {

              final months = _historyData!
                  .map((e) => DateTime(e.date.year, e.date.month))
                  .toSet()
                  .toList()
                ..sort();

              final byMonth = _historyMonthFilter == null
                  ? _historyData!
                  : _historyData!
                  .where((e) =>
              e.date.year == _historyMonthFilter!.year &&
                  e.date.month == _historyMonthFilter!.month)
                  .toList();

              const monthNames = [
                'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
              ];
              final monthFilterLabel = _historyMonthFilter == null
                  ? 'all months'
                  : '${monthNames[_historyMonthFilter!.month - 1]} ${_historyMonthFilter!.year}';

              final filtersSection = _sectionCard(
                title: 'HISTORY FILTERS',
                icon: Icons.filter_alt_outlined,
                child: DropdownButtonFormField<DateTime?>(
                  value: _historyMonthFilter,
                  decoration: InputDecoration(
                      labelText: 'Filter by month',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: [
                    const DropdownMenuItem<DateTime?>(
                        value: null, child: Text('All months')),
                    ...months.map((m) => DropdownMenuItem<DateTime?>(
                      value: m,
                      child: Text('${monthNames[m.month - 1]} ${m.year}'),
                    )),
                  ],
                  onChanged: (val) => setState(() {
                    _historyMonthFilter = val;
                    _heatmapAllMonthsIndex = null;
                    _heatmapSelectedDay = null;
                  }),
                ),
              );

              final weeklyPattern = _computeWeeklyPattern(byMonth);

              final weekdayWeekendStats = _computeWeekdayWeekendComparison(byMonth);
              final weeklyPatternSection =
              _buildWeeklyPatternSection(weeklyPattern, weekdayWeekendStats, monthFilterLabel);

              final monthlyTrend = _computeMonthlyTrend(_historyData!);
              final monthlyTrendSection = _buildMonthlyTrendSection(monthlyTrend);

              late final DateTime heatmapMonth;
              late final bool heatmapShowArrows;
              int heatmapAllMonthsIdx = 0;
              if (_historyMonthFilter != null) {
                heatmapMonth = _historyMonthFilter!;
                heatmapShowArrows = false;
              } else {
                heatmapAllMonthsIdx =
                    (_heatmapAllMonthsIndex ?? (months.length - 1)).clamp(0, months.length - 1);
                heatmapMonth = months[heatmapAllMonthsIdx];
                heatmapShowArrows = months.length > 1;
              }
              final heatmapMonthLabel = '${monthNames[heatmapMonth.month - 1]} ${heatmapMonth.year}';
              final heatmapSection = _buildHeatmapSection(
                _historyData!,
                heatmapMonth,
                heatmapMonthLabel,
                showArrows: heatmapShowArrows,
                canGoPrev: heatmapAllMonthsIdx > 0,
                canGoNext: heatmapAllMonthsIdx < months.length - 1,
                onPrev: () => setState(() {
                  _heatmapAllMonthsIndex = heatmapAllMonthsIdx - 1;
                  _heatmapSelectedDay = null;
                }),
                onNext: () => setState(() {
                  _heatmapAllMonthsIndex = heatmapAllMonthsIdx + 1;
                  _heatmapSelectedDay = null;
                }),
              );

              if (byMonth.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: _sectionGap),
                    filtersSection,
                    const SizedBox(height: _sectionGap),
                    _emptyState('No records for the selected month.'),
                    const SizedBox(height: _sectionGap),
                    heatmapSection,
                    const SizedBox(height: _sectionGap),
                    weeklyPatternSection,
                    const SizedBox(height: _sectionGap),
                    monthlyTrendSection,
                  ],
                );
              }

              final values = byMonth.map((e) => e.ridership).toList();
              final avg = values.reduce((a, b) => a + b) / values.length;
              final maxRecord = byMonth.reduce((a, b) => a.ridership >= b.ridership ? a : b);
              final minRecord = byMonth.reduce((a, b) => a.ridership <= b.ridership ? a : b);
              final latest = byMonth.last;
              final trend = _computeRidershipTrend(byMonth);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: _sectionGap),
                  filtersSection,
                  const SizedBox(height: _sectionGap),

                  _sectionCard(
                    title: 'SUMMARY STATISTICS',
                    icon: Icons.query_stats_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                  child: _statCard('AVERAGE', avg.round().toString(),
                                      accentColor: const Color(0xFF4F46E5))),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _statCard('HIGHEST', maxRecord.ridership.toString(),
                                      subtitle: '${maxRecord.date.day}/${maxRecord.date.month}/${maxRecord.date.year}',
                                      accentColor: const Color(0xFFDC2626))),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _statCard('LOWEST', minRecord.ridership.toString(),
                                      subtitle: '${minRecord.date.day}/${minRecord.date.month}/${minRecord.date.year}',
                                      accentColor: const Color(0xFF16A34A))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(fontSize: 11, color: Colors.black45),
                            children: [
                              const TextSpan(text: 'Most recent on file: '),
                              TextSpan(
                                text:
                                '${latest.date.day}/${latest.date.month}/${latest.date.year} — ${latest.ridership} trips',
                                style: const TextStyle(color: Color(0xFF0891B2), fontWeight: FontWeight.bold),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _sectionGap),

                  _sectionCard(
                    title: 'RIDERSHIP TREND',
                    icon: Icons.trending_up,
                    child: trend == null
                        ? _emptyState('Need at least 2 records in the current filter to compute a trend.')
                        : Builder(builder: (context) {
                      final (message, color, icon) = _ridershipInsight(trend);
                      final pct = trend.percentChange;

                      final pctColor = pct > 5
                          ? const Color(0xFFDC2626)
                          : pct < -5
                          ? const Color(0xFF16A34A)
                          : Colors.blueGrey;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                    child: _statCard('EARLIER PERIOD AVG',
                                        trend.previousAvg.round().toString())),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: _statCard('LATER PERIOD AVG',
                                        trend.currentAvg.round().toString())),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: _statCard('% CHANGE',
                                        '${trend.percentChange >= 0 ? '+' : ''}${trend.percentChange.toStringAsFixed(1)}%',
                                        accentColor: pctColor)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Based on the selected records, split chronologically into two equal periods.',
                            style: TextStyle(fontSize: 11, color: Colors.black45),
                          ),
                          const SizedBox(height: 12),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.05),
                              border: Border.all(color: color.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(icon, size: 16, color: color),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    message,
                                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                  const SizedBox(height: _sectionGap),

                  heatmapSection,
                  const SizedBox(height: _sectionGap),

                  weeklyPatternSection,
                  const SizedBox(height: _sectionGap),

                  monthlyTrendSection,
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildWeeklyPatternSection(List<({int weekday, double avg, int count})> pattern,
      _WeekdayWeekendStats weekdayWeekendStats, String monthFilterLabel) {
    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    final (message, color, icon) = _weeklyPatternInsight(pattern);

    if (pattern.isEmpty) {
      return _sectionCard(
        title: 'WEEKLY RIDERSHIP PATTERN',
        icon: Icons.calendar_view_week,
        subtitle: 'Average ridership by day of week (Mon-Sun) for $monthFilterLabel.',
        child: _emptyState('No records available to compute a weekly pattern.'),
      );
    }

    final sorted = [...pattern]..sort((a, b) => b.avg.compareTo(a.avg));
    final highest = sorted.first;
    final lowest = sorted.last;
    final maxAvg = highest.avg;
    final minAvg = lowest.avg;
    final avgRange = maxAvg - minAvg;

    return _sectionCard(
      title: 'WEEKLY RIDERSHIP PATTERN',
      icon: Icons.calendar_view_week,
      subtitle: 'Average ridership by day of week (Mon-Sun) for $monthFilterLabel.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...pattern.map((p) {
            final isMax = p.weekday == highest.weekday;
            final isMin = p.weekday == lowest.weekday && lowest.weekday != highest.weekday;

            final t = avgRange == 0 ? 1.0 : ((p.avg - minAvg) / avgRange).clamp(0.0, 1.0);
            final barColor = Color.lerp(const Color(0xFF16A34A), const Color(0xFFDC2626), t)!;
            return _weekdayRow(
              dayNames[p.weekday - 1],
              p.avg,
              maxAvg,
              color: barColor,
              isMax: isMax,
              isMin: isMin,
            );
          }),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.05),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(message, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
          _weekdayWeekendComparisonSection(weekdayWeekendStats, monthFilterLabel),
        ],
      ),
    );
  }

  Widget _weekdayWeekendComparisonSection(_WeekdayWeekendStats stats, String monthFilterLabel) {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Container(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
        const SizedBox(height: 16),
        const Text(
          'WEEKDAY VS WEEKEND',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black45, letterSpacing: 0.5),
        ),
        const SizedBox(height: 2),
        Text(
          'Average daily ridership for weekdays versus weekends in $monthFilterLabel.',
          style: const TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 12),
      ],
    );

    if (stats.weekdayCount == 0 && stats.weekendCount == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          _emptyState('No records available to compare weekdays and weekends.'),
        ],
      );
    }

    final weekdayAvg = stats.weekdayAvg;
    final weekendAvg = stats.weekendAvg;
    final maxAvg = [weekdayAvg ?? 0.0, weekendAvg ?? 0.0].reduce((a, b) => a >= b ? a : b);

    const moreColor = Color(0xFFDC2626);
    const fewerColor = Color(0xFF16A34A);
    Color weekdayColor = Colors.blueGrey;
    Color weekendColor = Colors.blueGrey;
    if (weekdayAvg != null && weekendAvg != null && weekdayAvg != weekendAvg) {
      weekdayColor = weekdayAvg > weekendAvg ? moreColor : fewerColor;
      weekendColor = weekdayAvg > weekendAvg ? fewerColor : moreColor;
    }

    Widget diffLine;
    if (weekdayAvg != null && weekendAvg != null) {
      final diff = weekdayAvg - weekendAvg;
      final lowerAvg = diff >= 0 ? weekendAvg : weekdayAvg;
      final diffPct = lowerAvg > 0 ? (diff.abs() / lowerAvg * 100) : 0.0;
      diffLine = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: diff.abs() < 0.5
            ? const Text(
          'Difference: 0/day (0.0%, essentially tied)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
        )
            : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Difference: ${_formatNumber(diff.abs())}/day',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 2),

            Text(
              'Weekday is ${diffPct.toStringAsFixed(1)}% ${diff > 0 ? 'higher' : 'lower'}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: diff > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
            ),
          ],
        ),
      );
    } else {

      final missing = weekdayAvg == null ? 'weekday' : 'weekend';
      diffLine = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'No $missing records for the selected month — difference not available.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _compareStatBlock(
                  'Weekday Avg (Mon–Fri)', weekdayAvg ?? 0.0, weekdayColor),
            ),
            Container(
              width: 1,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: Colors.grey.withValues(alpha: 0.2),
            ),
            Expanded(
              child: _compareStatBlock(
                  'Weekend Avg (Sat–Sun)', weekendAvg ?? 0.0, weekendColor),
            ),
          ],
        ),
        const SizedBox(height: 12),
        diffLine,
        const SizedBox(height: 14),
        _weekdayWeekendBarRow('Weekday', weekdayAvg ?? 0.0, maxAvg, color: weekdayColor),
        const SizedBox(height: 10),
        _weekdayWeekendBarRow('Weekend', weekendAvg ?? 0.0, maxAvg, color: weekendColor),
      ],
    );
  }

  Widget _weekdayWeekendBarRow(String label, double avg, double maxAvg, {required Color color}) {
    final factor = maxAvg == 0 ? 0.0 : avg / maxAvg;
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        Expanded(
          child: Container(
            height: 14,
            decoration:
            BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: factor.clamp(0.03, 1.0),
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            '${_formatNumber(avg)}/day',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
    );
  }

  Widget _weekdayRow(String dayLabel, double avg, double maxAvg,
      {required Color color, required bool isMax, required bool isMin}) {
    final factor = maxAvg == 0 ? 0.0 : avg / maxAvg;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  dayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: (isMax || isMin) ? FontWeight.bold : FontWeight.normal,
                      color: Colors.black87),
                ),
              ),
              Expanded(
                child: Container(
                  height: 12,
                  decoration:
                  BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: factor.clamp(0.03, 1.0),
                    child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: Text(
                  avg.round().toString(),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          if (isMax || isMin) ...[
            Padding(
              padding: const EdgeInsets.only(left: 92, top: 2),
              child: Text(isMax ? 'Highest' : 'Lowest', style: TextStyle(fontSize: 10, color: color)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthlyTrendSection(List<({DateTime month, double avg, int count})> trend) {
    if (trend.isEmpty) {
      return _sectionCard(
        title: 'MONTHLY RIDERSHIP TREND',
        icon: Icons.show_chart,
        subtitle: 'Average daily ridership by month.',
        child: _emptyState('No records available to compute a monthly trend.'),
      );
    }

    final sorted = [...trend]..sort((a, b) => b.avg.compareTo(a.avg));
    final highest = sorted.first;
    final lowest = sorted.last;
    final highestIndex = trend.indexWhere((t) => t.month == highest.month);
    final lowestIndex = trend.indexWhere((t) => t.month == lowest.month);

    double? overallChangePct;
    if (trend.length >= 2 && trend.first.avg != 0) {
      overallChangePct = ((trend.last.avg - trend.first.avg) / trend.first.avg) * 100;
    }
    final (changeMessage, changeColor, changeIcon) =
    _monthlyChangeInsight(overallChangePct, trend.first.month, trend.last.month);

    return _sectionCard(
      title: 'MONTHLY RIDERSHIP TREND',
      icon: Icons.show_chart,
      subtitle: 'Average daily ridership by month.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _monthlyTrendChart(trend, highestIndex, lowestIndex),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _compareStatBlock(
                  'Highest: ${DateFormat('MMM yyyy').format(highest.month)}',
                  highest.avg,
                  const Color(0xFFDC2626),
                ),
              ),
              Container(
                width: 1,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.grey.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _compareStatBlock(
                  'Lowest: ${DateFormat('MMM yyyy').format(lowest.month)}',
                  lowest.avg,
                  const Color(0xFF16A34A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: changeColor.withValues(alpha: 0.05),
              border: Border.all(color: changeColor.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(changeIcon, size: 16, color: changeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    changeMessage,
                    style: TextStyle(color: changeColor, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, IconData) _monthlyChangeInsight(
      double? pct, DateTime firstMonth, DateTime lastMonth) {
    if (pct == null) {
      return (
      'Only one month of real data is available for this station, so an overall change can\'t be computed.',
      Colors.blueGrey,
      Icons.info_outline,
      );
    }
    final fromLabel = DateFormat('MMM yyyy').format(firstMonth);
    final toLabel = DateFormat('MMM yyyy').format(lastMonth);
    if (pct > 5) {
      return (
      'Ridership rose ${pct.toStringAsFixed(1)}% from $fromLabel to $toLabel.',
      Colors.red.shade700,
      Icons.trending_up,
      );
    } else if (pct < -5) {
      return (
      'Ridership fell ${pct.abs().toStringAsFixed(1)}% from $fromLabel to $toLabel.',
      Colors.green.shade700,
      Icons.trending_down,
      );
    }
    return (
    'Ridership stayed roughly stable (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%) from $fromLabel to $toLabel.',
    Colors.blueGrey,
    Icons.trending_flat,
    );
  }

  Widget _monthlyTrendChart(
      List<({DateTime month, double avg, int count})> trend, int highestIndex, int lowestIndex) {
    const slotWidth = 64.0;
    final values = trend.map((t) => t.avg).toList();
    final totalWidth = trend.length * slotWidth;
    final effectiveWidth = totalWidth < 200 ? 200.0 : totalWidth;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: effectiveWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 120,
                width: effectiveWidth,
                child: Stack(
                  children: [
                    CustomPaint(
                      size: Size(effectiveWidth, 120),
                      painter: _MonthlyLineChartPainter(
                        values: values,
                        highestIndex: highestIndex,
                        lowestIndex: lowestIndex,
                      ),
                    ),

                    Row(
                      children: trend.map((t) {
                        return Expanded(
                          child: Tooltip(
                            message: '${DateFormat('MMM yyyy').format(t.month)}\n'
                                '${_formatNumber(t.avg)} trips/day avg',
                            child: Container(color: Colors.transparent),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: trend.map((t) {
                  return SizedBox(
                    width: totalWidth < 200 ? 200 / trend.length : slotWidth,
                    child: Text(
                      DateFormat('MMM yy').format(t.month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_HeatmapDayCell> _computeHeatmapMonthCells(
      List<RidershipRecord> records, DateTime month) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final Map<int, double> byDay = {};
    for (final r in records) {
      if (r.date.year == month.year && r.date.month == month.month) {
        byDay[r.date.day] = r.ridership.toDouble();
      }
    }
    return List.generate(daysInMonth, (i) {
      final day = i + 1;
      return (day: day, date: DateTime(month.year, month.month, day), ridership: byDay[day]);
    });
  }

  (double, double)? _heatmapMinMax(List<_HeatmapDayCell> cells) {
    final values = cells.where((c) => c.ridership != null).map((c) => c.ridership!).toList();
    if (values.isEmpty) return null;
    return (values.reduce((a, b) => a < b ? a : b), values.reduce((a, b) => a > b ? a : b));
  }

  Color _heatmapColor(double value, (double, double) minMax) {
    final (minV, maxV) = minMax;
    final t = (maxV == minV) ? 1.0 : ((value - minV) / (maxV - minV)).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFF16A34A), const Color(0xFFDC2626), t)!.withValues(alpha: 0.15 + t * 0.65);
  }

  Widget _buildHeatmapSection(
      List<RidershipRecord> records, DateTime heatmapMonth, String heatmapMonthLabel,
      {required bool showArrows,
        required bool canGoPrev,
        required bool canGoNext,
        required VoidCallback onPrev,
        required VoidCallback onNext}) {
    final cells = _computeHeatmapMonthCells(records, heatmapMonth);
    final minMax = _heatmapMinMax(cells);

    return _sectionCard(
      title: 'CALENDAR HEATMAP',
      icon: Icons.calendar_month,
      subtitle: 'Daily ridership intensity for $heatmapMonthLabel. Tap a day to view its exact figure.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showArrows) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: canGoPrev ? onPrev : null,
                  icon: const Icon(Icons.chevron_left),
                  color: const Color(0xFF4F46E5),
                  tooltip: 'Previous month',
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    heatmapMonthLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                IconButton(
                  onPressed: canGoNext ? onNext : null,
                  icon: const Icon(Icons.chevron_right),
                  color: const Color(0xFF4F46E5),
                  tooltip: 'Next month',
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (cells.every((c) => c.ridership == null)) ...[
            _emptyState('No records for $heatmapMonthLabel.'),
          ] else ...[
            _heatmapWeekdayHeader(),
            const SizedBox(height: 4),
            _heatmapGrid(cells, minMax!),
            const SizedBox(height: 12),
            _heatmapLegend(minMax),
          ],
          if (_heatmapSelectedDay != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _heatmapSelectedDay!.ridership != null
                    ? '${DateFormat('EEEE, d MMM yyyy').format(_heatmapSelectedDay!.date)} — '
                    '${_formatNumber(_heatmapSelectedDay!.ridership!)} trips'
                    : '${DateFormat('EEEE, d MMM yyyy').format(_heatmapSelectedDay!.date)} — no record for this date',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heatmapWeekdayHeader() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: labels
          .map((l) => Expanded(
        child: Center(
          child: Text(l, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black45)),
        ),
      ))
          .toList(),
    );
  }

  Widget _heatmapGrid(List<_HeatmapDayCell> cells, (double, double) minMax) {
    final leading = cells.first.date.weekday - 1;
    final items = <_HeatmapDayCell?>[
      ...List<_HeatmapDayCell?>.filled(leading, null),
      ...cells,
    ];
    while (items.length % 7 != 0) {
      items.add(null);
    }
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += 7) {
      final week = items.sublist(i, i + 7);
      rows.add(Row(children: week.map((c) => Expanded(child: _heatmapCell(c, minMax))).toList()));
    }
    return Column(children: rows);
  }

  Widget _heatmapCell(_HeatmapDayCell? cell, (double, double) minMax) {
    if (cell == null) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox.shrink());
    }
    final hasData = cell.ridership != null;
    final t = hasData
        ? ((minMax.$2 == minMax.$1) ? 1.0 : ((cell.ridership! - minMax.$1) / (minMax.$2 - minMax.$1)).clamp(0.0, 1.0))
        : 0.0;
    final bgColor = hasData ? _heatmapColor(cell.ridership!, minMax) : Colors.grey.withValues(alpha: 0.05);
    final textColor = hasData
        ? (t > 0.55 ? Colors.white : Colors.black87)
        : Colors.black26;

    return AspectRatio(
      aspectRatio: 1,
      child: Tooltip(
        message: hasData
            ? '${DateFormat('d MMM yyyy').format(cell.date)}\n${_formatNumber(cell.ridership!)} trips'
            : '${DateFormat('d MMM yyyy').format(cell.date)}\nNo record',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _heatmapSelectedDay = (date: cell.date, ridership: cell.ridership);
          }),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.withValues(alpha: hasData ? 0.15 : 0.12)),
            ),
            alignment: Alignment.center,
            child: Text(
              '${cell.day}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heatmapLegend((double, double) minMax) {
    final (minV, maxV) = minMax;
    return Row(
      children: [
        const Text('Low', style: TextStyle(fontSize: 10, color: Colors.black45)),
        const SizedBox(width: 6),
        Container(
          width: 72,
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF16A34A).withValues(alpha: 0.5),
                const Color(0xFFDC2626).withValues(alpha: 0.8),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Text('High', style: TextStyle(fontSize: 10, color: Colors.black45)),
        const Spacer(),
        Text(
          '${_formatNumber(minV)}–${_formatNumber(maxV)} trips/day',
          style: const TextStyle(fontSize: 10.5, color: Colors.black45),
        ),
      ],
    );
  }

  Widget _buildConnectionsTab() {
    final hasOdData = _connStation != null && _stationsWithOdData.contains(_connStation);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Station Connections',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Real trip counts showing where riders travel to and from this station.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: _sectionGap),

          _sectionCard(
            title: 'STATION SELECTION',
            icon: Icons.pin_drop_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StationSearchField(
                  label: 'Station',
                  stations: _stations,
                  value: _connStation,
                  onChanged: (val) => setState(() {
                    _connStation = val;
                    _connTopDestinations = null;
                    _connTopOrigins = null;
                    _connValidationMsg = null;
                  }),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: _loadingConnections
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.alt_route, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _loadingConnections ? null : _runConnections,
                  label: const Text('Show Connections', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
                if (_connValidationMsg != null) ...[
                  const SizedBox(height: 12),
                  _validationMessage(_connValidationMsg!),
                ],
              ],
            ),
          ),

          if (_loadingConnections) ...[
            const SizedBox(height: _sectionGap),
            Row(
              children: [
                const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5))),
                const SizedBox(width: 10),
                Text('Loading connections… ${_connLoadingSeconds}s', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
              ],
            ),
          ],

          if (_connTopDestinations != null) ...[
            const SizedBox(height: _sectionGap),
            if (!hasOdData) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(_sectionCardPadding),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(_sectionCardRadius),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'No real O-D (station-to-station) trip data is recorded for this station in the '
                      'current dataset. The busiest-connections leaderboard below still shows what real '
                      'connection data is available network-wide.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            ] else ...[

              Builder(builder: (context) {
                final outgoing = _connOutgoing ?? 0;
                final incoming = _connIncoming ?? 0;
                Color outColor = Colors.blueGrey;
                Color inColor = Colors.blueGrey;
                if (outgoing != incoming) {
                  outColor = outgoing > incoming ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
                  inColor = outgoing > incoming ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
                }
                return _sectionCard(
                  title: 'CONNECTION SUMMARY',
                  icon: Icons.swap_horiz,
                  child: Row(
                    children: [
                      Expanded(child: _connectionSummaryCard('OUTGOING TRIPS', outgoing,
                          icon: Icons.north_east, color: outColor)),
                      const SizedBox(width: 12),
                      Expanded(child: _connectionSummaryCard('INCOMING TRIPS', incoming,
                          icon: Icons.south_west, color: inColor)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: _sectionGap),

              _sectionCard(
                title: 'CONNECTION INSIGHT',
                icon: Icons.insights,
                child: _connectionInsightCard(_connOutgoing ?? 0, _connIncoming ?? 0),
              ),
              const SizedBox(height: _sectionGap),

              _sectionCard(
                title: 'TOP DESTINATIONS',
                icon: Icons.north_east,
                subtitle: 'Top 5 destinations from ${_connStation ?? ''}',
                child: (_connTopDestinations!.isEmpty)
                    ? _emptyState('No recorded outgoing connections for this station.')
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _connTopDestinations!
                      .map((e) => _connectionRow(e.key, e.value, _connTopDestinations!.first.value))
                      .toList(),
                ),
              ),
              const SizedBox(height: _sectionGap),

              _sectionCard(
                title: 'TOP ORIGINS',
                icon: Icons.south_west,
                subtitle: 'Top 5 origins to ${_connStation ?? ''}',
                child: ((_connTopOrigins ?? const []).isEmpty)
                    ? _emptyState('No recorded incoming connections for this station.')
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _connTopOrigins!
                      .map((e) => _connectionRow(e.key, e.value, _connTopOrigins!.first.value))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: _sectionGap),

            _sectionCard(
              title: 'BUSIEST CONNECTIONS NETWORK-WIDE',
              icon: Icons.leaderboard,
              subtitle: 'Top station-to-station links by total real trips recorded, across the whole dataset.',
              child: (_connBusiestNetwork == null || _connBusiestNetwork!.isEmpty)
                  ? _emptyState('No recorded connections found network-wide.')
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _connBusiestNetwork!.asMap().entries.map((entry) {
                  final rank = entry.key + 1;
                  final e = entry.value;
                  return _busiestConnectionRow(rank, e.key, e.value, _connBusiestNetwork!.first.value);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _connectionInsightCard(int outgoing, int incoming) {
    final diff = incoming - outgoing;
    const accent = Color(0xFF4F46E5);
    final String message;
    final String? diffLabel;
    if (diff == 0) {
      message = 'Incoming and outgoing trips are evenly balanced for this station.';
      diffLabel = null;
    } else if (diff > 0) {
      message = 'More trips are recorded entering this station than leaving it.';
      diffLabel = '${_formatNumber(diff)} more incoming trips';
    } else {
      message = 'More trips are recorded leaving this station than entering it.';
      diffLabel = '${_formatNumber(diff.abs())} more outgoing trips';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.insights, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
                if (diffLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(diffLabel, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: accent)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _busiestConnectionRow(int rank, String label, int trips, int maxTrips) {
    final isTop = rank == 1;

    final factor = maxTrips == 0 ? 0.0 : trips / maxTrips;
    final accent = Color.lerp(const Color(0xFF16A34A), const Color(0xFFDC2626), factor.clamp(0.0, 1.0))!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(vertical: isTop ? 12 : 8, horizontal: isTop ? 10 : 4),
      decoration: isTop
          ? BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#$rank',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: isTop ? 13 : 12, color: isTop ? accent : Colors.black45)),
          ),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: isTop ? 13 : 12, fontWeight: isTop ? FontWeight.bold : FontWeight.normal, color: Colors.black87)),
          ),
          const SizedBox(width: 8),
          Text(_formatNumber(trips),
              style: TextStyle(fontSize: isTop ? 13 : 12, fontWeight: FontWeight.bold, color: isTop ? accent : Colors.black87)),
        ],
      ),
    );
  }

  String _formatNumber(num n) {
    final s = n.round().toString();
    final negative = s.startsWith('-');
    final digits = negative ? s.substring(1) : s;
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return (negative ? '-' : '') + buffer.toString();
  }

  Widget _connectionSummaryCard(String label, int value, {required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.4)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_formatNumber(value), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 2),
          const Text('trips', style: TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      ),
    );
  }

  Widget _connectionRow(String stationName, int trips, int maxTrips) {
    final factor = maxTrips == 0 ? 0.0 : trips / maxTrips;

    final color = Color.lerp(const Color(0xFF16A34A), const Color(0xFFDC2626), factor.clamp(0.0, 1.0))!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(stationName,
                    style: const TextStyle(fontSize: 12.5, color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text(_formatNumber(trips), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            height: 12,
            decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: factor.clamp(0.03, 1.0),
              child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, {String? subtitle, Color? accentColor}) {
    final neutral = accentColor == null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: neutral ? Colors.grey.withValues(alpha: 0.06) : accentColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: neutral ? Colors.transparent : accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: neutral ? Colors.grey : accentColor,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: neutral ? Colors.black87 : accentColor)),
          const SizedBox(height: 2),

          Text(subtitle ?? '\u200b',
              style: const TextStyle(fontSize: 10, color: Colors.black45),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildTab5() {
    return _tab5View == _Tab5View.ranking ? _buildStationRankingTab() : _buildCompareStationsTab();
  }

  Widget _tab5ViewSwitch() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          avatar: const Icon(Icons.leaderboard, size: 15),
          label: const Text('Station Ranking'),
          selected: _tab5View == _Tab5View.ranking,
          onSelected: (_) => setState(() => _tab5View = _Tab5View.ranking),
        ),
        ChoiceChip(
          avatar: const Icon(Icons.compare_arrows, size: 15),
          label: const Text('Compare Stations'),
          selected: _tab5View == _Tab5View.compare,
          onSelected: (_) => setState(() => _tab5View = _Tab5View.compare),
        ),
      ],
    );
  }

  String? _rankingPeriodLabel() {
    final data = _rankingData;
    if (data == null || data.isEmpty) return null;
    DateTime? minDate;
    DateTime? maxDate;
    for (final r in data) {
      if (r.minDate != null && (minDate == null || r.minDate!.isBefore(minDate))) minDate = r.minDate;
      if (r.maxDate != null && (maxDate == null || r.maxDate!.isAfter(maxDate))) maxDate = r.maxDate;
    }
    if (minDate == null || maxDate == null) return null;
    if (minDate.year == maxDate.year) {
      if (minDate.month == maxDate.month) return DateFormat('MMM yyyy').format(minDate);
      return '${DateFormat('MMM').format(minDate)}–${DateFormat('MMM yyyy').format(maxDate)}';
    }
    return '${DateFormat('MMM yyyy').format(minDate)} – ${DateFormat('MMM yyyy').format(maxDate)}';
  }

  Widget _rankingPeriodFilter() {
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final months = _rankingAvailableMonths();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Overall'),
              selected: _rankingPeriod == _RankingPeriod.overall,
              onSelected: (_) => _onRankingPeriodChanged(_RankingPeriod.overall),
            ),
            ChoiceChip(
              label: const Text('Month'),
              selected: _rankingPeriod == _RankingPeriod.month,
              onSelected: (_) => _onRankingPeriodChanged(_RankingPeriod.month),
            ),
            ChoiceChip(
              label: const Text('Day'),
              selected: _rankingPeriod == _RankingPeriod.day,
              onSelected: (_) => _onRankingPeriodChanged(_RankingPeriod.day),
            ),
          ],
        ),
        if (_rankingPeriod == _RankingPeriod.month) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<DateTime>(
            value: _rankingMonth,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'Select month',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: months
                .map((m) => DropdownMenuItem(value: m, child: Text('${monthNames[m.month - 1]} ${m.year}')))
                .toList(),
            onChanged: _onRankingMonthChanged,
          ),
        ],
        if (_rankingPeriod == _RankingPeriod.day) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickRankingDay,
            icon: const Icon(Icons.calendar_today, size: 15),
            label: Text(_rankingDay != null ? DateFormat('d MMM yyyy').format(_rankingDay!) : 'Select a date'),
          ),
        ],
      ],
    );
  }

  Widget _buildStationRankingTab() {
    final periodLabel = _rankingPeriodLabel();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tab5ViewSwitch(),
          const SizedBox(height: 12),
          const Text('Station Ridership Ranking',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Compare stations by their typical daily ridership.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
          _rankingPeriodFilter(),
          if (periodLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              'Based on $periodLabel data.',
              style: const TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 6),

          Text(
            'Network average: ${_formatNumber(_networkAverage)}/day',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black54),
          ),
          const SizedBox(height: _sectionGap),

          if (_rankingPeriod == _RankingPeriod.month && _rankingMonth == null) ...[
            _validationMessage('Please select a month to see the station ranking.'),
            const SizedBox(height: _sectionGap),
          ] else if (_rankingPeriod == _RankingPeriod.day && _rankingDay == null) ...[
            _validationMessage('Please select a date to see the station ranking.'),
            const SizedBox(height: _sectionGap),
          ],

          if (_loadingRanking && _rankingData == null) ...[
            Row(
              children: [
                const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5))),
                const SizedBox(width: 10),
                const Text('Loading ranking…', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: _sectionGap),
          ],

          if (_rankingError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(_sectionCardPadding),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(_sectionCardRadius),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text(_rankingError!, style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ),
            const SizedBox(height: _sectionGap),
          ],

          if (_rankingData != null)
            Builder(builder: (context) {
              if (_rankingData!.isEmpty) {
                return _emptyState('No ridership records found for any station.');
              }

              final sortedDesc = [..._rankingData!]..sort((a, b) => b.avgRidership.compareTo(a.avgRidership));
              final busiest = sortedDesc.take(5).toList();
              final leastBusy = sortedDesc.reversed.take(5).toList();

              double vsNetworkAvg(double stationAvg) =>
                  _networkAverage > 0 ? stationAvg / _networkAverage : 0.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  _sectionCard(
                    title: 'TOP 5 BUSIEST STATIONS',
                    icon: Icons.trending_up,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: busiest.asMap().entries.map((entry) {
                        final rank = entry.key + 1;
                        final r = entry.value;
                        return _rankingRow(rank, r.station, r.avgRidership.round(), vsNetworkAvg(r.avgRidership), const Color(0xFFDC2626));
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: _sectionGap),

                  _sectionCard(
                    title: 'TOP 5 LEAST-BUSY STATIONS',
                    icon: Icons.trending_down,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: leastBusy.asMap().entries.map((entry) {
                        final rank = entry.key + 1;
                        final r = entry.value;
                        return _rankingRow(rank, r.station, r.avgRidership.round(), vsNetworkAvg(r.avgRidership), const Color(0xFF16A34A));
                      }).toList(),
                    ),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _rankingRow(int rank, String station, int avgRidership, double vsNetworkAvg, Color color) {
    final isTop = rank == 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(vertical: isTop ? 12 : 8, horizontal: isTop ? 10 : 4),
      decoration: isTop
          ? BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#$rank',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: isTop ? 13 : 12, color: isTop ? color : Colors.black45)),
          ),
          Expanded(
            child: Text(station,
                style: TextStyle(
                    fontSize: isTop ? 13 : 12, fontWeight: isTop ? FontWeight.bold : FontWeight.normal, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_formatNumber(avgRidership)}/day',
                  style: TextStyle(fontSize: isTop ? 13 : 12, fontWeight: FontWeight.bold, color: isTop ? color : Colors.black87)),
              const SizedBox(height: 1),
              Text('${vsNetworkAvg.toStringAsFixed(2)}× network average',
                  style: TextStyle(fontSize: 10, color: isTop ? color : Colors.black45)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompareStationsTab() {
    final dataA = _compareDataA;
    final dataB = _compareDataB;
    final canCompare = _compareStationA != null && _compareStationB != null;
    final sameStation = canCompare && _compareStationA == _compareStationB;
    final haveResults = dataA != null && dataB != null;
    final periodNeedsSelection = (_comparePeriod == _RankingPeriod.month && _compareMonth == null) ||
        (_comparePeriod == _RankingPeriod.day && _compareDay == null);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tab5ViewSwitch(),
          const SizedBox(height: 12),
          const Text('Compare Stations',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Compare average daily ridership between two stations.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: _sectionGap),

          _sectionCard(
            title: 'SELECT STATIONS',
            icon: Icons.compare_arrows,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StationSearchField(
                  label: 'Station A',
                  stations: _stations,
                  value: _compareStationA,
                  onChanged: (val) {
                    setState(() => _compareStationA = val);
                    _runCompare();
                  },
                ),
                const SizedBox(height: 12),
                StationSearchField(
                  label: 'Station B',
                  stations: _stations,
                  value: _compareStationB,
                  onChanged: (val) {
                    setState(() => _compareStationB = val);
                    _runCompare();
                  },
                ),
                const SizedBox(height: 14),
                _comparePeriodFilter(),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),

          if (!canCompare)
            _emptyState('Select Station A and Station B to compare their ridership.')
          else if (sameStation)
            _emptyState('Select two different stations to compare.')
          else if (periodNeedsSelection)
              _validationMessage(
                _comparePeriod == _RankingPeriod.month
                    ? 'Please select a month to compare these stations.'
                    : 'Please select a date to compare these stations.',
              )
            else ...[
                if (_loadingCompare && !haveResults) ...[
                  Row(
                    children: [
                      const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5))),
                      const SizedBox(width: 10),
                      const Text('Loading comparison…', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: _sectionGap),
                ],

                if (_compareError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(_sectionCardPadding),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(_sectionCardRadius),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Text(_compareError!, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  ),
                  const SizedBox(height: _sectionGap),
                ],

                if (haveResults) ...[

                  _sectionCard(
                    title: 'AVERAGE DAILY RIDERSHIP',
                    icon: Icons.bar_chart,
                    child: _compareAverageSection(dataA, dataB),
                  ),
                  const SizedBox(height: _sectionGap),

                  _sectionCard(
                    title: 'RIDERSHIP COMPARISON',
                    icon: Icons.stacked_bar_chart,
                    child: _compareBarChart(dataA, dataB),
                  ),
                ] else if (!_loadingCompare)
                  _emptyState('No ridership records found for one or both stations in this period.'),
              ],
        ],
      ),
    );
  }

  Widget _comparePeriodFilter() {
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final months = _rankingAvailableMonths();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Overall'),
              selected: _comparePeriod == _RankingPeriod.overall,
              onSelected: (_) => _onComparePeriodChanged(_RankingPeriod.overall),
            ),
            ChoiceChip(
              label: const Text('Month'),
              selected: _comparePeriod == _RankingPeriod.month,
              onSelected: (_) => _onComparePeriodChanged(_RankingPeriod.month),
            ),
            ChoiceChip(
              label: const Text('Day'),
              selected: _comparePeriod == _RankingPeriod.day,
              onSelected: (_) => _onComparePeriodChanged(_RankingPeriod.day),
            ),
          ],
        ),
        if (_comparePeriod == _RankingPeriod.month) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<DateTime>(
            value: _compareMonth,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'Select month',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: months
                .map((m) => DropdownMenuItem(value: m, child: Text('${monthNames[m.month - 1]} ${m.year}')))
                .toList(),
            onChanged: _onCompareMonthChanged,
          ),
        ],
        if (_comparePeriod == _RankingPeriod.day) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickCompareDay,
            icon: const Icon(Icons.calendar_today, size: 15),
            label: Text(_compareDay != null ? DateFormat('d MMM yyyy').format(_compareDay!) : 'Select a date'),
          ),
        ],
      ],
    );
  }

  Widget _compareAverageSection(_StationRidershipRow a, _StationRidershipRow b) {

    Color colorA = Colors.blueGrey;
    Color colorB = Colors.blueGrey;
    if (a.avgRidership != b.avgRidership) {
      colorA = a.avgRidership > b.avgRidership ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
      colorB = a.avgRidership > b.avgRidership ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    }
    final diff = a.avgRidership - b.avgRidership;

    final lowerAvg = diff >= 0 ? b.avgRidership : a.avgRidership;
    final diffPct = lowerAvg > 0 ? (diff.abs() / lowerAvg * 100) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _compareStatBlock(a.station, a.avgRidership, colorA)),
            Container(
              width: 1,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: Colors.grey.withValues(alpha: 0.2),
            ),
            Expanded(child: _compareStatBlock(b.station, b.avgRidership, colorB)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: diff.abs() < 0.5
              ? const Text(
            'Ridership Difference: 0/day (0.0%, essentially tied)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
          )
              : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ridership Difference: ${_formatNumber(diff.abs())}/day',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 2),

              Text(
                '${a.station} is ${diffPct.toStringAsFixed(1)}% ${diff > 0 ? 'higher' : 'lower'}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: diff > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compareStatBlock(String station, double avgRidership, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(station,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text('${_formatNumber(avgRidership)}/day',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _compareBarChart(_StationRidershipRow a, _StationRidershipRow b) {
    final maxAvg = a.avgRidership >= b.avgRidership ? a.avgRidership : b.avgRidership;
    Color colorA = Colors.blueGrey;
    Color colorB = Colors.blueGrey;
    if (a.avgRidership != b.avgRidership) {
      colorA = a.avgRidership > b.avgRidership ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
      colorB = a.avgRidership > b.avgRidership ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _compareBarRow(a.station, a.avgRidership, maxAvg, color: colorA),
        const SizedBox(height: 14),
        _compareBarRow(b.station, b.avgRidership, maxAvg, color: colorB),
      ],
    );
  }

  Widget _compareBarRow(String station, double avg, double maxAvg, {required Color color}) {
    final factor = maxAvg == 0 ? 0.0 : avg / maxAvg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          station,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 14,
                decoration:
                BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: factor.clamp(0.03, 1.0),
                  child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: Text(
                '${_formatNumber(avg)}/day',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
      ],
    );
  }

}