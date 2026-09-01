import 'package:flutter/material.dart';
import '../services/api_service.dart';

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

  // ── Tab 2: Peak Hours state ──
  String? _peakStation;
  int _peakWeekday = DateTime.monday;
  List<MapEntry<int, CrowdResult>>? _peakSlots;

  // ── Tab 3: Ridership History state ──
  String? _historyStation;
  List<RidershipRecord>? _historyData;
  final ScrollController _historyScrollController = ScrollController();

  // ── Tab 4: Connections (O-D) state ──
  String? _connStation;
  List<MapEntry<String, int>>? _connTopDestinations;
  List<MapEntry<String, int>>? _connTopOrigins;
  int? _connOutgoing;
  int? _connIncoming;
  List<MapEntry<String, int>>? _connBusiestNetwork;
  bool _loadingConnections = false;

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
      setState(() => _loadError = 'Could not load the ridership dataset. Check that '
          'assets/ridership.csv is declared in pubspec.yaml.');
    }
  }

  double _magnitudeFactor(double dayAvg) {
    final ratio = dayAvg / _networkAverage;
    return ratio.clamp(0.4, 1.8);
  }

  Future<void> _runCrowdEstimate() async {
    final station = _station;
    if (station == null) return;
    final dayAvg = await _api.getStationAverageForWeekday(station, _weekday);
    if (!mounted) return;
    final minutes = _time.hour * 60 + _time.minute;
    final factor = _magnitudeFactor(dayAvg);
    setState(() {
      _crowdResult = predictCrowd(_weekday, minutes, factor);
      _crowdResultDayAvg = dayAvg;
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
    setState(() => _peakSlots = slots);
  }

  Future<void> _runHistory() async {
    final station = _historyStation;
    if (station == null) return;
    final data = await _api.getStationTotalRecords(station);
    if (!mounted) return;
    setState(() => _historyData = data);
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
          title: const Text('AI Crowd & Ridership Insights',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  // ── Tab 1 UI ───────────────────────────────────────────────────────────

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
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _station,
            decoration: InputDecoration(
                labelText: 'Station', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
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
          if (_crowdResult != null) ...[
            const SizedBox(height: 24),
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
            const SizedBox(height: 16),
            Container(
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
          const Text('Peak Hour Pattern',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Modelled hourly shape (the dataset has no hourly column), scaled by this station\'s real day-of-week average.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _peakStation,
            decoration: InputDecoration(
                labelText: 'Station', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() { _peakStation = val; _peakSlots = null; }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _peakWeekday,
            decoration: InputDecoration(
                labelText: 'Day', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: List.generate(7, (i) => i + 1)
                .map((w) => DropdownMenuItem(value: w, child: Text(kWeekdayLabels[w - 1])))
                .toList(),
            onChanged: (val) => setState(() { _peakWeekday = val!; _peakSlots = null; }),
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
          const Text('Ridership History',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Real daily ridership totals from the local dataset — no modelling here.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _historyStation,
            decoration: InputDecoration(
                labelText: 'Station', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() { _historyStation = val; _historyData = null; }),
          ),
          const SizedBox(height: 16),
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
          if (_historyData != null && _historyData!.isEmpty) ...[
            const SizedBox(height: 16),
            const Text('No records found for this station in the local dataset.',
                style: TextStyle(color: Colors.black54)),
          ],
          if (_historyData != null && _historyData!.isNotEmpty) ...[
            Builder(builder: (context) {
              final values = _historyData!.map((e) => e.ridership).toList();
              final avg = values.reduce((a, b) => a + b) / values.length;
              final maxRecord = _historyData!.reduce((a, b) => a.ridership >= b.ridership ? a : b);
              final minRecord = _historyData!.reduce((a, b) => a.ridership <= b.ridership ? a : b);
              final maxVal = maxRecord.ridership.toDouble();
              final latest = _historyData!.last;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: _statCard('AVERAGE', avg.round().toString())),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard('HIGHEST', maxRecord.ridership.toString())),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard('LOWEST', minRecord.ridership.toString())),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Most recent on file: ${latest.date.day}/${latest.date.month}/${latest.date.year} — ${latest.ridership} trips.',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Daily totals', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
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
                        children: _historyData!.map((record) {
                          final factor = maxVal == 0 ? 0.0 : record.ridership / maxVal;
                          final isMax = record.ridership == maxRecord.ridership;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _buildTrendBar(
                              '${record.date.day}/${record.date.month}',
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

  // ── Tab 4 UI (NEW) ────────────────────────────────────────────────────

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
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _connStation,
            decoration: InputDecoration(
                labelText: 'Station', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() {
              _connStation = val;
              _connTopDestinations = null;
              _connTopOrigins = null;
            }),
          ),
          const SizedBox(height: 16),
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

          if (_connTopDestinations != null) ...[
            const SizedBox(height: 24),
            if (!hasOdData) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
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
              Row(
                children: [
                  Expanded(child: _statCard('OUTGOING TRIPS', '${_connOutgoing ?? 0}')),
                  const SizedBox(width: 10),
                  Expanded(child: _statCard('INCOMING TRIPS', '${_connIncoming ?? 0}')),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Top destinations from this station',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              ..._connTopDestinations!.map((e) => _connectionRow(e.key, e.value,
                  _connTopDestinations!.first.value, const Color(0xFF4F46E5))),
              if (_connTopOrigins!.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Top origins into this station',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                const SizedBox(height: 8),
                ..._connTopOrigins!.map((e) => _connectionRow(e.key, e.value,
                    _connTopOrigins!.first.value, const Color(0xFF16A34A))),
              ],
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Busiest connections network-wide',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 4),
            const Text('Top station-to-station links by total real trips recorded, across the whole dataset.',
                style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            if (_connBusiestNetwork != null)
              ..._connBusiestNetwork!.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final e = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('#$rank', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black45, fontSize: 12)),
                      ),
                      Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12))),
                      Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  Widget _connectionRow(String stationName, int trips, int maxTrips, Color color) {
    final factor = maxTrips == 0 ? 0.0 : trips / maxTrips;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(stationName, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: factor.clamp(0.03, 1.0),
                child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 40, child: Text('$trips', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
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