import 'package:flutter/material.dart';
import '../localization/app_language.dart';
import '../services/api_service.dart';

class JourneyPlanningScreen extends StatefulWidget {
  const JourneyPlanningScreen({super.key});

  @override
  State<JourneyPlanningScreen> createState() => _JourneyPlanningScreenState();
}

class _JourneyPlanningScreenState extends State<JourneyPlanningScreen> {
  final ApiService _apiService = ApiService();

  // Data State
  List<StationModel> _allStations = [];
  List<StationModel> _filteredStations = [];
  List<Map<String, dynamic>> _routes = [];
  bool _isLoading = true;

  // Journey State
  StationModel? _origin;
  StationModel? _destination;
  bool _hasSearched = false;
  int _selectedRouteIndex = 0;
  bool _isJourneyConfirmed = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    final stations = await _apiService.loadAllStations();
    final routesData = await _apiService.loadGtfsRoutes();

    // Fallback static data if GTFS is empty, just so the UI looks exactly like your mockup
    final displayRoutes = routesData.isNotEmpty ? routesData : [
      {
        'id': 'KJ', 'name': 'LRT Kelana Jaya', 'duration': '24 min', 'fare': 'RM 2.50',
        'walk': '3 min walk', 'badge': 'Fastest', 'color': const Color(0xFFEF4444)
      },
      {
        'id': 'PY', 'name': 'MRT Putrajaya', 'duration': '28 min', 'fare': 'RM 3.00',
        'walk': '5 min walk', 'badge': 'Scenic', 'color': const Color(0xFF10B981)
      },
      {
        'id': 'BUS', 'name': 'Bus + LRT Transfer', 'duration': '35 min', 'fare': 'RM 1.50',
        'walk': '8 min walk', 'badge': 'Budget', 'color': const Color(0xFF3B82F6)
      },
    ];

