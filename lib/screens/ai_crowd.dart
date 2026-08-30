import 'package:flutter/material.dart';
import '../localization/app_language.dart';
import '../services/api_service.dart';

// ── Crowd levels & rule-based prediction ────────────────────────────────────
// This is NOT a trained ML model. It is a transparent, rule-based estimator:
// a weekday/weekend + time-of-day baseline pattern (based on typical urban
// rail commuter behaviour), scaled by each station's REAL average daily
// ridership from the local dataset — so busier real stations genuinely
// produce higher estimates than quieter ones, not just a fixed guess.

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
  final int occupancy; // 0-100
  CrowdResult(this.level, this.occupancy);
}

// Baseline occupancy shape for an "average" station across the day.
// This is the modelled part (no real hourly data exists publicly).
int _baselineOccupancy(String day, int minutesOfDay) {
  final isWeekend = day == 'Saturday' || day == 'Sunday';
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

// Core rule-based estimator.
// [magnitudeFactor] comes from real data: a station with higher real average
// ridership gets a factor above 1.0, a quieter one gets a factor below 1.0.
CrowdResult predictCrowd(String day, int minutesOfDay, double magnitudeFactor) {
  final baseline = _baselineOccupancy(day, minutesOfDay);
  final occupancy = (baseline * magnitudeFactor).round().clamp(4, 99);
  return CrowdResult(_levelForOccupancy(occupancy), occupancy);
}

String getAiInsight(String station, CrowdLevel level, TimeOfDay time, String day) {
  final isWeekend = day == 'Saturday' || day == 'Sunday';
  final t = time.format24Hour();
  if (isWeekend) {
    return '$station sees quiet weekend traffic at $t. No significant congestion expected.';
  }
  switch (level) {
    case CrowdLevel.critical:
      return 'Heavy commuters are expected at $station around $t, combining rush-hour timing with $station\'s real historical ridership volume. Platform crowding is severe.';
    case CrowdLevel.high:
      return 'Passenger volume is high at $station around $t. Platforms will be congested and boarding may require waiting for the next train.';
    case CrowdLevel.moderate:
      return 'Moderate passenger flow expected at $station around $t. Some crowding on platforms but conditions remain manageable.';
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
  final ApiService _apiService = ApiService();

  final List<String> _days = const [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  final List<String> _stations = const [
    'KL Sentral', 'KLCC', 'Pasar Seni', 'Masjid Jamek', 'Bukit Bintang',
  ];

  // Real per-station average ridership, loaded once from the CSV at startup.
  // This is what makes Crowd Estimate / Peak Hours actually reflect real data.
  Map<String, double> _stationAvg = {};
  double _maxStationAvg = 1;
  bool _statsReady = false;

  // ── Tab 1: Crowd Estimate state ──
  String _station = 'KL Sentral';
  String _day = 'Monday';
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 30);
  CrowdResult? _crowdResult;
  bool _loadingCrowd = false;

  // ── Tab 2: Peak Hours state ──
  String _peakStation = 'KL Sentral';
  String _peakDay = 'Monday';
  List<MapEntry<int, CrowdResult>>? _peakSlots; // hour -> result
  bool _loadingPeak = false;

  // ── Tab 3: Ridership History state ──
  String _historyStation = 'KL Sentral';
  List<MapEntry<DateTime, int>>? _historyData;
  bool _loadingHistory = false;
  String? _historyError;
  final ScrollController _historyScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadStationStats();
  }

  @override
  void dispose() {
    _historyScrollController.dispose();
    super.dispose();
  }

  // Loads each demo station's real average daily ridership from the CSV,
  // so predictCrowd() can scale its estimates against real magnitude
  // instead of a fixed "is this a major station" guess.
  Future<void> _loadStationStats() async {
    final Map<String, double> avgs = {};
    for (final s in _stations) {
      avgs[s] = await _apiService.getStationAverageRidership(s);
    }
    final maxAvg = avgs.values.isEmpty
        ? 1.0
        : avgs.values.reduce((a, b) => a > b ? a : b);
    if (!mounted) return;
    setState(() {
      _stationAvg = avgs;
      _maxStationAvg = maxAvg == 0 ? 1 : maxAvg;
      _statsReady = true;
    });
  }

  // Converts a station's real average ridership into a multiplier roughly
  // between 0.55 (quietest real station in our dataset) and 1.15 (busiest).
  double _magnitudeFactor(String station) {
    final avg = _stationAvg[station] ?? 0;
    return 0.55 + 0.6 * (avg / _maxStationAvg);
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

  void _runCrowdEstimate() {
    setState(() => _loadingCrowd = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final minutes = _time.hour * 60 + _time.minute;
      final factor = _magnitudeFactor(_station);
      setState(() {
        _crowdResult = predictCrowd(_day, minutes, factor);
        _loadingCrowd = false;
      });
    });
  }

  void _runPeakHours() {
    setState(() => _loadingPeak = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final hours = [6, 8, 10, 12, 14, 16, 18, 20, 22];
      final factor = _magnitudeFactor(_peakStation);
      final slots = hours
          .map((h) => MapEntry(h, predictCrowd(_peakDay, h * 60, factor)))
          .toList();
      setState(() {
        _peakSlots = slots;
        _loadingPeak = false;
      });
    });
  }

  Future<void> _runHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final data = await _apiService.getDailyTotalsForStation(_historyStation);
      if (!mounted) return;
      setState(() {
        _historyData = data;
        _loadingHistory = false;
      });
      // Jump the chart to the most recent date once it's rendered, so users
      // see current data by default instead of the very first day on file.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_historyScrollController.hasClients) {
          _historyScrollController.jumpTo(
            _historyScrollController.position.maxScrollExtent,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = 'Could not load ridership history for this station.';
        _loadingHistory = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            context.tr('AI Crowd Intelligence'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: const Color(0xFF1E3A8A),
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TabBar(
                  indicator: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  labelColor: const Color(0xFF1E3A8A),
                  unselectedLabelColor: Colors.white,
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: const TextStyle(fontSize: 11),
                  tabs: [
                    Tab(text: context.tr('Crowd Estimate'), icon: const Icon(Icons.bar_chart, size: 16)),
                    Tab(text: context.tr('Peak Hours'), icon: const Icon(Icons.schedule, size: 16)),
                    Tab(text: context.tr('History'), icon: const Icon(Icons.show_chart, size: 16)),
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
              child: FutureBuilder<String>(
                future: _apiService.getDatasetStatus(),
                builder: (context, snapshot) {
                  final base = snapshot.data ?? 'Loading local ridership dataset...';
                  final suffix = _statsReady ? ' · station averages ready' : ' · computing station averages...';
                  return Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          base + suffix,
                          style: const TextStyle(
                              color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildCrowdEstimateTab(),
                  _buildPeakHoursTab(),
                  _buildHistoryTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1 UI ───────────────────────────────────────────────────────────

  Widget _buildCrowdEstimateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Station Crowd Estimate'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Modelled time-of-day pattern, scaled by each station\'s real average ridership.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _station,
            decoration: InputDecoration(
                labelText: context.tr('Station'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() { _station = val!; _crowdResult = null; }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _day,
            decoration: InputDecoration(
                labelText: context.tr('Day'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _days.map((d) => DropdownMenuItem(value: d, child: Text(context.tr(d)))).toList(),
            onChanged: (val) => setState(() { _day = val!; _crowdResult = null; }),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickTime,
            child: InputDecorator(
              decoration: InputDecoration(
                  labelText: context.tr('Time'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(_time.format(context), style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: _loadingCrowd
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.analytics, color: Colors.white),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: (!_statsReady || _loadingCrowd) ? null : _runCrowdEstimate,
            label: Text(context.tr(_statsReady ? 'Predict Crowd' : 'Loading station data...'),
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
          if (_crowdResult != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('EXPECTED CROWD'),
                          style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
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
                            child: Text(context.tr(_crowdResult!.level.label),
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
                      Text(context.tr('EST. QUEUE'),
                          style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text(_crowdResult!.level.queueEstimate,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Based on $_station\'s real average ridership (~${(_stationAvg[_station] ?? 0).round()} trips/day in local dataset).',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _crowdResult!.level.color.withValues(alpha: 0.05),
                border: Border.all(color: _crowdResult!.level.color.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                getAiInsight(_station, _crowdResult!.level, _time, _day),
                style: TextStyle(color: _crowdResult!.level.color, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 2 UI ───────────────────────────────────────────────────────────

  Widget _buildPeakHoursTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Peak Hour Pattern'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Modelled time-of-day shape, scaled by this station\'s real average ridership — not live sensor data.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _peakStation,
            decoration: InputDecoration(
                labelText: context.tr('Station'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() { _peakStation = val!; _peakSlots = null; }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _peakDay,
            decoration: InputDecoration(
                labelText: context.tr('Day'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _days.map((d) => DropdownMenuItem(value: d, child: Text(context.tr(d)))).toList(),
            onChanged: (val) => setState(() { _peakDay = val!; _peakSlots = null; }),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: _loadingPeak
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.schedule, color: Colors.white),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: (!_statsReady || _loadingPeak) ? null : _runPeakHours,
            label: Text(context.tr(_statsReady ? 'Show Peak Pattern' : 'Loading station data...'),
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
          if (_peakSlots != null) ...[
            const SizedBox(height: 24),
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
                  final label = hour == 12
                      ? '12pm'
                      : hour > 12
                          ? '${hour - 12}pm'
                          : '${hour}am';
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
        ],
      ),
    );
  }

  Widget _buildTrendBar(String label, double heightFactor, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 22,
          height: 100 * heightFactor.clamp(0.05, 1.0),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Tab 3 UI ───────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Ridership History'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Real daily ridership totals aggregated from the local dataset.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _historyStation,
            decoration: InputDecoration(
                labelText: context.tr('Station'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() { _historyStation = val!; _historyData = null; }),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: _loadingHistory
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.show_chart, color: Colors.white),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _loadingHistory ? null : _runHistory,
            label: Text(context.tr('Load History'), style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
          if (_historyError != null) ...[
            const SizedBox(height: 16),
            Text(_historyError!, style: const TextStyle(color: Colors.red)),
          ],
          if (_historyData != null && _historyData!.isEmpty) ...[
            const SizedBox(height: 16),
            Text(context.tr('No records found for this station in the local dataset.'),
                style: const TextStyle(color: Colors.black54)),
          ],
          if (_historyData != null && _historyData!.isNotEmpty) ...[
            Builder(builder: (context) {
              final values = _historyData!.map((e) => e.value).toList();
              final avg = values.reduce((a, b) => a + b) / values.length;
              final maxEntry = _historyData!.reduce((a, b) => a.value >= b.value ? a : b);
              final minEntry = _historyData!.reduce((a, b) => a.value <= b.value ? a : b);
              final maxVal = maxEntry.value.toDouble();
              final latest = _historyData!.last;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: _statCard(context.tr('AVERAGE'), avg.round().toString())),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard(context.tr('HIGHEST'), maxEntry.value.toString())),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard(context.tr('LOWEST'), minEntry.value.toString())),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Most recent on file: ${latest.key.day}/${latest.key.month}/${latest.key.year} — ${latest.value} trips.',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.tr('Daily totals'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                      Text('${_historyData!.length} days — scrolled to most recent',
                          style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
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
                        children: _historyData!.map((entry) {
                          final factor = maxVal == 0 ? 0.0 : entry.value / maxVal;
                          final isMax = entry.value == maxEntry.value;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _buildTrendBar(
                              '${entry.key.day}/${entry.key.month}',
                              factor,
                              isMax ? const Color(0xFF4F46E5) : Colors.blueGrey,
                            ),
                          );
                        }).toList(),
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

  Widget _statCard(String label, String value) {
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
        ],
      ),
    );
  }
}
