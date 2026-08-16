import 'package:flutter/material.dart';
import 'dart:math';

class JourneyPlanningScreen extends StatefulWidget {
  const JourneyPlanningScreen({super.key});

  @override
  State<JourneyPlanningScreen> createState() => _JourneyPlanningScreenState();
}

class _JourneyPlanningScreenState extends State<JourneyPlanningScreen> {
  // Pre-populated list of major Rapid KL stations for the dropdowns
  final List<String> _stations = [
    'KL Sentral',
    'Bukit Bintang',
    'Pasar Seni',
    'KLCC',
    'Masjid Jamek',
    'Maluri',
    'Merdeka',
    'Titiwangsa',
    'Bandar Utama',
    'Putrajaya Sentral'
  ];

  String? _selectedOrigin = 'KL Sentral';
  String? _selectedDestination;
  bool _isLoading = false;
  List<Map<String, dynamic>> _routes = [];

  void _findRoutes() {
    // Validation
    if (_selectedOrigin == null || _selectedDestination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both origin and destination')),
      );
      return;
    }

    if (_selectedOrigin == _selectedDestination) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Origin and destination cannot be the same')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _routes = [];
    });

    // Simulating route calculation API response delay
    Future.delayed(const Duration(seconds: 1), () {
      final random = Random();

      // Dynamic fare and ETA generation based on Rapid KL fare structure simulation
      final double directFare = 1.50 + random.nextDouble() * 3.0;
      final int directEta = 5 + random.nextInt(20);

      final double transferFare = directFare + 0.80;
      final int transferEta = directEta + 10;

      setState(() {
        _isLoading = false;
        // Displaying possible route combinations
        _routes = [
          {
            'title': 'LRT / MRT (Direct)',
            'fare': 'RM ${directFare.toStringAsFixed(2)}',
            'eta': '$directEta min',
            'icon': Icons.train,
            'color': Colors.pink,
            'mode': 'Fastest Route',
          },
          {
            'title': 'Bus + Rail Transfer',
            'fare': 'RM ${transferFare.toStringAsFixed(2)}',
            'eta': '$transferEta min',
            'icon': Icons.directions_bus,
            'color': Colors.blue,
            'mode': 'Alternative',
          },
        ];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey Planning', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2563EB),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Origin Dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedOrigin,
                      decoration: InputDecoration(
                        labelText: 'Origin',
                        prefixIcon: const Icon(Icons.my_location, color: Colors.purple),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: _stations.map((station) {
                        return DropdownMenuItem(value: station, child: Text(station));
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedOrigin = value),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Icon(Icons.swap_vert, color: Colors.grey),
                    ),
                    // Destination Dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedDestination,
                      decoration: InputDecoration(
                        labelText: 'Destination',
                        prefixIcon: const Icon(Icons.location_on, color: Colors.pink),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: _stations.map((station) {
                        return DropdownMenuItem(value: station, child: Text(station));
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedDestination = value),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: _isLoading ? null : _findRoutes,
                      child: _isLoading
                          ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      )
                          : const Text('Find Routes', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Conditional Rendering based on state
            if (_routes.isNotEmpty) ...[
              Text(
                  'ROUTES: ${_selectedOrigin?.toUpperCase()} TO ${_selectedDestination?.toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final route = _routes[index];
                    return _buildRouteCard(
                      route['title'],
                      route['fare'],
                      route['eta'],
                      route['icon'],
                      route['color'],
                      route['mode'],
                    );
                  },
                ),
              ),
            ] else if (!_isLoading) ...[
              const Expanded(
                child: Center(
                  child: Text('Select stations and tap "Find Routes" to begin.', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildRouteCard(String title, String fare, String eta, IconData icon, Color color, String mode) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8)
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(mode, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.attach_money, size: 16, color: Colors.grey),
                Text(' Fare: $fare   '),
                const Icon(Icons.timer, size: 16, color: Colors.grey),
                Text(' ETA: $eta'),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Future implementation: Navigate to detailed route map
        },
      ),
    );
  }
}