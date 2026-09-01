import 'package:flutter/material.dart';
import '../services/api_service.dart';

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

// Baseline intraday shape for an "average" station across the day.
// MODELLED, not from the CSV — see file header comment.
int _baselineOccupancy(int weekday, int minutesOfDay) {
  final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;
  if (isWeekend) return 24;

  final h = minutesOfDay / 60.0;
  if (h < 6.0) return 8;
  if (h < 7.0) return 16;
  if (h < 7.5) return 46;
  if (h < 8.0) return 84;
  if (h < 8.25) return 60;
  if (h < 9.0) return 42;
  if (h < 17.0) return 40;
  if (h < 17.5) return 58;
  if (h < 19.5) return 80;
  if (h < 21.0) return 32;
  return 14;
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
  if (isWeekend) {
    return '$station sees quiet weekend traffic at $t, based on real historical weekend averages. No significant congestion expected.';
  }
  switch (level) {
    case CrowdLevel.critical:
      return 'Heavy commuters are expected at $station around $t, combining typical rush-hour timing with $station\'s real historical ridership volume for this day. Platform crowding is likely severe.';
    case CrowdLevel.high:
      return 'Passenger volume is expected to be high at $station around $t. Platforms will likely be congested and boarding may require waiting for the next train.';
    case CrowdLevel.moderate:
      return 'Moderate passenger flow expected at $station around $t. Some crowding on platforms but conditions should remain manageable.';
    case CrowdLevel.low:
      return 'Light traffic expected at $station around $t. Comfortable boarding and ample seating should be available.';
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
  int _weekday = DateTime.monday;
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 30);
  CrowdResult? _crowdResult;
  double? _crowdResultDayAvg;
  double? _crowdResultFactor;
  int? _crowdResultRecordCount;

  // ── Tab 2: Peak Hours state ──
  String? _peakStation;
  int _peakWeekday = DateTime.monday;
  List<MapEntry<int, CrowdResult>>? _peakSlots;
  double? _peakDayAvg;
  double? _peakFactor;

  // ── Tab 3: Ridership History state ──
  String? _historyStation;
  List<RidershipRecord>? _historyData;
  DateTime? _historyMonthFilter; // null = show all months
  final ScrollController _historyScrollController = ScrollController();

  // ── Tab 4: Connections (O-D) state ──
  String? _connStation;
  List<MapEntry<String, int>>? _connTopDestinations;
  List<MapEntry<String, int>>? _connTopOrigins;
  int? _connOutgoing;
  int? _connIncoming;
  List<MapEntry<String, int>>? _connBusiestNetwork;
  bool _loadingConnections = false;

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

  @override
  void dispose() {
    _historyScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final stations = await _api.getStationList();
      final odStations = await _api.getStationsWithOutgoingData();
      final networkAvg = await _api.getNetworkAverageRidership();
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _stationsWithOdData = odStations.toSet();
        _networkAverage = networkAvg;
        _station = stations.isNotEmpty ? stations.first : null;
        _peakStation = _station;
        _historyStation = _station;
        _connStation = _station;
        _statsReady = stations.isNotEmpty;
        if (stations.isEmpty) _loadError = 'No station records found in the local dataset.';
      });
    } catch (e) {
      if (!mounted) return;
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

  Future<void> _runCrowdEstimate() async {
    final station = _station;
    if (station == null) return;
    final dayAvg = await _api.getStationAverageForWeekday(station, _weekday);
    // Reuses the same daily-totals lookup that getStationAverageForWeekday
    // is built on, just to expose how many real records fed that average.
    final dailyTotals = await _api.getDailyTotalsForStation(station);
    if (!mounted) return;
    final recordCount = dailyTotals.where((e) => e.key.weekday == _weekday).length;
    final minutes = _time.hour * 60 + _time.minute;
    final factor = _magnitudeFactor(dayAvg);
    setState(() {
      _crowdResult = predictCrowd(_weekday, minutes, factor);
      _crowdResultDayAvg = dayAvg;
      _crowdResultFactor = factor;
      _crowdResultRecordCount = recordCount;
    });
  }

  Future<void> _runPeakHours() async {
    final station = _peakStation;
    if (station == null) return;
    final dayAvg = await _api.getStationAverageForWeekday(station, _peakWeekday);
    if (!mounted) return;
    final hours = [6, 8, 10, 12, 14, 16, 18, 20, 22];
    final factor = _magnitudeFactor(dayAvg);
    final slots = hours
        .map((h) => MapEntry(h, predictCrowd(_peakWeekday, h * 60, factor)))
        .toList();
    setState(() {
      _peakSlots = slots;
      _peakDayAvg = dayAvg;
      _peakFactor = factor;
    });
  }

  Future<void> _runHistory() async {
    final station = _historyStation;
    if (station == null) return;
    final data = await _api.getStationTotalRecords(station);
    if (!mounted) return;
    setState(() {
      _historyData = data;
      _historyMonthFilter = null; // reset filter on fresh load
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_historyScrollController.hasClients) {
        _historyScrollController.jumpTo(_historyScrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _runConnections() async {
    final station = _connStation;
    if (station == null) return;
    setState(() => _loadingConnections = true);
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() {
        _time = picked;
        _crowdResult = null;
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
            child: Text(_loadError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (!_statsReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 4,
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
                    Tab(text: 'History', icon: Icon(Icons.show_chart, size: 15)),
                    Tab(text: 'Connections', icon: Icon(Icons.alt_route, size: 15)),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: Colors.green.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Loaded ${_stations.length} stations · ${_stationsWithOdData.length} with O-D connection data',
                      style: const TextStyle(
                          color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildCrowdEstimateTab(),
                  _buildPeakHoursTab(),
                  _buildHistoryTab(),
                  _buildConnectionsTab(),
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
            'Real historical day-of-week average for this station, applied to a modelled time-of-day pattern.',
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
                  onChanged: (val) => setState(() { _station = val; _crowdResult = null; }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _weekday,
                  decoration: InputDecoration(
                      labelText: 'Day', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: List.generate(7, (i) => i + 1)
                      .map((w) => DropdownMenuItem(value: w, child: Text(kWeekdayLabels[w - 1])))
                      .toList(),
                  onChanged: (val) => setState(() { _weekday = val!; _crowdResult = null; }),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickTime,
                  child: InputDecorator(
                    decoration: InputDecoration(
                        labelText: 'Time', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text(_time.format(context), style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  final category = timeCategoryFor(_time.hour * 60 + _time.minute);
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
                const SizedBox(height: 16),
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
                  Text(
                    'Based on $_station\'s real average ${kWeekdayLabels[_weekday - 1]} ridership '
                        '(~${(_crowdResultDayAvg ?? 0).round()} trips in local dataset).',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
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

            // D. Crowd alert insight
            _sectionCard(
              title: 'CROWD ALERT INSIGHT',
              icon: Icons.notifications_active_outlined,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _crowdResult!.level.color.withValues(alpha: 0.05),
                  border: Border.all(color: _crowdResult!.level.color.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  getAiInsight(_station!, _crowdResult!.level, _time, _weekday),
                  style: TextStyle(color: _crowdResult!.level.color, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: _sectionGap),

            // E. Calculation Breakdown
            _sectionCard(
              title: 'CALCULATION BREAKDOWN',
              icon: Icons.calculate_outlined,
              child: _buildCalculationBreakdown(),
            ),
          ],

          const SizedBox(height: _sectionGap),
          _sectionCard(
            title: 'DATA SOURCE / METHOD',
            icon: Icons.info_outline,
            child: _buildMethodologyCard(),
          ),
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

  Widget _buildCalculationBreakdown() {
    final dayAvg = _crowdResultDayAvg ?? 0;
    final factor = _crowdResultFactor ?? 0;
    final recordCount = _crowdResultRecordCount ?? 0;
    final category = timeCategoryFor(_time.hour * 60 + _time.minute);
    final dayLabel = kWeekdayLabels[_weekday - 1];
    final baseline = _baselineOccupancy(_weekday, _time.hour * 60 + _time.minute);
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
            'Estimated Occupancy = Time Category Baseline × Relative Station Factor',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF4F46E5)),
          ),
        ),
        const SizedBox(height: 12),

        _breakdownStep(
          step: 1,
          title: 'Historical Station Average',
          lines: [
            '$dayLabel average: ${dayAvg.round()} trips/day',
            '($recordCount historical records analysed)',
          ],
        ),
        _breakdownStep(
          step: 2,
          title: 'Relative Station Factor',
          lines: [
            '${dayAvg.round()} ÷ ${_networkAverage.round()} = ${factor.toStringAsFixed(2)}x',
            'This station is ${(factor * 100).round()}% as busy as the network average.',
          ],
        ),
        _breakdownStep(
          step: 3,
          title: 'Time Category Baseline',
          lines: [
            'Time: ${_time.format(context)}',
            'Baseline Occupancy: $baseline%',
            '(${category.label} category, ${category.rangeLabel})',
            'Baseline varies by exact time within a category to reflect the real rush-hour shape.',
          ],
        ),
        _breakdownStep(
          step: 4,
          title: 'Final Estimation',
          lines: [
            '$baseline% × ${factor.toStringAsFixed(2)} = $occupancy%',
          ],
          isLast: true,
        ),

        const Divider(height: 18),
        _breakdownRow(
          'Final Estimated Occupancy',
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
                Text('Step $step — $title',
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
    final dayAvg = _crowdResultDayAvg ?? 0;
    final dayLabel = kWeekdayLabels[_weekday - 1];
    final (status, color, icon) = _demandInterpretation(factor);

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
              Text('$status (${factor.toStringAsFixed(2)}x)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Based on historical ridership data: $_station averages ${dayAvg.round()} trips/day '
                'on ${dayLabel}s, vs the network-wide average.',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodologyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.5),
                children: [
                  const TextSpan(text: 'Data Source: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Rapid Rail historical ridership dataset.\n'),
                  const TextSpan(text: 'Method: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(
                      text: 'Real daily ridership averages are combined with a rule-based '
                          'commuter demand pattern to estimate crowd levels at different times of day. '),
                  TextSpan(
                      text: 'No machine learning model is used.',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade900)),
                ],
              ),
            ),
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
            'Based on historical station ridership and a rule-based commuter demand pattern. '
                'The dataset contains daily totals only, so hourly demand is estimated rather than directly observed.',
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
                  onChanged: (val) => setState(() { _peakStation = val; _peakSlots = null; _peakDayAvg = null; _peakFactor = null; }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _peakWeekday,
                  decoration: InputDecoration(
                      labelText: 'Day', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: List.generate(7, (i) => i + 1)
                      .map((w) => DropdownMenuItem(value: w, child: Text(kWeekdayLabels[w - 1])))
                      .toList(),
                  onChanged: (val) => setState(() { _peakWeekday = val!; _peakSlots = null; _peakDayAvg = null; _peakFactor = null; }),
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
              ],
            ),
          ),

          if (_peakSlots != null) ...[
            const SizedBox(height: _sectionGap),

            // B. Peak Pattern
            _sectionCard(
              title: 'PEAK PATTERN',
              icon: Icons.show_chart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 150,
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
                        return _buildTrendBar(label, result.occupancy / 100, result.level.color);
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Builder(builder: (context) {
                    final peak = _peakSlots!.reduce((a, b) => a.value.occupancy >= b.value.occupancy ? a : b);
                    final label = peak.key == 12 ? '12pm' : peak.key > 12 ? '${peak.key - 12}pm' : '${peak.key}am';
                    return Text(
                      'Busiest modelled window for $_peakStation: around $label (${peak.value.level.label}, ~${peak.value.occupancy}% capacity).',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    );
                  }),
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

            // F. Data Source / Method
            _sectionCard(
              title: 'DATA SOURCE / METHOD',
              icon: Icons.info_outline,
              child: _buildPeakMethodologyCard(),
            ),
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
    final dayAvg = _peakDayAvg ?? 0;
    final factor = _peakFactor ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _breakdownRow('Peak Period', category.label),
        _breakdownRow('Peak Time', _hourLabel(peak.key)),
        _breakdownRow('Peak Occupancy', '${peak.value.occupancy}%',
            valueColor: peak.value.level.color),
        _breakdownRow('Crowd Level', peak.value.level.label,
            valueColor: peak.value.level.color),
        _breakdownRow('Historical Day Average', '${dayAvg.round()} trips/day'),
        _breakdownRow('Relative Station Factor', '${factor.toStringAsFixed(2)}x'),
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

  Widget _buildPeakMethodologyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.5),
                children: [
                  const TextSpan(text: 'Data Source: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Rapid Rail historical ridership dataset.\n'),
                  const TextSpan(text: 'Method: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(
                      text: 'Historical station ridership is used to scale a rule-based daily '
                          'commuter demand pattern. '),
                  TextSpan(
                      text: 'No machine learning model is used.',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade900)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendBar(String label, double heightFactor, Color color, {String? tooltip}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Tooltip(
          message: tooltip ?? label,
          waitDuration: const Duration(milliseconds: 200),
          child: Container(
            width: 22,
            height: 100 * heightFactor.clamp(0.05, 1.0),
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
  //   B. History filters
  //   C. Summary statistics (Average / Highest / Lowest)
  //   D. Daily totals chart
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
              final filtered = _historyMonthFilter == null
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

              // B. History filters — always shown once data is loaded, so the
              // filter stays visible even if it currently yields no records.
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
                  onChanged: (val) => setState(() => _historyMonthFilter = val),
                ),
              );

              if (filtered.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: _sectionGap),
                    filtersSection,
                    const SizedBox(height: _sectionGap),
                    _emptyState('No records for the selected month.'),
                  ],
                );
              }

              final values = filtered.map((e) => e.ridership).toList();
              final avg = values.reduce((a, b) => a + b) / values.length;
              final maxRecord = filtered.reduce((a, b) => a.ridership >= b.ridership ? a : b);
              final minRecord = filtered.reduce((a, b) => a.ridership <= b.ridership ? a : b);
              final maxVal = maxRecord.ridership.toDouble();
              final latest = filtered.last;

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

                  // D. Daily totals chart
                  _sectionCard(
                    title: 'DAILY TOTALS',
                    icon: Icons.bar_chart,
                    subtitle: '${filtered.length} days — scrolled to most recent',
                    child: Container(
                      height: 150,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: SingleChildScrollView(
                        controller: _historyScrollController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: filtered.map((record) {
                            final factor = maxVal == 0 ? 0.0 : record.ridership / maxVal;
                            final isMax = record.ridership == maxRecord.ridership;
                            final isMin = record.ridership == minRecord.ridership;
                            final barColor = isMax
                                ? const Color(0xFF4F46E5) // highest — purple
                                : isMin
                                ? const Color(0xFFDC2626) // lowest — red
                                : Colors.blueGrey;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: _buildTrendBar(
                                '${record.date.day}/${record.date.month}',
                                factor,
                                barColor,
                                tooltip: '${record.date.day}/${record.date.month}/${record.date.year}\n${record.ridership} trips'
                                    '${isMax ? ' (highest)' : isMin ? ' (lowest)' : ''}',
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
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
}