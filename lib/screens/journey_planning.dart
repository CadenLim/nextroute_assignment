import 'dart:async';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../localization/app_language.dart';
import '../services/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JourneyPlanningScreen extends StatefulWidget {
  const JourneyPlanningScreen({super.key});

  @override
  State<JourneyPlanningScreen> createState() => _JourneyPlanningScreenState();
}

class _JourneyPlanningScreenState extends State<JourneyPlanningScreen> {
  final ApiService _apiService = ApiService();

  List<StationModel> _allStations = [];
  List<StationModel> _filteredStations = [];
  List<Map<String, dynamic>> _realRoutes = [];
  bool _isLoading = true;

  String _originDisplayName = '';
  StationModel? _originGtfsStation;

  String _destinationDisplayName = '';
  StationModel? _destinationGtfsStation;

  bool _hasSearched = false;
  int _selectedRouteIndex = 0;
  bool _isStartingNavigation = false;

  List<Map<String, dynamic>> _recentJourneys = [];
  bool _isLoadingRecent = true;

  final Color _primaryBlue = const Color(0xFF1E50D6);
  final Color _bgLight = const Color(0xFFF4F7FC);
  final Color _textDark = const Color(0xFF1E293B);
  final Color _textGrey = const Color(0xFF64748B);

  Timer? _debounceTimer;
  List<Map<String, dynamic>> _livePlaces = [];
  bool _isSearchingPlaces = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    final stations = await _apiService.loadAllStations();
    await _loadRecentJourneys();

    if (mounted) {
      setState(() {
        _allStations = stations;
        _filteredStations = stations;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRecentJourneys() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('navigation_history')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(3);

        if (mounted) {
          setState(() {
            _recentJourneys = List<Map<String, dynamic>>.from(response);
            _isLoadingRecent = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingRecent = false);
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted) setState(() => _isLoadingRecent = false);
    }
  }

  void _swapLocations() {
    setState(() {
      final tempName = _originDisplayName;
      _originDisplayName = _destinationDisplayName;
      _destinationDisplayName = tempName;

      final tempStation = _originGtfsStation;
      _originGtfsStation = _destinationGtfsStation;
      _destinationGtfsStation = tempStation;

      _hasSearched = false;
    });
  }

  Future<void> _handleSearch() async {
    if (_originGtfsStation != null && _destinationGtfsStation != null) {
      setState(() {
        _isLoading = true;
        _hasSearched = true;
      });

      final results = await _apiService.findRoutes(_originGtfsStation!, _destinationGtfsStation!);

      if (mounted) {
        setState(() {
          _realRoutes = results;
          _isLoading = false;
          _selectedRouteIndex = 0;
        });
      }
    }
  }

  StationModel _findNearestGtfsStation(double lat, double lon, String placeName) {
    StationModel? absoluteNearest;
    double minDistance = double.infinity;

    String cleanSearchName = placeName.toUpperCase().replaceAll(RegExp(r'\([^)]+\)'), '').trim();

    for (var station in _allStations) {
      bool validGps = station.lat != 0 && station.lon != 0;

      if (validGps && lat != 0 && lon != 0) {
        var p = 0.017453292519943295;
        var a = 0.5 - cos((station.lat - lat) * p) / 2 +
            cos(lat * p) * cos(station.lat * p) * (1 - cos((station.lon - lon) * p)) / 2;
        double distance = 12742 * asin(sqrt(a));

        if (distance < minDistance) {
          minDistance = distance;
          absoluteNearest = station;
        }
      }
    }

    if (absoluteNearest == null) {
      for (var station in _allStations) {
        if (station.name == cleanSearchName) {
          absoluteNearest = station;
          break;
        }
      }
    }

    if (absoluteNearest != null) {
      return StationModel(
        ids: absoluteNearest.ids,
        name: placeName,
        lines: absoluteNearest.lines,
        category: absoluteNearest.category,
        lat: absoluteNearest.lat,
        lon: absoluteNearest.lon,
      );
    }

    return StationModel(
      ids: [], name: placeName, lines: {}, category: 'Mixed', lat: lat, lon: lon,
    );
  }

  void _onSearchQueryChanged(String query) {
    setState(() {
      _filteredStations = _allStations
          .where((s) => s.name.toLowerCase().contains(query.toLowerCase()) || s.lines.any((l) => l.toLowerCase().contains(query.toLowerCase())))
          .toList();
    });

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      if (query.trim().isEmpty) return;

      setState(() => _isSearchingPlaces = true);
      try {
        final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query, Malaysia&format=json&limit=5');
        final response = await http.get(url, headers: {'User-Agent': 'NextRoute_Project'});

        if (response.statusCode == 200) {
          final List data = json.decode(response.body);
          if (mounted) {
            setState(() {
              _livePlaces = data.map((e) => {
                'name': e['name'] ?? 'Unknown Place',
                'desc': e['display_name'] ?? '',
                'lat': double.tryParse(e['lat'].toString()) ?? 0.0,
                'lon': double.tryParse(e['lon'].toString()) ?? 0.0,
              }).toList();
            });
          }
        }
      } catch (e) {
        debugPrint('OSM Map API Error: $e');
      } finally {
        if (mounted) setState(() => _isSearchingPlaces = false);
      }
    });
  }