    if (mounted) {
      setState(() {
        _allStations = stations;
        _filteredStations = stations;
        _routes = displayRoutes;
        _isLoading = false;
      });
    }
  }

  void _swapStations() {
    setState(() {
      final temp = _origin;
      _origin = _destination;
      _destination = temp;
      _hasSearched = false;
      _isJourneyConfirmed = false;
    });
  }

  void _showStationPicker(bool isOrigin) {
    setState(() => _filteredStations = List.from(_allStations));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.85,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Text(
                      context.tr(
                        isOrigin
                            ? 'Select Starting Point'
                            : 'Select Destination',
                      ),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        hintText: context.tr('Search station...'),
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onChanged: (value) {
                        setModalState(() {
                          _filteredStations = _allStations
                              .where((s) => s.name.toLowerCase().contains(value.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _filteredStations.length,
                        separatorBuilder: (context, index) => Divider(color: Colors.grey[200]),
                        itemBuilder: (context, index) {
                          final station = _filteredStations[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(station.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Wrap(
                              spacing: 4,
                              children: station.lines.map((lineName) {
                                Color bgColor = Colors.grey;
                                String abrv = 'XX';

                                // Rail Lines
                                if (lineName.contains('Kelana Jaya')) { bgColor = const Color(0xFFEF4444); abrv = 'KJ'; }
                                else if (lineName.contains('Kajang')) { bgColor = const Color(0xFF10B981); abrv = 'KG'; }
                                else if (lineName.contains('Ampang')) { bgColor = const Color(0xFF8B5CF6); abrv = 'AG'; }
                                else if (lineName.contains('Putrajaya')) { bgColor = const Color(0xFFF59E0B); abrv = 'PY'; }
                                else if (lineName.contains('Monorail')) { bgColor = const Color(0xFF84CC16); abrv = 'MR'; }
                                else if (lineName.contains('Sri Petaling')) { bgColor = const Color(0xFF8B5CF6); abrv = 'SP'; }
                                else if (lineName.contains('KTM')) { bgColor = const Color(0xFF3B82F6); abrv = 'KT'; }
                                // Bus & Feeder Lines
                                else if (lineName.contains('MRT Feeder')) { bgColor = const Color(0xFF06B6D4); abrv = 'F'; }
                                else if (lineName.contains('Bus')) { bgColor = const Color(0xFF3B82F6); abrv = 'B'; }

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
                                  child: Text(abrv, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                );
                              }).toList(),
                            ),
                            onTap: () {
                              setState(() {
                                if (isOrigin) _origin = station;
                                else _destination = station;
                                _hasSearched = false;
                                _isJourneyConfirmed = false;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          context.tr('Cancel'),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6), // Light grey background
      body: Column(
        children: [
          // --- CUSTOM APP BAR ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 30),
            decoration: const BoxDecoration(
              color: Color(0xFF2A52BE), // Deep blue
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('ROUTE OPTIMIZATION'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('Journey Planning'),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // --- SCROLLABLE BODY ---
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Section Title
                Text(context.tr('ROAD SEARCH'), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 12),

                // --- SEARCH CARD ---
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: Column(
                    children: [
                      // Origin
                      InkWell(
                        onTap: () => _showStationPicker(true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.circle, color: Colors.blue, size: 12),
                              const SizedBox(width: 12),
                              Text(_origin?.name ?? context.tr('Select starting point'), style: TextStyle(color: _origin == null ? Colors.grey : Colors.black, fontWeight: _origin == null ? FontWeight.normal : FontWeight.bold)),
                              const Spacer(),
                              const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),

                      // Swap Icon Divider
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          const Divider(height: 30),
                          GestureDetector(
                            onTap: _swapStations,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), shape: BoxShape.circle),
                              child: const Icon(Icons.swap_vert, size: 18, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),

                      // Destination
                      InkWell(
                        onTap: () => _showStationPicker(false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.circle, color: Colors.red, size: 12),
                              const SizedBox(width: 12),
                              Text(_destination?.name ?? context.tr('Select destination'), style: TextStyle(color: _destination == null ? Colors.grey : Colors.black, fontWeight: _destination == null ? FontWeight.normal : FontWeight.bold)),
                              const Spacer(),
                              const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Find Routes Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.search, color: _origin != null && _destination != null ? Colors.white : Colors.indigo),
                          label: Text(context.tr('Find Routes'), style: TextStyle(fontWeight: FontWeight.bold, color: _origin != null && _destination != null ? Colors.white : Colors.indigo)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _origin != null && _destination != null ? const Color(0xFF2A52BE) : const Color(0xFFE2E8F0),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            if (_origin != null && _destination != null) {
                              setState(() => _hasSearched = true);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                if (_hasSearched) ...[
                  const SizedBox(height: 24),
                  Text(context.tr('ROUTE COMPARISON'), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 12),

                  // --- ROUTES LIST ---
                  ..._routes.asMap().entries.map((entry) {
                    final index = entry.key;
                    final route = entry.value;
                    final isSelected = _selectedRouteIndex == index;

                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedRouteIndex = index;
                        _isJourneyConfirmed = false;
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? const Color(0xFF2A52BE) : Colors.transparent, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
                        ),
                        child: Row(
                          children: [
                            // Badge Column
                            Column(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(color: route['color'], borderRadius: BorderRadius.circular(10)),
                                  child: Center(child: Text(route['id'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                                  child: Row(
                                    children: [
                                      if (index == 0) const Icon(Icons.star, color: Colors.amber, size: 10),
                                      if (index == 0) const SizedBox(width: 2),
                                      Text(route['badge'], style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Details Column
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(route['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time, size: 14, color: Colors.blueGrey),
                                      const SizedBox(width: 4), Text(route['duration'], style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                      const SizedBox(width: 12),
                                      const Icon(Icons.credit_card, size: 14, color: Colors.blue),
                                      const SizedBox(width: 4), Text(route['fare'], style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                      const SizedBox(width: 12),
                                      const Icon(Icons.directions_walk, size: 14, color: Colors.orange),
                                      const SizedBox(width: 4), Text(route['walk'], style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                    ],
                                  )
                                ],
                              ),
                            ),
                            // Radio Button
                            Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? const Color(0xFF2A52BE) : Colors.grey.shade300, width: 2),
                                color: isSelected ? const Color(0xFF2A52BE) : Colors.transparent,
                              ),
                              child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 24),
                  Text(context.tr('JOURNEY SUMMARY'), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 12),

                  // --- JOURNEY SUMMARY TICKET ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: Origin -> Dest
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(_origin!.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2A52BE)))),
                              const Icon(Icons.arrow_forward, size: 16, color: Color(0xFF2A52BE)),
                              Expanded(child: Text(_destination!.name, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2A52BE)))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Recommended Tag
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: _routes[_selectedRouteIndex]['color'], borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                children: [
                                  Text(_routes[_selectedRouteIndex]['id'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(width: 4),
                                  Text(_routes[_selectedRouteIndex]['name'], style: const TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (_selectedRouteIndex == 0) ...[
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(context.tr('Recommended Route'), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                            ]
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Stats Grid
                        Row(
                          children: [
                            _buildSummaryBox(context.tr('DEPART'), '8:20 AM'), const SizedBox(width: 12),
                            _buildSummaryBox(context.tr('ARRIVE'), '8:44 AM'), const SizedBox(width: 12),
                            _buildSummaryBox(context.tr('DURATION'), _routes[_selectedRouteIndex]['duration']),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildSummaryBox(context.tr('ESTIMATED FARE'), _routes[_selectedRouteIndex]['fare'], icon: Icons.credit_card, iconColor: Colors.blue)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildSummaryBox(context.tr('WALK TO STATION'), _routes[_selectedRouteIndex]['walk'], icon: Icons.directions_walk, iconColor: Colors.orange)),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Start Journey Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isJourneyConfirmed ? const Color(0xFF10B981) : const Color(0xFF2A52BE),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => setState(() => _isJourneyConfirmed = true),
                            child: Text(
                              context.tr(_isJourneyConfirmed ? '✓ Journey Confirmed' : 'Start Journey'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ),
                  )
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for the summary grid boxes
  Widget _buildSummaryBox(String label, String value, {IconData? icon, Color? iconColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(color: Colors.grey[50], border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: iconColor), const SizedBox(width: 4)],
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
              ],
            )
          ],
        ),
      ),
    );
  }
}
