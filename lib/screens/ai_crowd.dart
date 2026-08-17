import 'package:flutter/material.dart';
import '../services/api_service.dart';

// ── Crowd levels & rule-based prediction ────────────────────────────────────
// This is NOT a trained ML model. It is a transparent, rule-based estimator:
// weekday/weekend + time-of-day bands (based on typical urban rail commuter
// behaviour) combined with whether the station is a major interchange.
// This matches the brief: focus on Flutter + data handling, not ML training.

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

const List<String> kMajorStations = [
  'KL Sentral',
  'KLCC',
  'Bukit Bintang',
  'Masjid Jamek',
];

// Core rule-based estimator. station/day/minutesOfDay in, crowd level out.
CrowdResult predictCrowd(String station, String day, int minutesOfDay) {
  final isWeekend = day == 'Saturday' || day == 'Sunday';
  final isMajor = kMajorStations.contains(station);

  if (isWeekend) {
    return CrowdResult(CrowdLevel.low, isMajor ? 34 : 22);
  }

  final h = minutesOfDay / 60.0;

  if (h < 6.0) return CrowdResult(CrowdLevel.low, 8);
  if (h < 7.0) return CrowdResult(CrowdLevel.low, isMajor ? 24 : 14);
  if (h < 7.5) return CrowdResult(CrowdLevel.moderate, isMajor ? 58 : 44);
  if (h < 8.0) return CrowdResult(CrowdLevel.critical, isMajor ? 95 : 82);
  if (h < 8.25) return CrowdResult(CrowdLevel.high, isMajor ? 72 : 58);
  if (h < 9.0) return CrowdResult(CrowdLevel.moderate, isMajor ? 52 : 40);
  if (h < 17.0) return CrowdResult(CrowdLevel.moderate, isMajor ? 52 : 38);
  if (h < 17.5) return CrowdResult(CrowdLevel.high, isMajor ? 70 : 55);
  if (h < 19.5) return CrowdResult(CrowdLevel.critical, isMajor ? 92 : 78);
  if (h < 21.0) return CrowdResult(CrowdLevel.moderate, isMajor ? 45 : 30);
  return CrowdResult(CrowdLevel.low, isMajor ? 22 : 12);
}

String getAiInsight(String station, CrowdLevel level, TimeOfDay time, String day) {
  final isWeekend = day == 'Saturday' || day == 'Sunday';
  final t = time.format24Hour();
  if (isWeekend) {
    return '$station sees quiet weekend traffic at $t. No significant congestion expected.';
  }
  switch (level) {
    case CrowdLevel.critical:
      return 'Heavy office commuters are expected around $t due to weekday rush hour. Platform crowding is severe and trains may skip stops.';
    case CrowdLevel.high:
      return 'Passenger volume is high at $t. Platforms will be congested and boarding may require waiting for the next train.';
    case CrowdLevel.moderate:
      return 'Moderate passenger flow at $t. Some crowding on platforms is expected but conditions remain manageable.';
    case CrowdLevel.low:
      return 'Light traffic at $t. Comfortable boarding and ample seating should be available.';
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
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final minutes = _time.hour * 60 + _time.minute;
      setState(() {
        _crowdResult = predictCrowd(_station, _day, minutes);
        _loadingCrowd = false;
      });
    });
  }

  void _runPeakHours() {
    setState(() => _loadingPeak = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final hours = [6, 8, 10, 12, 14, 16, 18, 20, 22];
      final slots = hours
          .map((h) => MapEntry(h, predictCrowd(_peakStation, _peakDay, h * 60)))
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
          title: const Text('AI Crowd Intelligence',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                child: const TabBar(
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  labelColor: Color(0xFF1E3A8A),
                  unselectedLabelColor: Colors.white,
                  labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: TextStyle(fontSize: 11),
                  tabs: [
                    Tab(text: 'Crowd Estimate', icon: Icon(Icons.bar_chart, size: 16)),
                    Tab(text: 'Peak Hours', icon: Icon(Icons.schedule, size: 16)),
                    Tab(text: 'History', icon: Icon(Icons.show_chart, size: 16)),
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
                  return Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          snapshot.data ?? 'Loading local ridership dataset...',
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
          const Text('Station Crowd Estimate',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _station,
            decoration: InputDecoration(
                labelText: 'Station', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() { _station = val!; _crowdResult = null; }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _day,
            decoration: InputDecoration(
                labelText: 'Day', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (val) => setState(() { _day = val!; _crowdResult = null; }),
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
            icon: _loadingCrowd
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.analytics, color: Colors.white),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _loadingCrowd ? null : _runCrowdEstimate,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(_crowdResult!.level.queueEstimate,
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
          const Text('Peak Hour Pattern',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text(
            'Modelled typical pattern based on general weekday/weekend commuter behaviour — not live sensor data.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _peakStation,
            decoration: InputDecoration(
                labelText: 'Station', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() { _peakStation = val!; _peakSlots = null; }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _peakDay,
            decoration: InputDecoration(
                labelText: 'Day', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
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
            onPressed: _loadingPeak ? null : _runPeakHours,
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
                'Busiest modelled window: around $label (${peak.value.level.label}, ~${peak.value.occupancy}% capacity).',
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
            'Real daily ridership totals aggregated from the local dataset.',
            style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _historyStation,
            decoration: InputDecoration(
                labelText: 'Station', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
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
            label: const Text('Load History', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          if (_historyError != null) ...[
            const SizedBox(height: 16),
            Text(_historyError!, style: const TextStyle(color: Colors.red)),
          ],
          if (_historyData != null && _historyData!.isEmpty) ...[
            const SizedBox(height: 16),
            const Text('No records found for this station in the local dataset.',
                style: TextStyle(color: Colors.black54)),
          ],
          if (_historyData != null && _historyData!.isNotEmpty) ...[
            Builder(builder: (context) {
              final values = _historyData!.map((e) => e.value).toList();
              final avg = values.reduce((a, b) => a + b) / values.length;
              final maxEntry = _historyData!.reduce((a, b) => a.value >= b.value ? a : b);
              final minEntry = _historyData!.reduce((a, b) => a.value <= b.value ? a : b);
              final maxVal = maxEntry.value.toDouble();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: _statCard('AVERAGE', avg.round().toString())),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard('HIGHEST', maxEntry.value.toString())),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard('LOWEST', minEntry.value.toString())),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Daily totals', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),
                  Container(
                    height: 150,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _historyData!.map((entry) {
                        final factor = maxVal == 0 ? 0.0 : entry.value / maxVal;
                        final isMax = entry.value == maxEntry.value;
                        return _buildTrendBar(
                          '${entry.key.day}/${entry.key.month}',
                          factor,
                          isMax ? const Color(0xFF4F46E5) : Colors.blueGrey,
                        );
                      }).toList(),
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
