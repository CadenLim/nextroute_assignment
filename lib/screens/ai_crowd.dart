import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

// Period filter modes for the Station Ridership Ranking tab (Tab 5).
enum _RankingPeriod { overall, month, day }

// Which sub-page of Tab 5 is showing: the existing Station Ranking view,
// or the new Compare Stations view.
enum _Tab5View { ranking, compare }

// Shape of one row returned by ApiService.getStationRidershipTotals() —
// named here just so the Compare Stations fields below don't have to
// repeat the full anonymous record type. Structurally identical to what
// _rankingData already uses.
typedef _StationRidershipRow = ({
String station,
double avgRidership,
int totalRidership,
int recordCount,
DateTime? minDate,
DateTime? maxDate,
});

// Shape returned by _computeWeekdayWeekendComparison() for the History tab's
// Weekday vs Weekend comparison. Averages are nullable because a given
// month filter may genuinely contain zero weekday or zero weekend records
// (e.g. a single-day selection) — null means "no real records for this
// group", never a hardcoded/assumed 0.
typedef _WeekdayWeekendStats = ({
double? weekdayAvg,
double? weekendAvg,
int weekdayCount,
int weekendCount,
});

// One day-cell in the Calendar Heatmap for a given month. `ridership` is
// null when the local dataset has no record for that date — the heatmap
// must render that as visibly empty, never as a real 0.
typedef _HeatmapDayCell = ({int day, DateTime date, double? ridership});

// The currently tapped/selected day in the Calendar Heatmap, shown in the
// detail line below the grid. `ridership` mirrors _HeatmapDayCell: null
// means "no record for this date", not zero ridership.
typedef _HeatmapSelection = ({DateTime date, double? ridership});

// ── Monthly Ridership Trend line chart painter ─────────────────────────────
// Draws a simple polyline + point markers across evenly-spaced month slots.
// Pure presentation: takes the real per-month averages already computed by
// _computeMonthlyTrend() and just plots them — no modelling, no synthetic
// points. The highest/lowest indices get the same purple/red highlight
// colors used by the Daily Totals and Weekly Pattern charts elsewhere in
// this tab, for visual consistency.
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
      final color = isHighest
          ? const Color(0xFF4F46E5) // highest — purple, matches other History charts
          : isLowest
          ? const Color(0xFFDC2626) // lowest — red, matches other History charts
          : Colors.blueGrey;
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

// ── Type-to-search station picker ────────────────────────────────────────
// Drop-in replacement for DropdownButtonFormField<String> when the list of
// choices is long (station names). Lets the user either tap and scroll a
// list, or start typing to filter it, while looking like a normal form
// field. Built on Flutter's built-in Autocomplete widget (no extra
// packages required).
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
    // Keying on the *selected* value (not on keystrokes) means the field
    // remounts with the right initial text whenever the selection changes
    // programmatically (e.g. once stations finish loading), but stays put
    // — preserving whatever the user is currently typing — while they're
    // filtering the list.
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

// ── Crowd levels & rule-based prediction ────────────────────────────────────
// This is NOT a trained ML model. It is a transparent, rule-based estimator:
//   1. REAL: the station's historical average ridership for the selected
//      day-of-week, computed directly from the "A0: All Stations" rows.
//   2. MODELLED (documented assumption): a typical urban-rail intraday shape
//      (rush-hour bumps etc.), since the open dataset only has daily totals,
//      not hourly ones. Stated clearly in the UI and in the report.
// The Connections tab below uses NO modelling at all — it's pure real O-D
// data, filtered/grouped/summed/sorted.

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
  final int occupancy; // 0-100, a relative "capacity used" indicator
  CrowdResult(this.level, this.occupancy);
}

// ── Time-of-day category (display-only; does not affect the prediction) ────
// A labelling layer over the existing exact time selection, matching the
// bucket boundaries requested for the UI. Purely descriptive.
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

/// Maps a time-of-day (minutes since midnight) to its display category.
/// This is purely descriptive for the UI — the underlying prediction in
/// [predictCrowd] uses its own finer-grained rule table and is unaffected.
TimeCategory timeCategoryFor(int minutesOfDay) {
  final h = minutesOfDay / 60.0;
  if (h >= 6.0 && h < 7.0) return TimeCategory.earlyMorning;
  if (h >= 7.0 && h < 9.0) return TimeCategory.morningPeak;
  if (h >= 9.0 && h < 17.0) return TimeCategory.midday;
  if (h >= 17.0 && h < 19.5) return TimeCategory.eveningPeak;
  return TimeCategory.night; // 19:30–23:59 and 00:00–06:00
}

const List<String> kWeekdayLabels = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