  void _showLocationSearch(bool isOrigin) {
    setState(() {
      _filteredStations = List.from(_allStations);
      _livePlaces = [];
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.9,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                    Text(isOrigin ? 'Start from' : 'Where to?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _textDark)),
                    const SizedBox(height: 16),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search map, places, or stations...',
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: _isSearchingPlaces ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                        filled: true, fillColor: Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      onChanged: (value) {
                        _onSearchQueryChanged(value);
                        Future.delayed(const Duration(milliseconds: 900), () { if (mounted) setModalState((){}); });
                        setModalState((){});
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        children: [
                          if (_livePlaces.isNotEmpty) ...[
                            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('PLACES FROM MAP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textGrey))),
                            ..._livePlaces.map((place) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(backgroundColor: Colors.orange[50], child: const Icon(Icons.place, color: Colors.orange, size: 20)),
                              title: Text(place['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(place['desc'], style: TextStyle(color: Colors.grey[600], fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                final nearestStation = _findNearestGtfsStation(place['lat'], place['lon'], place['name']);
                                setState(() {
                                  if (isOrigin) { _originDisplayName = place['name']; _originGtfsStation = nearestStation; }
                                  else { _destinationDisplayName = place['name']; _destinationGtfsStation = nearestStation; }
                                  _hasSearched = false;
                                });
                                Navigator.pop(context);
                              },
                            )),
                            const Divider(height: 32),
                          ],
                          if (_filteredStations.isNotEmpty) ...[
                            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('STATIONS & BUS STOPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textGrey))),
                            ..._filteredStations.map((station) {
                              final isRail = station.category == 'Rail';
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(backgroundColor: isRail ? Colors.blue[50] : Colors.red[50], child: Icon(isRail ? Icons.train : Icons.directions_bus, color: isRail ? Colors.blue : Colors.red, size: 20)),
                                title: Text(station.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(station.lines.join(' • '), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                onTap: () {
                                  final finalStation = _findNearestGtfsStation(station.lat, station.lon, station.name);
                                  setState(() {
                                    if (isOrigin) { _originDisplayName = station.name; _originGtfsStation = finalStation; }
                                    else { _destinationDisplayName = station.name; _destinationGtfsStation = finalStation; }
                                    _hasSearched = false;
                                  });
                                  Navigator.pop(context);
                                },
                              );
                            }),
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startNavigation(Map<String, dynamic> route, int totalMins, String departTime, String arriveTime) async {
    setState(() => _isStartingNavigation = true);
    try {
      double farePrice = double.tryParse(route['fare'].toString().replaceAll('RM ', '').trim()) ?? 0.0;
      List<Map<String, dynamic>> dbSafeSteps = [];
      if (route['legs'] != null) {
        for (var leg in (route['legs'] as List)) {
          if (leg is Map) {
            dbSafeSteps.add({
              'mode': leg['mode'] ?? 'Transit',
              'name': leg['name'] ?? '',
              'duration': leg['duration'] ?? '',
              'desc': leg['desc'] ?? '',
            });
          }
        }
      }

      await _apiService.saveNavigationHistory(
        origin: _originDisplayName, destination: _destinationDisplayName, fare: farePrice,
        durationMinutes: totalMins, departureTime: departTime, estimatedArrivalTime: arriveTime, transitSteps: dbSafeSteps,
      );

      // --- NEW: Reload history from Supabase after saving ---
      await _loadRecentJourneys();

      if (mounted) {
        // --- NEW: Clear search states to return to Recent Journeys view ---
        setState(() {
          _originDisplayName = '';
          _originGtfsStation = null;
          _destinationDisplayName = '';
          _destinationGtfsStation = null;
          _realRoutes = [];
          _hasSearched = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Journey successfully started and saved!'),
            backgroundColor: Colors.green
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isStartingNavigation = false);
    }
  }

  int _calculateWalkMins(Map<String, dynamic> route) {
    int walkMins = 0;
    if (_originGtfsStation?.category == 'Mixed') walkMins += 5;
    if (_destinationGtfsStation?.category == 'Mixed') walkMins += 5;
    if (route['legs'] != null) {
      for (var leg in (route['legs'] as List)) {
        if (leg is Map && leg['mode'] == 'Walk') {
          walkMins += int.tryParse(leg['duration'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        }
      }
    }
    return walkMins;
  }

  Map<String, dynamic> _getLineDetails(Map<String, dynamic> route) {
    final List legs = (route['legs'] is List) ? (route['legs'] as List) : [];
    Map<String, dynamic> mainLeg = {};

    for (var leg in legs) {
      if (leg is Map && leg['mode'] == 'Rail') {
        mainLeg = Map<String, dynamic>.from(leg);
        break;
      }
    }

    if (mainLeg.isEmpty) {
      for (var leg in legs) {
        if (leg is Map && leg['mode'] == 'Bus') {
          mainLeg = Map<String, dynamic>.from(leg);
          break;
        }
      }
    }

    if (mainLeg.isEmpty && legs.isNotEmpty && legs.first is Map) {
      mainLeg = Map<String, dynamic>.from(legs.first as Map);
    }

    String name = (mainLeg['name'] ?? 'Transit').toString().toUpperCase();
    String code = 'BUS';
    Color color = (mainLeg['color'] is Color) ? mainLeg['color'] as Color : _primaryBlue;

    if (name.contains('KELANA JAYA')) { code = 'KJ'; color = const Color(0xFFE11D48); }
    else if (name.contains('KAJANG')) { code = 'KG'; color = const Color(0xFF15803D); }
    else if (name.contains('PUTRAJAYA')) { code = 'PY'; color = const Color(0xFF059669); }
    else if (name.contains('AMPANG')) { code = 'AG'; color = const Color(0xFFF97316); }
    else if (name.contains('SRI PETALING')) { code = 'SP'; color = const Color(0xFF7F1D1D); }
    else if (name.contains('MONORAIL')) { code = 'MR'; color = const Color(0xFF84CC16); }
    else if (name.contains('BRT')) { code = 'B1'; color = const Color(0xFF14532D); }

    return {'code': code, 'color': color, 'name': mainLeg['name'] ?? name};
  }

  String _formatTime(String? time24) {
    if (time24 == null || !time24.contains(':')) return '8:00 AM';
    try {
      final parts = time24.split(':');
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
      return DateFormat('h:mm a').format(dt);
    } catch (e) { return time24; }
  }

  String _calculateArrival(String? time24, int durationMins) {
    if (time24 == null || !time24.contains(':')) return '8:30 AM';
    try {
      final parts = time24.split(':');
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1])).add(Duration(minutes: durationMins));
      return DateFormat('h:mm a').format(dt);
    } catch (e) { return time24; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgLight,
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Stack(
          children: [
            Container(height: 280, color: _primaryBlue),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ROUTE OPTIMIZATION', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    const Text('Journey Planning', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 32),

                    _buildRoadSearchCard(),
                    const SizedBox(height: 32),

                    if (_isLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator()))
                    else if (!_hasSearched)
                      _buildRecentJourneys()
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRouteComparisonList(),
                          const SizedBox(height: 32),
                          _buildJourneySummaryCard(),
                          const SizedBox(height: 40),
                        ],
                      )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoadSearchCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ROAD SEARCH', style: TextStyle(color: _textGrey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 16),

          Stack(
            alignment: Alignment.center,
            children: [
              Column(
                children: [
                  _buildSearchField(
                      label: 'ORIGIN',
                      value: _originDisplayName.isEmpty ? 'Origin Location' : _originDisplayName,
                      isHint: _originDisplayName.isEmpty,
                      dotColor: _primaryBlue,
                      onTap: () => _showLocationSearch(true)
                  ),
                  const SizedBox(height: 12),
                  _buildSearchField(
                      label: 'DESTINATION',
                      value: _destinationDisplayName.isEmpty ? 'Destination Location' : _destinationDisplayName,
                      isHint: _destinationDisplayName.isEmpty,
                      dotColor: const Color(0xFFEF4444),
                      onTap: () => _showLocationSearch(false)
                  ),
                ],
              ),
              Positioned(
                child: GestureDetector(
                  onTap: _swapLocations,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]),
                    child: Icon(Icons.swap_vert, color: _textGrey, size: 20),
                  ),
                ),
              )
            ],
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Find Routes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: _originGtfsStation != null && _destinationGtfsStation != null ? _handleSearch : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField({required String label, required String value, required bool isHint, required Color dotColor, required VoidCallback onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: _textGrey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(child: Text(value, style: TextStyle(fontSize: 15, color: isHint ? Colors.grey[400] : _textDark, fontWeight: isHint ? FontWeight.normal : FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Icon(Icons.keyboard_arrow_down, color: _textGrey, size: 20),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildRecentJourneys() {
    if (_isLoadingRecent) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }

    if (_recentJourneys.isEmpty) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('RECENT JOURNEYS', style: TextStyle(color: _textGrey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            // --- NEW: Added clear all functionality linked to Supabase ---
            TextButton(
                onPressed: () async {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user != null) {
                    setState(() => _isLoadingRecent = true);
                    await Supabase.instance.client.from('navigation_history').delete().eq('user_id', user.id);
                    await _loadRecentJourneys();
                  }
                },
                child: Text('Clear all', style: TextStyle(color: _primaryBlue, fontSize: 12, fontWeight: FontWeight.bold))
            )
          ],
        ),

        ..._recentJourneys.map((journey) {
          final origin = journey['origin'] ?? 'Unknown';
          final dest = journey['destination'] ?? 'Unknown';
          final fare = journey['fare'] ?? 0.0;
          final duration = journey['duration_minutes'] ?? 0;

          String lineCode = 'RT';
          Color lineColor = Colors.blue;
          String lineName = 'Transit';

          if (journey['transit_steps'] != null && (journey['transit_steps'] is List) && (journey['transit_steps'] as List).isNotEmpty) {
            try {
              final List steps = journey['transit_steps'] as List;
              Map<String, dynamic> mainStep = {};
              for (var s in steps) {
                if (s is Map && s['mode'] == 'Rail') {
                  mainStep = Map<String, dynamic>.from(s);
                  break;
                }
              }
              if (mainStep.isEmpty && steps.first is Map) {
                mainStep = Map<String, dynamic>.from(steps.first as Map);
              }

              lineName = (mainStep['name'] ?? 'Transit').toString();
              String upperName = lineName.toUpperCase();

              if (upperName.contains('KELANA JAYA')) { lineCode = 'KJ'; lineColor = const Color(0xFFE11D48); }
              else if (upperName.contains('KAJANG')) { lineCode = 'KG'; lineColor = const Color(0xFF15803D); }
              else if (upperName.contains('PUTRAJAYA')) { lineCode = 'PY'; lineColor = const Color(0xFF059669); }
              else if (upperName.contains('AMPANG')) { lineCode = 'AG'; lineColor = const Color(0xFFF97316); }
              else if (upperName.contains('MONORAIL')) { lineCode = 'MR'; lineColor = const Color(0xFF84CC16); }
            } catch (_) {}
          }

          return GestureDetector(
            onTap: () {
              setState(() {
                _originDisplayName = origin;
                _destinationDisplayName = dest;
                _originGtfsStation = _findNearestGtfsStation(0, 0, origin);
                _destinationGtfsStation = _findNearestGtfsStation(0, 0, dest);
              });
              _handleSearch();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: lineColor.withOpacity(0.1), shape: BoxShape.circle),
                    child: Text(lineCode, style: TextStyle(color: lineColor, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(origin, style: TextStyle(fontWeight: FontWeight.bold, color: _textDark, fontSize: 14), overflow: TextOverflow.ellipsis)),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward, size: 12, color: Colors.grey)),
                            Expanded(child: Text(dest, style: TextStyle(fontWeight: FontWeight.bold, color: _textDark, fontSize: 14), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('$lineName • RM ${fare.toStringAsFixed(2)} • $duration min', style: TextStyle(color: _textGrey, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[300]),
                ],
              ),
            ),
          );
        })
      ],
    );
  }

  Widget _buildRouteComparisonList() {
    if (_realRoutes.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ROUTE COMPARISON', style: TextStyle(color: _textGrey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        const SizedBox(height: 16),
        ...List.generate(_realRoutes.length, (index) {
          final route = _realRoutes[index];
          final isSelected = _selectedRouteIndex == index;
          final lineDetails = _getLineDetails(route);
          final walkMins = _calculateWalkMins(route);
          final String durationStr = route['duration'] ?? '20 min';
          final String fareStr = route['fare'] ?? 'RM 2.00';

          String tagText = ''; Color tagColor = Colors.grey; IconData tagIcon = Icons.star;
          if (index == 0) { tagText = 'Fastest'; tagColor = Colors.orange; tagIcon = Icons.bolt; }
          else if (route['badge'] == 'Direct') { tagText = 'Direct'; tagColor = Colors.green; tagIcon = Icons.check_circle; }
          else if (index == 1) { tagText = 'Scenic'; tagColor = Colors.blue; tagIcon = Icons.landscape; }
          else { tagText = 'Budget'; tagColor = Colors.purple; tagIcon = Icons.savings; }

          return GestureDetector(
            onTap: () => setState(() => _selectedRouteIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isSelected ? _primaryBlue : Colors.grey[200]!, width: isSelected ? 2 : 1),
                boxShadow: isSelected ? [BoxShadow(color: _primaryBlue.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))] : [],
              ),
              child: Row(
                children: [
                  Column(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: lineDetails['color'], borderRadius: BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: Text(lineDetails['code'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(tagIcon, size: 10, color: tagColor),
                          const SizedBox(width: 2),
                          Text(tagText, style: TextStyle(color: _textGrey, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(route['badge'] == 'Direct' ? lineDetails['name'] : (route['name'] ?? ''), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _textDark)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 12, color: _textGrey), const SizedBox(width: 4),
                            Text(durationStr, style: TextStyle(fontSize: 12, color: _textGrey, fontWeight: FontWeight.w500)),
                            const SizedBox(width: 12),
                            Container(width: 12, height: 2, color: lineDetails['color']), const SizedBox(width: 4),
                            Text(fareStr, style: TextStyle(fontSize: 12, color: _textGrey, fontWeight: FontWeight.w500)),
                            const SizedBox(width: 12),
                            Icon(Icons.directions_walk, size: 12, color: _textGrey), const SizedBox(width: 4),
                            Text('$walkMins min walk', style: TextStyle(fontSize: 12, color: _textGrey, fontWeight: FontWeight.w500)),
                          ],
                        )
                      ],
                    ),
                  ),
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? _primaryBlue : Colors.white,
                        border: Border.all(color: isSelected ? _primaryBlue : Colors.grey[300]!, width: 2)
                    ),
                    child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                  )
                ],
              ),
            ),
          );
        })
      ],
    );
  }

  Widget _buildJourneySummaryCard() {
    if (_realRoutes.isEmpty) return const SizedBox();

    final route = _realRoutes[_selectedRouteIndex];
    final lineDetails = _getLineDetails(route);

    int transitMins = int.tryParse(route['duration'].toString().split(' ')[0]) ?? 20;
    int walkMins = _calculateWalkMins(route);
    int totalMins = transitMins + walkMins;

    final String departStr = _formatTime(route['scheduledDepart'] ?? DateFormat('HH:mm').format(DateTime.now()));
    final String arriveStr = _calculateArrival(route['scheduledDepart'] ?? DateFormat('HH:mm').format(DateTime.now()), totalMins);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('JOURNEY SUMMARY', style: TextStyle(color: _textGrey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))]),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(color: _primaryBlue.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                child: Row(
                  children: [
                    Expanded(child: Text(_originDisplayName, style: TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Icon(Icons.arrow_forward, color: _primaryBlue.withOpacity(0.5), size: 16)),
                    Expanded(child: Text(_destinationDisplayName, style: TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue, fontSize: 15), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
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
                          decoration: BoxDecoration(color: lineDetails['color'], borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Text(lineDetails['code'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 6),
                              Text(lineDetails['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        const Text('Recommended Route', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(child: _buildInfoBlock('DEPART', departStr)),
                        Container(width: 1, height: 40, color: Colors.grey[200]),
                        Expanded(child: _buildInfoBlock('ARRIVE', arriveStr)),
                        Container(width: 1, height: 40, color: Colors.grey[200]),
                        Expanded(child: _buildInfoBlock('DURATION', '$totalMins min')),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                            child: Row(
                              children: [
                                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.credit_card, color: Colors.blue, size: 20)),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('ESTIMATED FARE', style: TextStyle(fontSize: 10, color: _textGrey, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(route['fare'] ?? 'RM 2.00', style: TextStyle(fontSize: 16, color: _textDark, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            )
                        ),
                        Expanded(
                            child: Row(
                              children: [
                                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.directions_walk, color: Colors.orange, size: 20)),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('WALK TO STATION', style: TextStyle(fontSize: 10, color: _textGrey, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text('$walkMins min', style: TextStyle(fontSize: 16, color: _textDark, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            )
                        )
                      ],
                    ),

                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: _isStartingNavigation ? null : () => _startNavigation(route, totalMins, departStr, arriveStr),
                        child: _isStartingNavigation
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Start Journey', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    )
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildInfoBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(color: _textGrey, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: _textDark, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}