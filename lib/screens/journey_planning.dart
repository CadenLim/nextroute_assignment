import 'package:flutter/material.dart';
import '../services/api_service.dart';


class JourneyPlanningScreen extends StatefulWidget {
  const JourneyPlanningScreen({super.key});

  @override
  State<JourneyPlanningScreen> createState() => _JourneyPlanningScreenState();
}

class _JourneyPlanningScreenState extends State<JourneyPlanningScreen> {
  final ApiService _apiService = ApiService();

  List<StationModel> _allStations = [];
  List<StationModel> _filteredStations = [];
  bool _isLoadingStations = true;

  String? _selectedOrigin;
  String? _selectedDestination;
  bool _hasSearched = false;
  int _selectedRouteIndex = 0;
  bool _isJourneyConfirmed = false;

  final List<Map<String, dynamic>> _routes = [
    {
      'id': 'KJ',
      'name': 'LRT Kelana Jaya Line',
      'duration': '24 min',
      'fare': 'RM 2.50',
      'walk': '3 min walk',
      'badge': 'Fastest',
      'badgeIcon': Icons.star,
      'badgeColor': Colors.amber,
      'color': const Color(0xFFEF4444),
    },
    {
      'id': 'PY',
      'name': 'MRT Putrajaya Line',
      'duration': '28 min',
      'fare': 'RM 3.00',
      'walk': '5 min walk',
      'badge': 'Scenic',
      'badgeIcon': null,
      'badgeColor': Colors.grey,
      'color': const Color(0xFF10B981),
    },
    {
      'id': 'BUS',
      'name': 'Bus + Rail Transfer',
      'duration': '35 min',
      'fare': 'RM 1.50',
      'walk': '8 min walk',
      'badge': 'Budget',
      'badgeIcon': null,
      'badgeColor': Colors.grey,
      'color': const Color(0xFF3B82F6),
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadGtfsData();
  }

  Future<void> _loadGtfsData() async {
    final stations = await _apiService.loadAllStations();
    setState(() {
      _allStations = stations;
      _filteredStations = stations;
      _isLoadingStations = false;
    });
  }

  void _showStationPicker(bool isOrigin) {
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final displayList = searchQuery.isEmpty
              ? _allStations
              : _allStations.where((s) => s.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOrigin ? 'Select Starting Point' : 'Select Destination',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          onChanged: (val) {
                            setModalState(() {
                              searchQuery = val;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search station...',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            prefixIcon: const Icon(Icons.search, color: Colors.grey),
                            filled: true,
                            fillColor: Colors.grey[100],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _isLoadingStations
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                      controller: scrollController,
                      itemCount: displayList.length,
                      separatorBuilder: (context, index) => Divider(color: Colors.grey[200], height: 1),
                      itemBuilder: (context, index) {
                        final station = displayList[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          title: Text(station.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Wrap(
                              spacing: 6,
                              children: station.lines.map((code) => _buildLineBadge(code)).toList(),
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              if (isOrigin) {
                                _selectedOrigin = station.name;
                              } else {
                                _selectedDestination = station.name;
                              }
                              _hasSearched = false;
                              _isJourneyConfirmed = false;
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontSize: 16)),
                      ),
                    ),
                  )
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLineBadge(String code) {
    Color bgColor;
    switch (code) {
      case 'KJ': bgColor = const Color(0xFFEF4444); break;
      case 'PY': bgColor = const Color(0xFF10B981); break;
      case 'KT': bgColor = const Color(0xFF22C55E); break;
      case 'MR': bgColor = const Color(0xFFF59E0B); break;
      case 'AG': bgColor = const Color(0xFF8B5CF6); break;
      case 'SP': bgColor = const Color(0xFF06B6D4); break;
      case 'KG': bgColor = const Color(0xFF14B8A6); break;
      case 'T': bgColor = const Color(0xFF6366F1); break;
      default: bgColor = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
      child: Text(code, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _swapStations() {
    setState(() {
      final temp = _selectedOrigin;
      _selectedOrigin = _selectedDestination;
      _selectedDestination = temp;
      _hasSearched = false;
      _isJourneyConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
              decoration: const BoxDecoration(color: Color(0xFF2563EB)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ROUTE OPTIMIZATION', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  SizedBox(height: 4),
                  Text('Journey Planning', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ROAD SEARCH', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildSelector(
                          label: 'ORIGIN',
                          value: _selectedOrigin ?? 'Select starting point',
                          dotColor: Colors.blue,
                          onTap: () => _showStationPicker(true),
                          isPlaceholder: _selectedOrigin == null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Divider(color: Colors.grey[200], thickness: 1),
                              GestureDetector(
                                onTap: _swapStations,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[200]!), shape: BoxShape.circle),
                                  child: const Icon(Icons.swap_vert, size: 20, color: Colors.grey),
                                ),
                              )
                            ],
                          ),
                        ),
                        _buildSelector(
                          label: 'DESTINATION',
                          value: _selectedDestination ?? 'Select destination',
                          dotColor: Colors.red,
                          onTap: () => _showStationPicker(false),
                          isPlaceholder: _selectedDestination == null,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (_selectedOrigin != null && _selectedDestination != null) ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            onPressed: (_selectedOrigin != null && _selectedDestination != null)
                                ? () {
                              setState(() {
                                _hasSearched = true;
                                _isJourneyConfirmed = false;
                              });
                            }
                                : null,
                            icon: const Icon(Icons.search, color: Colors.white),
                            label: const Text('Find Routes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hasSearched) ...[
                    const SizedBox(height: 30),
                    const Text('ROUTE COMPARISON', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    const SizedBox(height: 12),
                    ...List.generate(_routes.length, (index) => _buildRouteCard(index)),
                    const SizedBox(height: 30),
                    const Text('JOURNEY SUMMARY', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    const SizedBox(height: 12),
                    _buildJourneySummary(),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelector({required String label, required String value, required Color dotColor, required VoidCallback onTap, required bool isPlaceholder}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(child: Text(value, style: TextStyle(fontSize: 16, color: isPlaceholder ? Colors.grey[400] : const Color(0xFF1E293B), fontWeight: isPlaceholder ? FontWeight.normal : FontWeight.w600))),
                const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(int index) {
    final route = _routes[index];
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF2563EB) : Colors.transparent, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: route['color'], borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(route['id'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: route['badgeColor'].withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    children: [
                      if (route['badgeIcon'] != null) Icon(route['badgeIcon'], size: 10, color: route['badgeColor']),
                      if (route['badgeIcon'] != null) const SizedBox(width: 2),
                      Text(route['badge'], style: TextStyle(fontSize: 10, color: route['badgeColor'], fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(route['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(route['duration'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(width: 12),
                      const Icon(Icons.credit_card, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(route['fare'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(width: 12),
                      const Icon(Icons.directions_walk, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(route['walk'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  )
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? const Color(0xFF2563EB) : Colors.grey[300]!, width: 2),
                color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
              ),
              child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
            )
          ],
        ),
      ),
    );
  }

  Widget _buildJourneySummary() {
    final route = _routes[_selectedRouteIndex];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(_selectedOrigin ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.arrow_forward, color: Colors.blue, size: 20)),
                Expanded(child: Text(_selectedDestination ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: route['color'], borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Text(route['id'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 6),
                          Text(route['name'], style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    const Text('Recommended Route', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _buildInfoCard('DEPART', '8:20 AM')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildInfoCard('ARRIVE', '8:44 AM')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildInfoCard('DURATION', route['duration'])),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildInfoCardWithIcon('ESTIMATED FARE', route['fare'], Icons.credit_card)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildInfoCardWithIcon('WALK TO STATION', route['walk'], Icons.directions_walk)),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isJourneyConfirmed ? const Color(0xFFDCFCE7) : const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () => setState(() => _isJourneyConfirmed = true),
                    child: _isJourneyConfirmed
                        ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check, color: Color(0xFF16A34A)),
                        SizedBox(width: 8),
                        Text('Journey Confirmed', style: TextStyle(color: Color(0xFF16A34A), fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    )
                        : const Text('Start Journey', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInfoCardWithIcon(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}