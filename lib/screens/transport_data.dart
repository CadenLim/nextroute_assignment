import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TransportDataScreen extends StatefulWidget {
  const TransportDataScreen({super.key});

  @override
  State<TransportDataScreen> createState() => _TransportDataScreenState();
}

class _TransportDataScreenState extends State<TransportDataScreen> {
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> _stations = [
    {
      'name': 'KL Sentral',
      'lines': [
        {'label': 'KJ', 'color': Colors.pink},
        {'label': 'MR', 'color': Colors.lightGreen},
        {'label': 'KTM', 'color': Colors.blue},
        {'label': 'ERL', 'color': Colors.purple},
      ]
    },
    {
      'name': 'KLCC',
      'lines': [
        {'label': 'KJ', 'color': Colors.pink},
      ]
    },
    {
      'name': 'Bukit Bintang',
      'lines': [
        {'label': 'MR', 'color': Colors.lightGreen},
        {'label': 'MRT', 'color': Colors.green},
      ]
    },
    {
      'name': 'Pasar Seni',
      'lines': [
        {'label': 'KJ', 'color': Colors.pink},
        {'label': 'MRT', 'color': Colors.green},
      ]
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Your Station', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            color: const Color(0xFF2563EB),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Station',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Action Buttons (Nearby & Map)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(Icons.location_on, 'Nearby Stations', Colors.green),
                _buildActionButton(Icons.map, 'View Map', Colors.purple),
              ],
            ),
          ),

          const Divider(thickness: 1),

          // Station List
          Expanded(
            child: ListView.separated(
              itemCount: _stations.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final station = _stations[index];
                return ListTile(
                  leading: const Icon(Icons.business_outlined, color: Colors.grey),
                  title: Text(station['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Wrap(
                      spacing: 6,
                      children: (station['lines'] as List).map((line) {
                        return _buildLineBadge(line['label'], line['color']);
                      }).toList(),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StationDetailScreen(
                          stationName: station['name'],
                          lines: station['lines'],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color) {
    return InkWell(
      onTap: () {},
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildLineBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// STATION DETAIL SCREEN (Information, Timetable, Facilities Tabs)
// ----------------------------------------------------------------------

class StationDetailScreen extends StatefulWidget {
  final String stationName;
  final List<dynamic> lines;

  const StationDetailScreen({super.key, required this.stationName, required this.lines});

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  final ApiService _apiService = ApiService();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.stationName, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF2563EB),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Information'),
              Tab(text: 'Timetable'),
              Tab(text: 'Facilities'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildInfoTab(context),
            _buildTimetableTab(),
            _buildFacilitiesTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Station Address & Hours
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.location_city, color: Colors.blue),
            title: Text('Address', style: TextStyle(color: Colors.grey, fontSize: 12)),
            subtitle: Text('Jalan Stesen Sentral, 50470 Kuala Lumpur', style: TextStyle(color: Colors.black, fontSize: 16)),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.access_time, color: Colors.orange),
            title: Text('Operating Hours', style: TextStyle(color: Colors.grey, fontSize: 12)),
            subtitle: Text('5:30 AM - 12:00 AM', style: TextStyle(color: Colors.black, fontSize: 16)),
          ),
          const SizedBox(height: 16),

          // Live API Integration Card
          const Text('Live Bus Updates (API)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.blue.withValues(alpha: 0.3))),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: FutureBuilder<String>(
                future: _apiService.getRealtimeBusPositions(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Row(
                      children: [
                        SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 16),
                        Text('Connecting to data.gov.my...'),
                      ],
                    );
                  } else if (snapshot.hasError) {
                    return const Text('Failed to load live data', style: TextStyle(color: Colors.red));
                  }
                  return Row(
                    children: [
                      const Icon(Icons.satellite_alt, color: Colors.green),
                      const SizedBox(width: 16),
                      Expanded(child: Text(snapshot.data ?? 'No data', style: const TextStyle(fontWeight: FontWeight.w500))),
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 32),
          ElevatedButton.icon(
            icon: const Icon(Icons.map, color: Colors.white),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {},
            label: const Text('Open in Google Maps', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetableTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildTimePill('5:30 AM', Colors.green),
            const Text('-', style: TextStyle(fontSize: 24, color: Colors.grey)),
            _buildTimePill('11:58 PM', Colors.red),
          ],
        ),
        const SizedBox(height: 24),
        _buildTimetableRow('Next Train (Gombak)', 'Every 3-4 mins', Colors.pink),
        const Divider(),
        _buildTimetableRow('Next Train (Putra Heights)', 'Every 7-8 mins', Colors.pink),
        const Divider(),
        _buildTimetableRow('MRT (Kwasa Damansara)', 'Every 5 mins', Colors.green),
        const Divider(),
        _buildTimetableRow('MRT (Putrajaya Sentral)', 'Every 5 mins', Colors.green),
      ],
    );
  }

  Widget _buildTimePill(String time, Color color) {
    return Text(
      time,
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
    );
  }

  Widget _buildTimetableRow(String destination, String frequency, Color color) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.train, color: color),
      title: Text(destination),
      trailing: Text(frequency, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildFacilitiesTab() {
    return GridView.count(
      crossAxisCount: 3,
      padding: const EdgeInsets.all(16.0),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        _buildFacilityIcon(Icons.wc, 'Toilet', Colors.blue),
        _buildFacilityIcon(Icons.elevator, 'Elevator', Colors.orange),
        _buildFacilityIcon(Icons.local_parking, 'Parking', Colors.indigo),
        _buildFacilityIcon(Icons.atm, 'ATM', Colors.green),
        _buildFacilityIcon(Icons.wheelchair_pickup, 'Accessible', Colors.purple),
        _buildFacilityIcon(Icons.store, 'Retail', Colors.teal),
      ],
    );
  }

  Widget _buildFacilityIcon(IconData icon, String label, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: color),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}