// Rule-based intraday demand profile.
// Time-of-day boundaries are informed by Rapid KL's published
// operating hours (6am-12am) and weekday rush hours
// (7am-9am and 5pm-7pm).
// See: https://myrapid.com.my/resources/faqs/
//
// Exact baseline values are modelling assumptions.
// They are not directly derived from the dataset because
// the available dataset contains daily ridership totals,
// not hourly ridership data.
//
// Only ever called for times within operating hours (06:00-23:59) —
// times before 06:00 are blocked in the Crowd Prediction UI before this
// function is reached, so there is no pre-6AM bucket here.
int _baselineOccupancy(int weekday, int minutesOfDay) {
  final isWeekend =
      weekday == DateTime.saturday || weekday == DateTime.sunday;
  final h = minutesOfDay / 60.0;
  // Weekend: flatter demand pattern without strong commuter peaks
  if (isWeekend) {
    if (h < 9.0) return 15;
    if (h < 12.0) return 25;
    if (h < 15.0) return 32;
    if (h < 18.0) return 38;
    if (h < 20.0) return 35;
    if (h < 22.0) return 25;
    return 15;
  }
  // Weekday morning rush hour: 07:00–09:00
  if (h < 7.0) return 15;
  if (h < 7.5) return 35;
  if (h < 8.0) return 55;
  if (h < 8.5) return 70;
  if (h < 9.0) return 65;
  // Weekday daytime / non-peak
  if (h < 12.0) return 45;
  if (h < 15.0) return 42;
  if (h < 17.0) return 45;
  // Weekday evening rush hour: 17:00–19:00
  if (h < 17.5) return 55;
  if (h < 18.0) return 65;
  if (h < 19.0) return 75;
  // Evening / night
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

// ── Screen ───────────────────────────────────────────────────────────────

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

  // ── Tab 1: Crowd Estimate state ──
  String? _station;
  int? _weekday; // null until the user picks a day — no default selection
  TimeOfDay? _time; // null until the user picks a time — no default selection
  CrowdResult? _crowdResult;
  double? _crowdResultDayAvg;
  double? _crowdResultFactor;
  int? _crowdResultRecordCount;
  String? _crowdValidationMsg; // shown when Predict is pressed with fields missing

  // ── Tab 2: Peak Hours state ──
  String? _peakStation;
  int? _peakWeekday; // null until the user picks a day — no default selection
  List<MapEntry<int, CrowdResult>>? _peakSlots;
  double? _peakDayAvg;
  double? _peakFactor;
  String? _peakValidationMsg; // shown when Show Peak Pattern is pressed with fields missing

  // ── Tab 3: Ridership History state ──
  String? _historyStation;
  List<RidershipRecord>? _historyData;
  DateTime? _historyMonthFilter; // null = show all months
  String? _historyValidationMsg; // shown when Load History is pressed with no station

  // Calendar Heatmap (still Tab 3 / History) — when the History Filters
  // month is "All months" the grid shows one month at a time, stepped
  // with left/right arrows via this index into that station's available
  // months. When a specific month is selected in History Filters, that
  // month is shown directly and the arrows are hidden.
  int? _heatmapAllMonthsIndex;
  _HeatmapSelection? _heatmapSelectedDay; // last tapped day, null until tapped

  // ── Tab 4: Connections (O-D) state ──
  String? _connStation;
  List<MapEntry<String, int>>? _connTopDestinations;
  List<MapEntry<String, int>>? _connTopOrigins;
  int? _connOutgoing;
  int? _connIncoming;
  List<MapEntry<String, int>>? _connBusiestNetwork;
  bool _loadingConnections = false;
  String? _connValidationMsg; // shown when Show Connections is pressed with no station

  // ── Tab 5: Station Crowd Ranking state ──
  // Real per-station ridership from Supabase's "station_ridership_totals"
  // view (Overall) or the station_ridership_totals_for_range() function
  // (Month/Day) — one grouped query for every station, no hardcoded
  // ridership, no modelling.
  bool _loadingRanking = false;
  String? _rankingError;
  List<({String station, double avgRidership, int totalRidership, int recordCount, DateTime? minDate, DateTime? maxDate})>?
  _rankingData;
  _RankingPeriod _rankingPeriod = _RankingPeriod.overall;
  DateTime? _rankingMonth; // first-of-month, set when _rankingPeriod == month
  DateTime? _rankingDay; // set when _rankingPeriod == day
  // The dataset's true earliest/latest date, captured once from the first
  // Overall (unfiltered) load — used only to bound the Month/Day pickers,
  // never overwritten by a later Month/Day fetch's narrower range.
  DateTime? _rankingDatasetMinDate;
  DateTime? _rankingDatasetMaxDate;

  // Which sub-page of Tab 5 is currently shown.
  _Tab5View _tab5View = _Tab5View.ranking;

  // ── Tab 5: Compare Stations state ──
  // Same underlying query as Station Ranking
  // (_api.getStationRidershipTotals — real per-station averages from
  // Supabase, no hardcoded ridership); this view just reads off the two
  // selected stations' rows instead of listing every station.
  String? _compareStationA;
  String? _compareStationB;
  _RankingPeriod _comparePeriod = _RankingPeriod.overall;
  DateTime? _compareMonth;
  DateTime? _compareDay;
  bool _loadingCompare = false;
  String? _compareError;
  _StationRidershipRow? _compareDataA;
  _StationRidershipRow? _compareDataB;

  // ── Shared visual-hierarchy tokens (all four tabs) ──
  // Single source of truth for section spacing/padding/radius, so the
  // Crowd, Peak, History and Connections tabs all read as the same
  // design language. Presentation-only — no calculation or query logic
  // lives here.
  static const double _sectionGap = 20.0;
  static const double _sectionCardPadding = 16.0;
  static const double _sectionCardRadius = 12.0;

  @override
  void initState() {
    super.initState();
    _loadData();
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
        // No auto-selected station — Crowd, Peak, Connections, and History
        // all start with an empty "Select Station" field, same as
        // Ranking/Compare, so the user always makes an explicit choice.
        _statsReady = stations.isNotEmpty;
        if (stations.isEmpty) _loadError = 'No station records found in the local dataset.';
      });
      // Kick off the Station Crowd Ranking fetch in the background, a
      // short beat after the essential startup data has loaded — not
      // immediately alongside it. Even with the ridership indexes in
      // place, firing this alongside your other tabs' own startup queries
      // (Journey, Stations, Profile, Analytics likely all fetch on app
      // open too) can still exhaust Supabase's connection pool for a
      // moment and trip a statement timeout (57014). This delay lets the
      // initial burst of app-wide startup queries clear first.
      if (stations.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _runStationRanking();
        });
      }
    } catch (e) {
      if (!mounted) return;
      // A statement timeout at app-startup is usually transient (a burst
      // of concurrent queries across the app's tabs, not a real outage),
      // so retry automatically a couple of times with backoff before
      // surfacing an error the user has to manually retry. Non-timeout
      // errors (bad config, RLS block, etc.) fail immediately instead —
      // retrying those would just waste time on something that won't fix
      // itself.
      final isTimeout = e.toString().contains('57014') || e.toString().contains('statement timeout');
      if (isTimeout && attempt < 2) {
        await Future.delayed(Duration(milliseconds: 1000 * (attempt + 1)));
        if (!mounted) return;
        return _loadData(attempt: attempt + 1);
      }
      // Shows the real exception instead of a canned message, so you can
      // see exactly what Supabase/PostgREST is complaining about (missing
      // view, RLS block, not-initialized client, etc.) rather than
      // guessing from a generic string.
      setState(() => _loadError = 'Could not load ridership data from Supabase:\n$e');
    }
  }

  double _magnitudeFactor(double dayAvg) {
    final ratio = dayAvg / _networkAverage;
    return ratio.clamp(0.4, 1.8);
  }

  // Describes the existing Relative Station Factor in words. Purely
  // presentational — does not affect the factor or occupancy calculation.
  // This reflects the STATION's historical ridership vs the network
  // average — it is unrelated to the predicted occupancy % shown above it.
  (String, Color, IconData) _demandInterpretation(double factor) {
    if (factor > 1.05) {
      return ('Above Network Average', Colors.red.shade700, Icons.trending_up);
    } else if (factor < 0.95) {
      return ('Below Network Average', Colors.green.shade700, Icons.trending_down);
    }
    return ('Around Network Average', Colors.blueGrey, Icons.trending_flat);
  }

  // Ridership Trend (Tab 3): compares the average of the more recent half
  // of the currently-filtered records against the average of the earlier
  // half. Purely derived from whatever real records are on screen after
  // the month/day-of-week filters are applied — no modelling, no fixed
  // window length, no hardcoded ridership figures. Assumes `records` is
  // already in chronological (ascending date) order, matching how
  // _historyData is loaded and rendered elsewhere in this tab.
  ({double currentAvg, double previousAvg, double percentChange})? _computeRidershipTrend(
      List<RidershipRecord> records) {
    if (records.length < 2) return null; // not enough real data to compare two periods
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

  // Describes the trend above in words, mirroring the tone/threshold style
  // of _demandInterpretation. Presentational only — does not alter the
  // underlying averages or % change.
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

  // Weekly Ridership Pattern (Tab 3): groups whatever real records are
  // currently on screen (month-filtered) by day-of-week and averages the
  // real ridership for each day. Purely derived from actual records — no
  // modelling, no fixed/hardcoded ridership figures. Days
  // with no records in the current month filter simply don't appear.
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

  // Weekday vs Weekend comparison (Tab 3 / History, still inside the
  // Weekly Ridership Pattern section). Fed the same `byMonth` records as
  // _computeWeeklyPattern above — respects the month filter, deliberately
  // ignores the day-of-week filter (that filter narrows to a single day,
  // which would make a weekday-vs-weekend comparison meaningless). Real
  // data only: Monday–Friday records average into weekdayAvg, Saturday–
  // Sunday records average into weekendAvg, no modelling or fixed values.
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

  // Monthly Ridership Trend (Tab 3 / History): groups ALL of the loaded
  // station's real records by calendar month and averages the real
  // ridership within each month. Deliberately fed `_historyData` directly
  // (not the month-filtered `byMonth` used elsewhere in this tab) since
  // this chart's whole purpose is to show every available month for the
  // selected station side by side — the existing month filter is not
  // applied here by design. Still respects the station filter, since
  // `_historyData` is already scoped to whichever station was loaded.
  // Real data only — no modelling, no fixed/hardcoded ridership figures.
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

  // Describes the weekly pattern above in words — names the real
  // highest/lowest average day. Presentational only.
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

  // Rapid KL rail services operate 6:00 AM to 12:00 AM (midnight) per the
  // official FAQ (see _baselineOccupancy comment). Times before 6:00 AM
  // are outside operating hours, so no crowd prediction is offered for
  // them — this only gates the Crowd Prediction tab's UI/flow; it does
  // not touch any calculation or dataset value.
  bool get _isOutsideOperatingHours => _time != null && _time!.hour < 6;

  Future<void> _runCrowdEstimate() async {
    final station = _station;
    final weekday = _weekday;
    final time = _time;
    // Required-field validation: never fall back to a default day/time —
    // if anything's missing, tell the user and stop, without calculating.
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
      return; // no service — nothing to predict
    }
    final dayAvg = await _api.getStationAverageForWeekday(station!, weekday!);
    // Reuses the same daily-totals lookup that getStationAverageForWeekday
    // is built on, just to expose how many real records fed that average.
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

  // Joins a list of missing-field descriptions into a natural-language
  // phrase, e.g. ["a station", "a day"] -> "a station and a day".
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
    // Sample hours chosen to reflect Rapid KL's actual operating pattern:
    // service runs 06:00–24:00 (00:00–06:00 excluded, matching Tab 1's
    // _isOutsideOperatingHours cutoff), with the morning rush (07:00–09:00)
    // and evening rush (17:00–19:30) given denser coverage since that's
    // when demand swings the most, plus a couple of midday samples for
    // off-peak contrast.
    final hours = [6, 7, 8, 9, 12, 15, 17, 18, 19];
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
      _historyMonthFilter = null; // reset filter on fresh load
      _heatmapSelectedDay = null; // clear any previously tapped day
      _heatmapAllMonthsIndex = null; // reset calendar navigation on fresh load
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
    });
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
  }

  // Station Crowd Ranking (Tab 5): a single query to the
  // "station_ridership_totals" Supabase view (Overall) or the
  // station_ridership_totals_for_range() function (Month/Day), which
  // compute real average/total ridership per station with a GROUP BY
  // directly in Postgres. One round-trip for all stations — no
  // per-station looping, no batching, no modelling, no hardcoded
  // ridership.
  //
  // forceRefresh: true bypasses ApiService's in-memory cache for the
  // Overall case so a manual re-pull actually re-queries Supabase instead
  // of just re-showing the same cached numbers. Month/Day fetches are
  // never cached, since the range changes with the user's selection.
  Future<void> _runStationRanking({bool forceRefresh = false}) async {
    if (_loadingRanking) return;

    // Resolve the selected period into a concrete date range. If Month or
    // Day is selected but nothing's been picked yet, wait for that pick
    // instead of fetching — the picker's onChanged calls this again once
    // a value is chosen.
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
      // Capture the dataset's true earliest/latest date once, from the
      // first Overall (unfiltered) load — this bounds the Month/Day
      // pickers and must not get overwritten by a later, narrower
      // Month/Day fetch's own min/max.
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

  // Every calendar month between the dataset's earliest and latest date
  // (inclusive) — populates the Month dropdown. Real data range only, not
  // a fixed/hardcoded list.
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
      // Month/Day with nothing picked yet must not keep showing results
      // from whatever period was previously active — clear them and wait
      // for the picker instead of displaying stale data.
      final needsSelection = (period == _RankingPeriod.month && _rankingMonth == null) ||
          (period == _RankingPeriod.day && _rankingDay == null);
      if (needsSelection) {
        _rankingData = null;
        _rankingError = null;
      }
    });
    // Overall and an already-picked Month/Day can fetch immediately;
    // Month/Day with nothing picked yet just wait for the picker.
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

  // ── Tab 5: Compare Stations ──
  // Reuses the same "station_ridership_totals" query as the Ranking view
  // (Overall) / station_ridership_totals_for_range() (Month/Day) — one
  // real, grouped Supabase query for every station — and simply reads off
  // the two selected stations' rows. No separate endpoint, no per-station
  // looping, no hardcoded ridership.
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
      // Month/Day with nothing picked yet must not keep showing results
      // from whatever period was previously active.
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

  // ── Shared section-card building blocks (used by all four tabs) ────────
  // Presentation-only helpers: consistent heading style, card padding,
  // corner radius, and spacing so Crowd / Peak / History / Connections all
  // read as the same design language. None of these touch data, queries,
  // or calculations — they only lay out whatever child widget is passed in.

  // Consistent section heading: small label + optional icon + optional
  // italic subtitle.
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

  // Consistent section card wrapper: same padding/radius/border for every
  // section on every tab, so each page reads as clearly separated blocks
  // instead of one long scroll of mixed content.
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

  // Consistent empty-state row: used instead of leaving a section blank
  // when there's genuinely nothing to show.
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

  // Consistent "please complete required fields" warning: shown instead
  // of calculating or displaying results when a required input is
  // missing. Never fills the gap with a default value — only tells the
  // user what to pick.
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

  // ── Tab 1 UI ───────────────────────────────────────────────────────────

  // Sections (mirrors the Connections tab pattern):
  //   A. Station & prediction inputs
  //   B. Crowd prediction summary
  //   C. Station Demand Profile
  //   D. Crowd alert insight
  //   E. Calculation Breakdown
  // (plus the existing methodology/legend reference cards at the bottom)
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

          // A. Station & prediction inputs
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

            // B. Crowd prediction summary
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

            // C. Station Demand Profile
            _sectionCard(
              title: 'STATION DEMAND PROFILE',
              icon: Icons.insights_outlined,
              child: _buildStationDemandProfile(),
            ),
            const SizedBox(height: _sectionGap),

            // D. Calculation Breakdown — collapsed by default; expand to
            // see the step-by-step math behind the estimate.
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

  // ── Calculation breakdown / methodology / legend (explainability) ──────

  // "How is this estimated?" — collapsed by default. Wraps the existing
  // step-by-step breakdown in a tappable, expandable card so it stays out
  // of the way until someone wants to see the math.
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
        // Formula summary, always visible at a glance.
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

  // Station Demand Profile — describes the station's real historical
  // ridership relative to the network average (the existing Relative
  // Station Factor). Deliberately separate from the occupancy result
  // above it, since this reflects the STATION's typical demand level,
  // not the predicted occupancy for the selected time.
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

  // ── Tab 2 UI ───────────────────────────────────────────────────────────

  // Sections (mirrors the Connections tab pattern):
  //   A. Station & day selection
  //   B. Peak Pattern
  //   C. Peak Analysis Summary
  //   D. Top 3 Predicted Time Periods
  //   E. Peak vs Off-Peak Comparison
  //   F. Data Source / Method
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

          // A. Station & day selection
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

            // B. Peak Pattern
            _sectionCard(
              title: 'MODELLED PEAK PATTERN',
              icon: Icons.show_chart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 176,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _peakSlots!.map((entry) {
                        final hour = entry.key;
                        final result = entry.value;
                        final label = hour == 12 ? '12pm' : hour > 12 ? '${hour - 12}pm' : '${hour}am';
                        return _buildTrendBar(label, result.occupancy / 100, result.level.color,
                            tooltip: '$label: ${result.occupancy}% (${result.level.label})',
                            valueLabel: '${result.occupancy}%');
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _sectionGap),

            // C. Peak Analysis Summary
            _sectionCard(
              title: 'PEAK ANALYSIS SUMMARY',
              icon: Icons.summarize_outlined,
              child: _buildPeakSummaryCard(),
            ),
            const SizedBox(height: _sectionGap),

            // D. Top 3 Predicted Time Periods
            _sectionCard(
              title: 'TOP 3 PREDICTED TIME PERIODS',
              icon: Icons.leaderboard_outlined,
              child: _buildTopPeakPeriods(),
            ),
            const SizedBox(height: _sectionGap),

            // E. Peak vs Off-Peak Comparison
            _sectionCard(
              title: 'PEAK VS OFF-PEAK COMPARISON',
              icon: Icons.compare_arrows,
              child: _buildPeakVsOffPeak(),
            ),
            const SizedBox(height: _sectionGap),

            // F. How is this estimated? — collapsed by default.
            _buildPeakMethodologyCard(),
          ],
        ],
      ),
    );
  }

  String _hourLabel(int hour) =>
      hour == 12 ? '12pm' : hour > 12 ? '${hour - 12}pm' : hour == 0 ? '12am' : '${hour}am';

  // Peak Analysis Summary — all values reused directly from _peakSlots,
  // _peakDayAvg and _peakFactor. No new calculation performed here.
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

  // Top 3 Predicted Time Periods — sorted from the existing _peakSlots list.
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

  // Peak vs Off-Peak Comparison — derived only from existing _peakSlots values.
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

  // "How is this estimated?" — collapsed by default, mirroring the same
  // pattern used on the Crowd Estimate tab. Wraps the existing data
  // source / methodology explanation so it stays out of the way until
  // someone wants to read it.
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
        // Formula summary, always visible at a glance.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.2)),
          ),
          child: const Text(
            'Estimated crowd = time-of-day baseline × network comparison',
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
          title: 'Time-of-day baseline, per sampled hour',
          lines: [
            'Each hour has its own fixed rule-based baseline % — weekday and weekend patterns differ. '
                'The one for $dayLabel is multiplied by the ${factor.toStringAsFixed(2)}x factor above to '
                'get the final estimate shown in the chart.',
          ],
          isLast: true,
        ),
        const SizedBox(height: 10),
        _buildPeakBaselineTable(),
        const SizedBox(height: 10),
        const Text(
          'These are modelled peak estimates, not observed hourly ridership — the source dataset only '
              'records daily totals, so the hourly baseline shape is a rule-based assumption informed by '
              'Rapid KL\'s published operating hours and rush-hour windows, not measured hourly data.',
          style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  // Table of the actual rule-based baseline % used for each sampled hour
  // (before the network-comparison factor is applied), next to the final
  // occupancy % shown in the chart. Values are read straight from
  // _baselineOccupancy() and the existing _peakSlots — nothing new computed.
  // _baselineOccupancy only branches on weekday-vs-weekend (not per specific
  // weekday), so "Monday" stands in for any weekday and "Saturday" for any
  // weekend day when computing the reference columns below.
  Widget _buildPeakBaselineTable() {
    final weekday = _peakWeekday!;
    final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;
    final accent = const Color(0xFF4F46E5);
    TextStyle colStyle(bool selected) => TextStyle(
        fontSize: 12,
        color: selected ? accent : Colors.black45,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal);

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
                  child: Text('Final',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54))),
            ],
          ),
          const Divider(height: 10),
          ..._peakSlots!.map((entry) {
            final hour = entry.key;
            final weekdayBaseline = _baselineOccupancy(DateTime.monday, hour * 60);
            final weekendBaseline = _baselineOccupancy(DateTime.saturday, hour * 60);
            final result = entry.value;
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
                      child: Text('${result.occupancy}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: result.level.color))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTrendBar(String label, double heightFactor, Color color, {String? tooltip, String? valueLabel}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (valueLabel != null) ...[
          Text(valueLabel,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
        ],
        Tooltip(
          message: tooltip ?? label,
          waitDuration: const Duration(milliseconds: 200),
          child: Container(
            width: 22,
            height: 90 * heightFactor.clamp(0.05, 1.0),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Tab 3 UI ───────────────────────────────────────────────────────────

  // Sections (mirrors the Connections tab pattern):
  //   A. Station selection
  //   B. History filters (month only)
  //   C. Summary statistics (Average / Highest / Lowest)
  //   D. Ridership Trend & Insight (trend stats + plain-language read, one card)
  //   E. Calendar Heatmap (daily ridership by date, month from History Filters)
  //   F. Weekly Ridership Pattern (Monday–Sunday averages, + Weekday vs Weekend)
  //   G. Monthly Ridership Trend (all months for the station, line chart)
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
            'Real daily ridership totals from the local dataset — no modelling here.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: _sectionGap),

          // A. Station selection
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
              // Distinct months present in the loaded data, sorted chronologically.
              final months = _historyData!
                  .map((e) => DateTime(e.date.year, e.date.month))
                  .toSet()
                  .toList()
                ..sort();

              // Apply the month filter (null = show everything).
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

              // B. History filters — month only. Always shown once data is
              // loaded, so the filter stays visible even if it currently
              // yields no records.
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

              // Weekly Ridership Pattern data — grouped by day-of-week from
              // `byMonth` (respects the month filter). Real data only, no
              // modelling.
              final weeklyPattern = _computeWeeklyPattern(byMonth);
              // Same `byMonth` (month-filtered) records feed the Weekday
              // vs Weekend comparison below.
              final weekdayWeekendStats = _computeWeekdayWeekendComparison(byMonth);
              final weeklyPatternSection =
              _buildWeeklyPatternSection(weeklyPattern, weekdayWeekendStats);

              // Monthly Ridership Trend — fed the full `_historyData` for
              // this station, NOT `byMonth`, so it always shows every
              // available month regardless of the month filter above.
              final monthlyTrend = _computeMonthlyTrend(_historyData!);
              final monthlyTrendSection = _buildMonthlyTrendSection(monthlyTrend);

              // Calendar Heatmap — when a specific month is chosen in
              // History Filters, the calendar shows that month directly
              // and hides the nav arrows. When History Filters is "All
              // months", the calendar can still only show one month at a
              // time, so it shows one month at a time with its own
              // left/right arrows to step through every available month
              // (no separate filter dropdown inside the calendar itself).
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

                  // C. Summary statistics (Average / Highest / Lowest)
                  _sectionCard(
                    title: 'SUMMARY STATISTICS',
                    icon: Icons.query_stats_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _statCard('AVERAGE', avg.round().toString())),
                            const SizedBox(width: 10),
                            Expanded(child: _statCard('HIGHEST', maxRecord.ridership.toString(),
                                subtitle: '${maxRecord.date.day}/${maxRecord.date.month}/${maxRecord.date.year}')),
                            const SizedBox(width: 10),
                            Expanded(child: _statCard('LOWEST', minRecord.ridership.toString(),
                                subtitle: '${minRecord.date.day}/${minRecord.date.month}/${minRecord.date.year}')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Most recent on file: ${latest.date.day}/${latest.date.month}/${latest.date.year} — ${latest.ridership} trips.',
                          style: const TextStyle(fontSize: 11, color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _sectionGap),

                  // D. Ridership Trend & Insight — one card: the trend
                  // stats (current-period vs previous-period average,
                  // computed by splitting the currently-shown real records
                  // in half chronologically) plus a short plain-language
                  // interpretation of that same trend underneath. No
                  // modelling, no fixed calendar window.
                  _sectionCard(
                    title: 'RIDERSHIP TREND',
                    icon: Icons.trending_up,
                    child: trend == null
                        ? _emptyState('Need at least 2 records in the current filter to compute a trend.')
                        : Builder(builder: (context) {
                      final (message, color, icon) = _ridershipInsight(trend);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: _statCard('PREVIOUS PERIOD AVG',
                                      trend.previousAvg.round().toString())),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _statCard('CURRENT PERIOD AVG',
                                      trend.currentAvg.round().toString())),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _statCard('% CHANGE',
                                      '${trend.percentChange >= 0 ? '+' : ''}${trend.percentChange.toStringAsFixed(1)}%')),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Based on the ${byMonth.length} record(s) currently shown, split chronologically into two equal halves.',
                            style: const TextStyle(fontSize: 11, color: Colors.black45),
                          ),
                          const SizedBox(height: 12),
                          // Ridership Insight — plain-language read of the
                          // trend above, kept in the same card.
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

                  // E. Calendar Heatmap (daily ridership by date, month from History Filters)
                  heatmapSection,
                  const SizedBox(height: _sectionGap),

                  // F. Weekly Ridership Pattern (Monday–Sunday averages, + Weekday vs Weekend)
                  weeklyPatternSection,
                  const SizedBox(height: _sectionGap),

                  // G. Monthly Ridership Trend (all months for this station)
                  monthlyTrendSection,
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  // Weekly Ridership Pattern section card (Tab 3 / History). Renders one
  // bar per day-of-week present in the real, month-filtered data, with the
  // highest/lowest day highlighted, plus a plain-language insight line.
  Widget _buildWeeklyPatternSection(List<({int weekday, double avg, int count})> pattern,
      _WeekdayWeekendStats weekdayWeekendStats) {
    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    final (message, color, icon) = _weeklyPatternInsight(pattern);

    if (pattern.isEmpty) {
      return _sectionCard(
        title: 'WEEKLY RIDERSHIP PATTERN',
        icon: Icons.calendar_view_week,
        subtitle: 'Average ridership by day of week, from real records for the selected month.',
        child: _emptyState('No records available to compute a weekly pattern.'),
      );
    }

    final sorted = [...pattern]..sort((a, b) => b.avg.compareTo(a.avg));
    final highest = sorted.first;
    final lowest = sorted.last;
    final maxAvg = highest.avg;

    return _sectionCard(
      title: 'WEEKLY RIDERSHIP PATTERN',
      icon: Icons.calendar_view_week,
      subtitle: 'Average ridership by day of week (Mon–Sun), from real records for the selected month.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...pattern.map((p) {
            final isMax = p.weekday == highest.weekday;
            final isMin = p.weekday == lowest.weekday && lowest.weekday != highest.weekday;
            final barColor = isMax
                ? const Color(0xFF4F46E5) // highest — purple, matches Daily Totals chart
                : isMin
                ? const Color(0xFFDC2626) // lowest — red, matches Daily Totals chart
                : Colors.blueGrey;
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
          _weekdayWeekendComparisonSection(weekdayWeekendStats),
        ],
      ),
    );
  }

  // Weekday (Mon–Fri) vs Weekend (Sat–Sun) comparison — sits inside the
  // same Weekly Ridership Pattern card as the day-of-week bars above, using
  // the same underlying real records (respects the month filter, ignores
  // the day-of-week filter). Shows both averages, the real difference and
  // percentage difference, plus a small bar chart. No hardcoded ridership.
  Widget _weekdayWeekendComparisonSection(_WeekdayWeekendStats stats) {
    const weekdayColor = Color(0xFF4F46E5);
    const weekendColor = Color(0xFF16A34A);

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
        const Text(
          'Monday–Friday vs Saturday–Sunday, from the same real records above for the selected month '
              '(not affected by the day-of-week filter).',
          style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 12),
      ],
    );

    // Genuinely no weekday or weekend records at all for this month filter
    // (e.g. neither group has data) — shouldn't normally happen since the
    // pattern above is non-empty, but handled defensively rather than
    // assuming/hardcoding a value.
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

    // Difference / percentage difference — only meaningful when both sides
    // actually have real data.
    Widget diffLine;
    if (weekdayAvg != null && weekendAvg != null) {
      final diff = weekdayAvg - weekendAvg;
      final higherLabel = diff >= 0 ? 'weekdays' : 'weekends';
      final lowerAvg = diff >= 0 ? weekendAvg : weekdayAvg;
      final diffPct = lowerAvg > 0 ? (diff.abs() / lowerAvg * 100) : 0.0;
      diffLine = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          diff.abs() < 0.5
              ? 'Difference: 0/day (0.0%, essentially tied)'
              : 'Difference: ${_formatNumber(diff.abs())}/day (${diffPct.toStringAsFixed(1)}% higher on $higherLabel)',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      );
    } else {
      // One side has no real records for the selected month — say so
      // rather than computing a difference against a missing value.
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

  // One bar in the Weekday vs Weekend chart — mirrors the styling of
  // _weekdayRow / _compareBarRow used elsewhere in this tab.
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

  // One day-of-week bar row for the Weekly Ridership Pattern section.
  // Mirrors the bar-with-value style already used by _connectionRow, with
  // an extra "Highest"/"Lowest" tag under the standout day(s).
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

  // Monthly Ridership Trend section card (Tab 3 / History). Plots the real
  // average daily ridership per calendar month for the selected station —
  // every month present in `_historyData`, unaffected by the month or
  // day-of-week filters used elsewhere in this tab. Also surfaces the
  // highest/lowest months and the overall % change from the first to the
  // last available month. Real data only — no modelling, nothing hardcoded.
  Widget _buildMonthlyTrendSection(List<({DateTime month, double avg, int count})> trend) {
    if (trend.isEmpty) {
      return _sectionCard(
        title: 'MONTHLY RIDERSHIP TREND',
        icon: Icons.show_chart,
        subtitle: 'Average daily ridership by month, from all real records for this station.',
        child: _emptyState('No records available to compute a monthly trend.'),
      );
    }

    final sorted = [...trend]..sort((a, b) => b.avg.compareTo(a.avg));
    final highest = sorted.first;
    final lowest = sorted.last;
    final highestIndex = trend.indexWhere((t) => t.month == highest.month);
    final lowestIndex = trend.indexWhere((t) => t.month == lowest.month);

    // Overall change: first available month's average vs the last
    // available month's average, in chronological order. Null (rather
    // than 0) when there's only one month of data — nothing to compare.
    double? overallChangePct;
    if (trend.length >= 2 && trend.first.avg != 0) {
      overallChangePct = ((trend.last.avg - trend.first.avg) / trend.first.avg) * 100;
    }
    final (changeMessage, changeColor, changeIcon) =
    _monthlyChangeInsight(overallChangePct, trend.first.month, trend.last.month);

    return _sectionCard(
      title: 'MONTHLY RIDERSHIP TREND',
      icon: Icons.show_chart,
      subtitle: 'Average daily ridership by month, from all real records for this station '
          '(not affected by the month filter).',
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
                  const Color(0xFF4F46E5),
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
                  const Color(0xFFDC2626),
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

  // Describes the overall month-to-month change in words. Mirrors the
  // tone/threshold style of _ridershipInsight for consistency (an increase
  // in ridership is flagged red as "more crowding", a decrease green).
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

  // The scrollable line-chart container for Monthly Ridership Trend: fixed
  // width per month so the chart and the month labels beneath it always
  // line up, scrolling horizontally when there are more months than fit
  // on screen (same visual language as the Daily Totals chart above it).
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
                    // Invisible hit-targets, one per month slot (same
                    // even division as the painter's own slotWidth), so
                    // hovering (desktop) or long-pressing (touch) a data
                    // point shows its exact month + real average via a
                    // Tooltip. Chart drawing/design above is unchanged.
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

  // ── Calendar Heatmap (Tab 3 / History) ──────────────────────────────────
  // Renders one calendar-style month grid where each real day-of-data gets
  // a filled cell whose color intensity reflects its real ridership value
  // (min–max scaled against the other real days in that same month — a
  // purely presentational scale, not a modelled or hardcoded one). Days
  // with no record in the local dataset render as empty/unfilled cells,
  // never as a ridership of 0. Reuses the History Filters month above —
  // no separate month control of its own, to avoid duplicate filters.

  // Builds the day cells for one calendar month: one entry per calendar
  // day in the month, `ridership` null where `_historyData` has no record
  // for that date.
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

  // Real min/max ridership among the days that actually have a record this
  // month — used only to scale color intensity, never displayed as if it
  // were itself a computed statistic. Null when the month has no records.
  (double, double)? _heatmapMinMax(List<_HeatmapDayCell> cells) {
    final values = cells.where((c) => c.ridership != null).map((c) => c.ridership!).toList();
    if (values.isEmpty) return null;
    return (values.reduce((a, b) => a < b ? a : b), values.reduce((a, b) => a > b ? a : b));
  }

  // Maps a real ridership value to a fill color: same indigo used
  // throughout this tab, with alpha scaled by where the value falls
  // between this month's real min and max. Empty days are handled by the
  // caller (they never reach this function with a null value).
  Color _heatmapColor(double value, (double, double) minMax) {
    final (minV, maxV) = minMax;
    final t = (maxV == minV) ? 1.0 : ((value - minV) / (maxV - minV)).clamp(0.0, 1.0);
    final alpha = 0.12 + t * 0.83;
    return const Color(0xFF4F46E5).withValues(alpha: alpha);
  }

  // `heatmapMonth` / `heatmapMonthLabel` come from the History Filters
  // month above (see the Builder in _buildHistoryTab). When History
  // Filters is a specific month, this section just displays it (no
  // arrows). When History Filters is "All months", this section shows
  // one month at a time and exposes its own left/right arrows
  // (`showArrows`/`canGoPrev`/`canGoNext`/`onPrev`/`onNext`) to step
  // through the station's available months — never a second dropdown
  // filter inside the calendar itself.
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
      subtitle: showArrows
          ? 'Daily ridership intensity from real records for this station. Tap a day for its exact '
          'figure. Use the arrows below to browse other months.'
          : 'Daily ridership intensity for $heatmapMonthLabel, from real records for this station. '
          'Tap a day for its exact figure. Uses the month selected in History Filters above.',
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

  // Mon–Sun header row above the calendar grid.
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

  // Lays the month's real day-cells out into a 7-wide calendar grid,
  // padding with blank leading/trailing slots so day 1 lands under the
  // correct weekday column (week starts Monday, matching the rest of the
  // app's day-of-week convention).
  Widget _heatmapGrid(List<_HeatmapDayCell> cells, (double, double) minMax) {
    final leading = cells.first.date.weekday - 1; // Monday=1 -> 0 leading blanks
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

  // One calendar cell. Tap shows the exact date + real ridership (or "no
  // record") in the detail line below the grid; a Tooltip gives the same
  // information on hover for desktop / long-press on touch devices. Days
  // with no record render with no fill at all — never a ridership of 0.
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

  // Low → high color-scale legend, plus the real min/max ridership that
  // scale is anchored to for this specific month.
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
                const Color(0xFF4F46E5).withValues(alpha: 0.12),
                const Color(0xFF4F46E5).withValues(alpha: 0.95),
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

  // ── Tab 4 UI ───────────────────────────────────────────────────────────
  //
  // Six visually distinct sections, each rendered with the shared
  // _sectionCard() helper defined above build():
  //   A. Station selection
  //   B. Connection summary
  //   C. Connection insight
  //   D. Top destinations
  //   E. Top origins
  //   F. Busiest network-wide connections

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
            'Real origin-destination trip counts — where riders actually travel to/from. Trip counts only, not routes.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: _sectionGap),

          // A. Station selection
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
              // B. Connection summary
              _sectionCard(
                title: 'CONNECTION SUMMARY',
                icon: Icons.swap_horiz,
                child: Row(
                  children: [
                    Expanded(child: _connectionSummaryCard('OUTGOING TRIPS', _connOutgoing ?? 0,
                        icon: Icons.north_east, color: const Color(0xFF4F46E5))),
                    const SizedBox(width: 12),
                    Expanded(child: _connectionSummaryCard('INCOMING TRIPS', _connIncoming ?? 0,
                        icon: Icons.south_west, color: const Color(0xFF16A34A))),
                  ],
                ),
              ),
              const SizedBox(height: _sectionGap),

              // C. Connection insight
              _sectionCard(
                title: 'CONNECTION INSIGHT',
                icon: Icons.insights,
                child: _connectionInsightCard(_connOutgoing ?? 0, _connIncoming ?? 0),
              ),
              const SizedBox(height: _sectionGap),

              // D. Top destinations
              _sectionCard(
                title: 'TOP DESTINATIONS',
                icon: Icons.north_east,
                subtitle: 'Top 5 destinations from ${_connStation ?? ''}',
                child: (_connTopDestinations!.isEmpty)
                    ? _emptyState('No recorded outgoing connections for this station.')
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _connTopDestinations!
                      .map((e) => _connectionRow(
                      e.key, e.value, _connTopDestinations!.first.value, const Color(0xFF4F46E5)))
                      .toList(),
                ),
              ),
              const SizedBox(height: _sectionGap),

              // E. Top origins
              _sectionCard(
                title: 'TOP ORIGINS',
                icon: Icons.south_west,
                subtitle: 'Top 5 origins to ${_connStation ?? ''}',
                child: ((_connTopOrigins ?? const []).isEmpty)
                    ? _emptyState('No recorded incoming connections for this station.')
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _connTopOrigins!
                      .map((e) => _connectionRow(
                      e.key, e.value, _connTopOrigins!.first.value, const Color(0xFF16A34A)))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: _sectionGap),

            // F. Busiest network-wide connections
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
                  return _busiestConnectionRow(rank, e.key, e.value);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Simple derived insight — no new data source, just incoming - outgoing
  // from the two totals already fetched for the summary cards above.
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

  Widget _busiestConnectionRow(int rank, String label, int trips) {
    final isTop = rank == 1;
    const accent = Color(0xFF4F46E5);
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

  // Adds thousands separators to a whole number, e.g. 708230 -> "708,230".
  // Purely a display helper — never touches the underlying numeric value.
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

  Widget _connectionRow(String stationName, int trips, int maxTrips, Color color) {
    final factor = maxTrips == 0 ? 0.0 : trips / maxTrips;
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

  Widget _statCard(String label, String value, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.black45)),
          ],
        ],
      ),
    );
  }

  // ── Tab 5 UI ───────────────────────────────────────────────────────────
  //
  // Station Ridership Ranking — real per-station ridership averages/totals
  // from the "station_ridership_totals" view (one grouped query for every
  // station). No hardcoded ridership, no modelling.
  // Sections (mirrors the other tabs' pattern):
  //   A. Load control
  //   B. Top 5 busiest stations
  //   C. Top 5 least-busy stations
  //   D. Ranking insight (busiest / least-busy station, in plain language)

  // Tab 5 has two sub-pages sharing one tab slot: Station Ranking (existing)
  // and Compare Stations (new). This just picks which one to render; the
  // toggle itself lives in _tab5ViewSwitch() and is rendered at the top of
  // each sub-page.
  Widget _buildTab5() {
    return _tab5View == _Tab5View.ranking ? _buildStationRankingTab() : _buildCompareStationsTab();
  }

  // Segmented-looking chip pair for switching between the two Tab 5
  // sub-pages. Uses the same ChoiceChip look as the period filters below,
  // so it reads as part of the existing UI rather than a new control.
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

  // Real earliest–latest date across every station's data (from the
  // min_date/max_date the ranking query already returns per station) —
  // shown as "Based on Jan–Mar 2026 data" when available. Not a fixed
  // label; simply not shown if the range isn't known yet.
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

  // Period filter row for the Ranking tab: Overall / Month / Day chips,
  // plus a compact month dropdown or date picker button underneath when
  // Month or Day is selected. Deliberately not wrapped in a section
  // card — just inline controls, per the tab's simplified layout.
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
          // Network average — a simple line, not a card. Real value from
          // Supabase's "network_average" view (same one the Crowd/Peak
          // tabs already use), which is also what every "× network
          // average" figure below is computed against.
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
              // Real "X.XX× network average" comparison — station avg ÷
              // _networkAverage, both sourced from Supabase. Guarded
              // against a zero network average rather than dividing by it.
              double vsNetworkAvg(double stationAvg) =>
                  _networkAverage > 0 ? stationAvg / _networkAverage : 0.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A. Top 5 busiest stations
                  _sectionCard(
                    title: 'TOP 5 BUSIEST STATIONS',
                    icon: Icons.trending_up,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: busiest.asMap().entries.map((entry) {
                        final rank = entry.key + 1;
                        final r = entry.value;
                        return _rankingRow(rank, r.station, r.avgRidership.round(), vsNetworkAvg(r.avgRidership), const Color(0xFF4F46E5));
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: _sectionGap),

                  // B. Top 5 least-busy stations
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

  // One ranked-station row for the Station Crowd Ranking tab. Mirrors
  // _busiestConnectionRow's rank/label/value layout and top-row highlight
  // treatment, with a ridership-per-day value plus a real "X.XX× network
  // avg" comparison underneath (station avg ÷ _networkAverage, both from
  // Supabase — no modelling, no hardcoded ridership).
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

  // ── Tab 5 UI: Compare Stations ──────────────────────────────────────────
  //
  // Real per-station ridership averages for two chosen stations, from the
  // same "station_ridership_totals" query the Ranking page uses. No new
  // data source, no hardcoded ridership.
  // Sections:
  //   A. Station A / Station B pickers + period filter (Overall/Month/Day)
  //   B. Average ridership for each + the ridership difference
  //   C. A simple comparison bar chart
  //   D. One-line insight comparing the two stations
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
            'See how two stations\' average ridership stacks up.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: _sectionGap),

          // A. Station pickers + period filter
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
                  // B. Average ridership + difference
                  _sectionCard(
                    title: 'AVERAGE DAILY RIDERSHIP',
                    icon: Icons.bar_chart,
                    child: _compareAverageSection(dataA, dataB),
                  ),
                  const SizedBox(height: _sectionGap),

                  // C. Simple comparison bar chart (reuses the same bar row
                  // style as the History tab's weekly pattern chart).
                  _sectionCard(
                    title: 'RIDERSHIP COMPARISON',
                    icon: Icons.stacked_bar_chart,
                    child: _compareBarChart(dataA, dataB),
                  ),
                  const SizedBox(height: _sectionGap),

                  // D. One-line insight
                  _compareInsightCard(dataA, dataB),
                ] else if (!_loadingCompare)
                  _emptyState('No ridership records found for one or both stations in this period.'),
              ],
        ],
      ),
    );
  }

  // Period filter row for Compare Stations — identical Overall/Month/Day
  // controls to the Ranking page's filter, bound to the compare-specific
  // state so switching one page's period never affects the other.
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

  // Two stat blocks (Station A / Station B average ridership) plus a real
  // ridership-difference line underneath — both values and the difference
  // are computed from the fetched Supabase rows, nothing hardcoded.
  Widget _compareAverageSection(_StationRidershipRow a, _StationRidershipRow b) {
    const colorA = Color(0xFF4F46E5);
    const colorB = Color(0xFF16A34A);
    final diff = a.avgRidership - b.avgRidership;
    final higher = diff >= 0 ? a.station : b.station;
    // Percentage is the difference relative to the lower of the two real
    // averages (i.e. "X% higher than the lower station"), guarded against
    // a zero average rather than dividing by it.
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
          child: Text(
            diff.abs() < 0.5
                ? 'Ridership Difference: 0/day (0.0%, essentially tied)'
                : 'Ridership Difference: ${_formatNumber(diff.abs())}/day (${diffPct.toStringAsFixed(1)}% higher at $higher)',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.black87),
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

  // A simple two-bar comparison: the full station name sits above its bar
  // rather than beside it, so long names never get truncated. Same bar
  // fill/track colors and rounded look as the rest of the app, just
  // stacked instead of inline — no Highest/Lowest tags, just the bars.
  Widget _compareBarChart(_StationRidershipRow a, _StationRidershipRow b) {
    final maxAvg = a.avgRidership >= b.avgRidership ? a.avgRidership : b.avgRidership;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _compareBarRow(a.station, a.avgRidership, maxAvg, color: const Color(0xFF4F46E5)),
        const SizedBox(height: 14),
        _compareBarRow(b.station, b.avgRidership, maxAvg, color: const Color(0xFF16A34A)),
      ],
    );
  }

  // One bar in the comparison chart: full station name on its own line,
  // then the proportional bar (real avgRidership ÷ the larger of the two
  // averages) with its value at the trailing end.
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

  // One short, plain-language insight — derived entirely from the two
  // fetched averages (ratio/difference), no hardcoded ridership.
  Widget _compareInsightCard(_StationRidershipRow a, _StationRidershipRow b) {
    const accent = Color(0xFF4F46E5);
    final diff = a.avgRidership - b.avgRidership;
    final String message;
    if (diff.abs() < 0.5) {
      message = '${a.station} and ${b.station} have almost identical average ridership over this period.';
    } else {
      final higher = diff > 0 ? a.station : b.station;
      final lower = diff > 0 ? b.station : a.station;
      final higherAvg = diff > 0 ? a.avgRidership : b.avgRidership;
      final lowerAvg = diff > 0 ? b.avgRidership : a.avgRidership;
      final ratioText = lowerAvg > 0 ? ' (about ${(higherAvg / lowerAvg).toStringAsFixed(1)}× busier)' : '';
      message = '$higher sees noticeably higher ridership than $lower$ratioText.';
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
            child: Text(message, style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}