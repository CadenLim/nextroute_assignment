import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AiCrowdScreen extends StatefulWidget {
  const AiCrowdScreen({super.key});

  @override
  State<AiCrowdScreen> createState() => _AiCrowdScreenState();
}

class _AiCrowdScreenState extends State<AiCrowdScreen> {
  final ApiService _apiService = ApiService();

  // Forecast State
  String _forecastStation = 'KL Sentral';
  String _forecastDay = 'Monday';
  TimeOfDay _forecastTime = const TimeOfDay(hour: 7, minute: 30);
  bool _isForecasting = false;
  bool _showForecastResult = false;

  // Planner State
  String _planOrigin = 'KLCC';
  String _planDestination = 'KL Sentral';
  String _planDay = 'Monday';
  TimeOfDay _planDeadline = const TimeOfDay(hour: 9, minute: 0);
  bool _isPlanning = false;
  bool _showPlanResult = false;

  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final List<String> _stations = ['KL Sentral', 'KLCC', 'Pasar Seni', 'Masjid Jamek', 'Bukit Bintang'];

  Future<void> _selectTime(BuildContext context, bool isForecast) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isForecast ? _forecastTime : _planDeadline,
    );
    if (picked != null) {
      setState(() {
        if (isForecast) {
          _forecastTime = picked;
          _showForecastResult = false;
        } else {
          _planDeadline = picked;
          _showPlanResult = false;
        }
      });
    }
  }

  void _predictCrowd() {
    setState(() => _isForecasting = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() { _isForecasting = false; _showForecastResult = true; });
    });
  }

  void _planJourney() {
    setState(() => _isPlanning = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() { _isPlanning = false; _showPlanResult = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI Crowd Intelligence', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  labelColor: const Color(0xFF1E3A8A),
                  unselectedLabelColor: Colors.white,
                  tabs: const [
                    Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.bar_chart, size: 18), SizedBox(width: 8), Text('Forecast')])),
                    Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_month, size: 18), SizedBox(width: 8), Text('Planner')])),
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
                  future: _apiService.getRidershipData(),
                  builder: (context, snapshot) {
                    return Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            snapshot.data ?? 'Syncing Prasarana Ridership Data...',
                            style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  }
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildForecastTab(),
                  _buildPlannerTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Station Crowd Forecast', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _forecastStation,
            decoration: InputDecoration(labelText: 'Station', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) => setState(() { _forecastStation = val!; _showForecastResult = false; }),
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _forecastDay,
            decoration: InputDecoration(labelText: 'Day', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (val) => setState(() { _forecastDay = val!; _showForecastResult = false; }),
          ),
          const SizedBox(height: 12),

          InkWell(
            onTap: () => _selectTime(context, true),
            child: InputDecorator(
              decoration: InputDecoration(labelText: 'Time', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(_forecastTime.format(context), style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            icon: _isForecasting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.analytics, color: Colors.white),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isForecasting ? null : _predictCrowd,
            label: const Text('Predict Crowd', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),

          if (_showForecastResult) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('EXPECTED CROWD', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          const Text('95', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const Text('%', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(width: 8),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: const Text('CRITICAL', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold))),
                        ],
                      ),
                      Container(height: 4, width: double.infinity, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(2))),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WAIT TIME', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('15+', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black87)),
                          Text(' min', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ],
                      ),
                      SizedBox(height: 4),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Crowd Trend (Hourly)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 16),

            // Native Custom Trend Bar Chart (No fl_chart package required)
            Container(
              height: 130,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildTrendBar('6am', 0.2, Colors.blue),
                  _buildTrendBar('8am', 0.95, Colors.red), // Peak
                  _buildTrendBar('10am', 0.5, Colors.orange),
                  _buildTrendBar('12pm', 0.4, Colors.blue),
                  _buildTrendBar('2pm', 0.35, Colors.blue),
                  _buildTrendBar('4pm', 0.55, Colors.orange),
                  _buildTrendBar('6pm', 0.9, Colors.red), // Peak
                  _buildTrendBar('8pm', 0.3, Colors.blue),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.05), border: Border.all(color: Colors.red.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
              child: const Text('CRITICAL: Severe crowding is expected during weekday morning rush hour. Train capacity may be exceeded.', style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ]
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
          height: 70 * heightFactor,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPlannerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('AI Journey Planner', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _planOrigin,
                  decoration: InputDecoration(labelText: 'Origin', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) => setState(() { _planOrigin = val!; _showPlanResult = false; }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _planDestination,
                  decoration: InputDecoration(labelText: 'Destination', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: _stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) => setState(() { _planDestination = val!; _showPlanResult = false; }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _planDay,
            decoration: InputDecoration(labelText: 'Day', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (val) => setState(() { _planDay = val!; _showPlanResult = false; }),
          ),
          const SizedBox(height: 12),

          InkWell(
            onTap: () => _selectTime(context, false),
            child: InputDecorator(
              decoration: InputDecoration(labelText: 'Deadline Arrival Time', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              child: Text(_planDeadline.format(context), style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            icon: _isPlanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.route, color: Colors.white),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isPlanning ? null : _planJourney,
            label: const Text('Plan My Journey', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),

          if (_showPlanResult) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RECOMMENDED ITINERARY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Departure', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Text('8:20', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                              const SizedBox(width: 4),
                              Text('AM', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E3A8A).withValues(alpha: 0.6))),
                            ],
                          ),
                        ],
                      ),
                      const Icon(Icons.arrow_forward, color: Colors.grey),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Arrival', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Text('8:44', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
                              const SizedBox(width: 4),
                              Text('AM', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniStat('Travel Duration', '24 min', Icons.timer),
                      _buildMiniStat('Crowd Level', 'Low', Icons.people_alt),
                      _buildMiniStat('Wait Time', '2 min', Icons.hourglass_empty),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.05), border: Border.all(color: Colors.green.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
              child: const Text('Departing at 8:20 AM avoids the morning peak (7:30 - 8:00 AM) while arriving before your 9:00 AM deadline - with 10 minutes to spare.', style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }
}