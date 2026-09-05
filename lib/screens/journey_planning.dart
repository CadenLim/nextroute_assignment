import 'dart:async';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../services/personal_travel_service.dart';
import 'favourite_routes.dart';
import 'auth_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// =========================================================================
// ARCGIS ENTERPRISE STATIC MAP GENERATOR (NO API KEY REQUIRED)
// =========================================================================
String getStaticMapUrl(double lat, double lon, {double zoomDelta = 0.005}) {
  double minLon = lon - zoomDelta;
  double minLat = lat - zoomDelta;
  double maxLon = lon + zoomDelta;
  double maxLat = lat + zoomDelta;
  return 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/export?bbox=$minLon,$minLat,$maxLon,$maxLat&bboxSR=4326&imageSR=4326&size=800,800&f=image';
}

String getWideTopoMapUrl() {
  return 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/export?bbox=101.55,3.05,101.85,3.25&bboxSR=4326&imageSR=4326&size=1200,1200&f=image';
}

class JourneyPlanningScreen extends StatefulWidget {
  const JourneyPlanningScreen({
    super.key,
    this.savedRoute,
    this.apiService,
    this.savedRoutesRepository,
    this.authenticate,
  });

  final SavedRoute? savedRoute;
  final ApiService? apiService;
  final SavedRoutesRepository? savedRoutesRepository;
  final Future<bool> Function(BuildContext)? authenticate;

  @override
  State<JourneyPlanningScreen> createState() => _JourneyPlanningScreenState();
}

class _JourneyPlanningScreenState extends State<JourneyPlanningScreen> {
  late final ApiService _apiService;
  SavedRoutesRepository? _savedRoutesRepository;

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
  bool _isSavingRoute = false;
  final Set<String> _savedRouteKeys = {};
  String? _searchError;

  List<Map<String, dynamic>> _recentJourneys = [];
  bool _isLoadingRecent = true;

  final Color _primaryBlue = const Color(0xFF1E50D6);
  final Color _bgLight = const Color(0xFFF4F7FC);
  final Color _textDark = const Color(0xFF1E293B);
  final Color _textGrey = const Color(0xFF64748B);

  Timer? _debounceTimer;
  StreamSubscription<AuthState>? _authSubscription;
  List<Map<String, dynamic>> _livePlaces = [];
  bool _isSearchingPlaces = false;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _savedRoutesRepository = widget.savedRoutesRepository;

    if (_savedRoutesRepository == null && widget.authenticate == null) {
      _savedRoutesRepository = SupabaseSavedRoutesRepository();
    }

    if (widget.authenticate == null) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (!mounted) return;
        if (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.signedOut) {
          setState(() {
            _savedRouteKeys.clear();
            _recentJourneys = [];
          });
          _loadRecentJourneys();
          _loadSavedRouteKeys();
        }
      });
    }
    _initializeData();
  }

  Future<void> _initializeData() async {
    unawaited(_loadRecentJourneys());
    unawaited(_loadSavedRouteKeys());
    final stations = await _apiService.loadAllStations();

    if (mounted) {
      setState(() {
        _allStations = stations;
        _filteredStations = stations;
        _isLoading = false;
      });
      final saved = widget.savedRoute;
      if (saved != null) {
        _originDisplayName = saved.origin.name;
        _destinationDisplayName = saved.destination.name;
        _originGtfsStation = saved.resolveOrigin(stations);
        _destinationGtfsStation = saved.resolveDestination(stations);
        if (_originGtfsStation == null || _destinationGtfsStation == null) {
          setState(() => _searchError = 'A saved station is no longer available. Please select your locations again.');
        } else {
          await _handleSearch(preferredSignature: saved.signature);
        }
      }
    }
  }

  Future<void> _loadSavedRouteKeys() async {
    final repository = _savedRoutesRepository;
    if (repository == null) return;
    final userId = widget.savedRoutesRepository == null ? Supabase.instance.client.auth.currentUser?.id : null;
    if (widget.savedRoutesRepository == null && userId == null) {
      if (mounted) setState(_savedRouteKeys.clear);
      return;
    }
    try {
      final routes = await repository.load();
      if (!mounted) return;
      if (widget.savedRoutesRepository == null && Supabase.instance.client.auth.currentUser?.id != userId) {
        return;
      }
      setState(() {
        _savedRouteKeys
          ..clear()
          ..addAll(routes.map((route) => route.routeKey));
      });
    } catch (error) {
      debugPrint('Unable to load saved route markers: $error');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentJourneys() async {
    if (widget.authenticate != null) {
      if (mounted) setState(() => _isLoadingRecent = false);
      return;
    }
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('navigation_history')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(3);

        if (mounted && Supabase.instance.client.auth.currentUser?.id == user.id) {
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
      _searchError = null;
    });
  }

  Future<void> _handleSearch({String? preferredSignature}) async {
    if (_isLoading || _isSavingRoute || _isStartingNavigation) return;
    if (_originGtfsStation != null && _destinationGtfsStation != null) {
      if (_originGtfsStation!.ids.any(_destinationGtfsStation!.ids.contains)) {
        setState(() {
          _searchError = 'Choose different origin and destination stations.';
          _hasSearched = false;
        });
        return;
      }
      setState(() {
        _isLoading = true;
        _hasSearched = true;
        _searchError = null;
        _realRoutes = [];
      });

      try {
        final results = await _apiService.findRoutes(_originGtfsStation!, _destinationGtfsStation!);
        if (!mounted) return;

        final preferredIndex = results.indexWhere((route) => route['sig'] == preferredSignature);

        setState(() {
          _realRoutes = results;
          _selectedRouteIndex = preferredIndex < 0 ? 0 : preferredIndex;
          if (results.isEmpty) {
            _searchError = 'No routes found. Try another origin or destination.';
          }
        });

        if (preferredSignature != null && preferredIndex < 0 && results.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your saved route is unavailable. Showing other routes for these locations.')),
          );
        }
      } catch (_) {
        if (mounted) setState(() => _searchError = 'Unable to find routes. Please try again.');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  SavedRoute _routeToSave(Map<String, dynamic> route, String name) =>
      SavedRoute(
        name: name,
        origin: _originGtfsStation!,
        destination: _destinationGtfsStation!,
        signature: route['sig'] as String,
        lineName: (route['name'] ?? _getLineDetails(route)['name']).toString(),
      );

  Future<void> _saveRoute(Map<String, dynamic> route) async {
    if (_isSavingRoute) return;
    final defaultName = '$_originDisplayName → $_destinationDisplayName';
    final draft = _routeToSave(route, defaultName);

    if (!await (widget.authenticate ?? requireSignIn)(context) || !mounted) return;

    final name = await showRouteNameDialog(
      context,
      initialName: defaultName.length > 80 ? defaultName.substring(0, 80) : defaultName,
    );

    if (name == null || !mounted) return;
    setState(() => _isSavingRoute = true);

    try {
      final repository = _savedRoutesRepository ??= SupabaseSavedRoutesRepository();
      await repository.save(
        SavedRoute(
          name: name,
          origin: draft.origin,
          destination: draft.destination,
          signature: draft.signature,
          lineName: draft.lineName,
        ),
      );
      if (!mounted) return;
      setState(() => _savedRouteKeys.add(draft.routeKey));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route saved. Find it in Profile > Favourite Routes.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save route. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingRoute = false);
    }
  }

  StationModel _findNearestGtfsStation(double lat, double lon, String placeName) {
    String cleanSearchName = placeName.toUpperCase().replaceAll(RegExp(r'\([^)]+\)'), '').trim();
    List<String> combinedIds = [];
    Set<String> combinedLines = {};
    String determinedCategory = 'Mixed';

    if (lat == 0 && lon == 0) {
      String normSearch = cleanSearchName.replaceAll(RegExp(r'[^A-Z0-9]'), '');

      for (var station in _allStations) {
        String normStation = station.name.replaceAll(RegExp(r'\s*\([^)]+\)'), '').replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (normStation == normSearch && station.lat != 0 && station.lon != 0) {
          lat = station.lat;
          lon = station.lon;
          break;
        }
      }

      if (lat == 0 && lon == 0 && normSearch.length >= 4) {
        for (var station in _allStations) {
          String normStation = station.name.replaceAll(RegExp(r'\s*\([^)]+\)'), '').replaceAll(RegExp(r'[^A-Z0-9]'), '');
          if ((normStation.contains(normSearch) || normSearch.contains(normStation)) && station.lat != 0 && station.lon != 0) {
            lat = station.lat;
            lon = station.lon;
            break;
          }
        }
      }
    }

    if (lat != 0 && lon != 0) {
      double minDistance = double.infinity;
      StationModel? absoluteNearest;

      for (var station in _allStations) {
        if (station.lat != 0 && station.lon != 0) {
          var p = 0.017453292519943295;
          var a = 0.5 - cos((station.lat - lat) * p) / 2 +
              cos(lat * p) * cos(station.lat * p) * (1 - cos((station.lon - lon) * p)) / 2;
          double distance = 12742 * asin(sqrt(a));

          if (distance < minDistance) {
            minDistance = distance;
            absoluteNearest = station;
          }

          bool isExactMatch = cleanSearchName.isNotEmpty && station.name == cleanSearchName;
          bool isSafeSubstring = cleanSearchName.length >= 4 && station.name.contains(cleanSearchName);

          if (distance <= 1.2 || isExactMatch || isSafeSubstring) {
            combinedIds.addAll(station.ids);
            combinedLines.addAll(station.lines);
            if (station.category == 'Rail') determinedCategory = 'Rail';
          }
        }
      }

      if (combinedIds.isEmpty && absoluteNearest != null) {
        combinedIds.addAll(absoluteNearest.ids);
        combinedLines.addAll(absoluteNearest.lines);
      }

      if (absoluteNearest != null && minDistance < 0.1) {
        determinedCategory = absoluteNearest.category;
      }

      if (placeName == 'Selected on Map' && absoluteNearest != null) {
        placeName = absoluteNearest.name;
      }

    } else {
      String normSearch = cleanSearchName.replaceAll(RegExp(r'[^A-Z0-9]'), '');

      for (var station in _allStations) {
        String stationBaseName = station.name.replaceAll(RegExp(r'\s*\([^)]+\)'), '').trim();
        String normStation = stationBaseName.replaceAll(RegExp(r'[^A-Z0-9]'), '');

        bool isExact = normStation == normSearch;
        bool isSub1 = normSearch.length >= 4 && normStation.contains(normSearch);
        bool isSub2 = normStation.length >= 4 && normSearch.contains(normStation);

        if (isExact || isSub1 || isSub2) {
          combinedIds.addAll(station.ids);
          combinedLines.addAll(station.lines);
          if (station.category == 'Rail') determinedCategory = 'Rail';
        }
      }
    }

    return StationModel(
      ids: combinedIds.toSet().toList(),
      name: placeName,
      lines: combinedLines,
      category: determinedCategory,
      lat: lat,
      lon: lon,
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

  Future<void> _openMapPicker(bool isOrigin) async {
    Navigator.pop(context);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MapPickerMockScreen(allStations: _allStations)),
    );

    if (result != null) {
      final nearestStation = _findNearestGtfsStation(result['lat'], result['lon'], result['name']);
      setState(() {
        if (isOrigin) {
          _originDisplayName = nearestStation.name;
          _originGtfsStation = nearestStation;
        } else {
          _destinationDisplayName = nearestStation.name;
          _destinationGtfsStation = nearestStation;
        }
        _hasSearched = false;
        _searchError = null;
      });
    }
  }

  void _showLocationSearch(bool isOrigin) {
    if (_isLoading || _isSavingRoute || _isStartingNavigation) return;
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
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(backgroundColor: _primaryBlue.withValues(alpha: 0.1), child: Icon(Icons.map_rounded, color: _primaryBlue, size: 20)),
                            title: Text('Choose on map', style: TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue)),
                            trailing: Icon(Icons.chevron_right, color: Colors.grey[300]),
                            onTap: () => _openMapPicker(isOrigin),
                          ),
                          const Divider(height: 32),

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
                                  _searchError = null;
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
                                    _searchError = null;
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

      final signedIn = Supabase.instance.client.auth.currentUser != null;
      if (signedIn) {
        await _apiService.saveNavigationHistory(
          origin: _originDisplayName,
          destination: _destinationDisplayName,
          fare: farePrice,
          durationMinutes: totalMins,
          departureTime: departTime,
          estimatedArrivalTime: arriveTime,
          transitSteps: dbSafeSteps,
        );
      }

      await _loadRecentJourneys();

      if (mounted) {
        setState(() => _isStartingNavigation = false);
        _showLiveNavigationModal(route, totalMins, departTime, arriveTime, signedIn);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStartingNavigation = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    }
  }

  void _showLiveNavigationModal(Map<String, dynamic> route, int totalMins, String departTime, String arriveTime, bool signedIn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.95,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 24, left: 20, right: 20, bottom: 20),
                decoration: BoxDecoration(color: _primaryBlue, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                          child: const Row(
                            children: [
                              Icon(Icons.navigation, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('LIVE NAVIGATION', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Text(arriveTime, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Heading to $_destinationDisplayName', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('$totalMins mins remaining', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
                  ],
                ),
              ),

              _buildLiveMapCard(route: route),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildMoovitTimeline(route, departTime, arriveTime),
                ),
              ),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[50],
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(context);

                      setState(() {
                        _originDisplayName = '';
                        _originGtfsStation = null;
                        _destinationDisplayName = '';
                        _destinationGtfsStation = null;
                        _realRoutes = [];
                        _hasSearched = false;
                        _searchError = null;
                      });

                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          signedIn
                              ? 'Journey Completed! Welcome to your destination.'
                              : 'Journey completed. Sign in to save your travel history.',
                        ),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ));
                    },
                    child: const Text('End Journey', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // 🌟 FIX: Updated Map Preview Card to use OpenStreetMap (No API Key Required)
  Widget _buildLiveMapCard({Map<String, dynamic>? route}) {
    double lat = _originGtfsStation?.lat ?? 3.1341;
    double lon = _originGtfsStation?.lon ?? 101.6861;

    return GestureDetector(
      onTap: () {
        if (_originGtfsStation != null && _destinationGtfsStation != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RouteMapViewerScreen(
                origin: _originGtfsStation!,
                destination: _destinationGtfsStation!,
                route: route ?? (_realRoutes.isNotEmpty ? _realRoutes[_selectedRouteIndex] : null),
                allStations: _allStations,
              ),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 24, left: 20, right: 20),
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lon),
                    initialZoom: 14.0,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    // 🌟 USE OPENSTREETMAP - 100% FREE NO API KEY
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.nextroute.app',
                    ),
                    MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(lat, lon),
                            width: 40, height: 40,
                            child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                          )
                        ]
                    )
                  ],
                ),
              ),
              Positioned(
                bottom: 0, left: 0, right: 0, height: 80,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12, right: 12,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                  child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 16),
                ),
              ),
              Positioned(
                bottom: 12, left: 16, right: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.my_location, color: Colors.blue, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Live Boarding Location', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                          Text(_originDisplayName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                      child: const Text('ON TIME', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
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
      appBar: widget.savedRoute == null ? null : AppBar(title: const Text('Plan again')),
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

                    if (_searchError != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_searchError!, style: const TextStyle(color: Color(0xFF7C2D12))),
                      ),

                    const SizedBox(height: 32),

                    if (_isLoading)
                      const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator()))
                    else if (!_hasSearched)
                      _buildRecentJourneys()
                    else if (_realRoutes.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Column(
                              children: [
                                Icon(Icons.directions_transit_outlined, size: 64, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text('No transit routes found.', style: TextStyle(color: _textGrey, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        )
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
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
                  onTap: _isLoading || _isSavingRoute || _isStartingNavigation ? null : _swapLocations,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]),
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
              onPressed: !_isLoading && !_isSavingRoute && !_isStartingNavigation && _originGtfsStation != null && _destinationGtfsStation != null
                  ? () => _handleSearch()
                  : null,
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
                    decoration: BoxDecoration(color: lineColor.withValues(alpha: 0.1), shape: BoxShape.circle),
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
          final isSaved = _savedRouteKeys.contains(_routeToSave(route, '').routeKey);
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
                boxShadow: isSelected ? [BoxShadow(color: _primaryBlue.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))] : [],
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
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _buildRouteMetric(Icons.schedule, durationStr),
                            _buildRouteMetric(Icons.payments_outlined, fareStr),
                            _buildRouteMetric(Icons.directions_walk, '$walkMins min walk'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSaved) ...[
                        const Tooltip(
                          message: 'Saved route',
                          child: Icon(Icons.favorite, color: Color(0xFFE11D48), size: 23),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? _primaryBlue : Colors.white,
                            border: Border.all(color: isSelected ? _primaryBlue : Colors.grey[300]!, width: 2)
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                      ),
                    ],
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
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))]),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(color: _primaryBlue.withValues(alpha: 0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                child: Row(
                  children: [
                    Expanded(child: Text(_originDisplayName, style: TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Icon(Icons.arrow_forward, color: _primaryBlue.withValues(alpha: 0.5), size: 16)),
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
                      child: OutlinedButton.icon(
                        onPressed: _isSavingRoute || _isStartingNavigation || _savedRouteKeys.contains(_routeToSave(route, '').routeKey)
                            ? null
                            : () => _saveRoute(route),
                        icon: _isSavingRoute
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(
                          _savedRouteKeys.contains(_routeToSave(route, '').routeKey)
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                        label: Text(
                          _savedRouteKeys.contains(_routeToSave(route, '').routeKey) ? 'Saved' : 'Save route',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: _isStartingNavigation || _isSavingRoute
                            ? null
                            : () => _startNavigation(route, totalMins, departStr, arriveStr),
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

  Widget _buildRouteMetric(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _textGrey),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: _textGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
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

  Widget _buildMoovitTimeline(Map<String, dynamic> route, String departTime, String arriveTime) {
    List<Widget> nodes = [];
    List<dynamic> rawLegs = route['legs'] ?? [];

    nodes.add(_buildStationNode(_originDisplayName, departTime, type: 'start'));

    if (_originGtfsStation?.category == 'Mixed') {
      nodes.add(_buildWalkLeg('Walk to station', '5 min'));
    }

    String currentStation = _originDisplayName;

    for (int i = 0; i < rawLegs.length; i++) {
      var leg = rawLegs[i];

      if (leg['mode'] == 'Walk') {
        String transferStation = leg['desc'].replaceAll('Transfer at ', '');
        nodes.add(_buildWalkLeg('Transfer', leg['duration']));
        nodes.add(_buildStationNode(transferStation, 'Transfer', type: 'transfer'));
        currentStation = transferStation;
      } else {
        String endStation = _destinationDisplayName;
        if (i + 1 < rawLegs.length && rawLegs[i + 1]['mode'] == 'Walk') {
          endStation = rawLegs[i + 1]['desc'].replaceAll('Transfer at ', '');
        }

        nodes.add(ExpandableTransitLeg(
          leg: leg as Map<String, dynamic>,
          startStation: currentStation,
          endStation: endStation,
        ));
        currentStation = endStation;
      }
    }

    if (_destinationGtfsStation?.category == 'Mixed') {
      nodes.add(_buildWalkLeg('Walk to destination', '5 min'));
    }

    nodes.add(_buildStationNode(_destinationDisplayName, arriveTime, type: 'end'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: nodes,
    );
  }

  Widget _buildStationNode(String title, String time, {required String type}) {
    Color color = type == 'start' ? Colors.black : (type == 'end' ? Colors.green : Colors.orange);
    IconData icon = type == 'start' ? Icons.location_on : (type == 'end' ? Icons.location_on : Icons.adjust);

    return Row(
      children: [
        SizedBox(width: 48, child: Icon(icon, color: color, size: type == 'transfer' ? 16 : 24)),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
        Text(time, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildWalkLeg(String title, String duration) {
    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 48,
              height: 40,
              child: Center(
                  child: RotatedBox(
                      quarterTurns: 1,
                      child: const Text('......', style: TextStyle(color: Colors.grey, letterSpacing: 2, fontWeight: FontWeight.bold))
                  )
              )
          ),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                      children: [
                        const Icon(Icons.directions_walk, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(title, style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600, fontSize: 13)),
                        const Spacer(),
                        Text(duration, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 13))
                      ]
                  )
              )
          )
        ]
    );
  }
}

// =========================================================================
// EXPANDABLE ACCORDION LEG
// =========================================================================
class ExpandableTransitLeg extends StatefulWidget {
  final Map<String, dynamic> leg;
  final String startStation;
  final String endStation;

  const ExpandableTransitLeg({
    super.key,
    required this.leg,
    required this.startStation,
    required this.endStation,
  });

  @override
  State<ExpandableTransitLeg> createState() => _ExpandableTransitLegState();
}

class _ExpandableTransitLegState extends State<ExpandableTransitLeg> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    List<String> realStops = (widget.leg['intermediate_stops'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    int stopCount = realStops.length;

    if (stopCount == 0) {
      int durationMins = int.tryParse(widget.leg['duration'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 15;
      stopCount = (durationMins / 2.5).round();
      if (stopCount < 1) stopCount = 1;
    }

    Color color = widget.leg['color'] ?? Colors.blue;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: 4,
                height: _isExpanded ? (realStops.isEmpty ? stopCount * 28.0 + 60 : realStops.length * 28.0 + 60) : 60,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
            ],
          ),
        ),

        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              padding: const EdgeInsets.only(bottom: 20, top: 4),
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(widget.leg['icon'], size: 14, color: color),
                            const SizedBox(width: 6),
                            Text(
                              widget.leg['name'],
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        widget.leg['duration'],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey[500],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (!_isExpanded)
                    Text(
                      realStops.isEmpty ? 'Non-stop service' : 'Ride ${realStops.length} stops towards ${widget.endStation}',
                      style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600, fontSize: 13),
                    ),

                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: !_isExpanded
                        ? const SizedBox.shrink()
                        : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Board at: ${widget.startStation}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),

                          if (realStops.isNotEmpty)
                            for (String stopName in realStops)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.circle, size: 6, color: Colors.grey[400]),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(stopName, style: TextStyle(color: Colors.grey[600], fontSize: 12))),
                                  ],
                                ),
                              )
                          else
                            for (int i = 1; i <= stopCount; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.circle, size: 6, color: Colors.grey[400]),
                                    const SizedBox(width: 12),
                                    Text('Intermediate Stop $i', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                  ],
                                ),
                              ),

                          const SizedBox(height: 8),
                          Text('Alight at: ${widget.endStation}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// ROUTE MAP VIEWER (Displays Origin and Destination accurately)
// =========================================================================
class RouteMapViewerScreen extends StatefulWidget {
  final StationModel origin;
  final StationModel destination;
  final Map<String, dynamic>? route;
  final List<StationModel> allStations;

  const RouteMapViewerScreen({
    super.key,
    required this.origin,
    required this.destination,
    this.route,
    required this.allStations,
  });

  @override
  State<RouteMapViewerScreen> createState() => _RouteMapViewerScreenState();
}

class _RouteMapViewerScreenState extends State<RouteMapViewerScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _pathLatLngs = [];

  @override
  void initState() {
    super.initState();
    _calculatePath();
  }

  List<StationModel> _getWaypoints() {
    List<StationModel> pts = [widget.origin];
    if (widget.route != null) {
      String sig = widget.route!['sig'] ?? '';

      if (sig.startsWith('1X_')) {
        List<String> parts = sig.split('_');
        if (parts.length >= 3) {
          String sName = parts[2];
          var st = widget.allStations.where((s) => s.name == sName).firstOrNull;
          if (st != null) pts.add(st);
        }
      }
      else if (sig.startsWith('2X_')) {
        List<String> parts = sig.split('_');
        if (parts.length >= 5) {
          String sName1 = parts[2];
          String sName2 = parts[4];
          var st1 = widget.allStations.where((s) => s.name == sName1).firstOrNull;
          var st2 = widget.allStations.where((s) => s.name == sName2).firstOrNull;
          if (st1 != null) pts.add(st1);
          if (st2 != null) pts.add(st2);
        }
      }
    }
    pts.add(widget.destination);
    return pts;
  }

  void _calculatePath() {
    List<StationModel> waypoints = _getWaypoints();
    List<LatLng> path = [];

    for (int i = 0; i < waypoints.length - 1; i++) {
      var p1 = waypoints[i];
      var p2 = waypoints[i+1];
      path.add(LatLng(p1.lat, p1.lon));

      int numStops = 4;
      for (int j = 1; j <= numStops; j++) {
        double fraction = j / (numStops + 1);
        double ilat = p1.lat + (p2.lat - p1.lat) * fraction;
        double ilon = p1.lon + (p2.lon - p1.lon) * fraction;
        path.add(LatLng(ilat, ilon));
      }
    }
    path.add(LatLng(waypoints.last.lat, waypoints.last.lon));

    setState(() {
      _pathLatLngs = path;
    });
  }

  void _centerOnRoute() {
    if (_pathLatLngs.isEmpty) return;

    double minLat = _pathLatLngs.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = _pathLatLngs.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLon = _pathLatLngs.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLon = _pathLatLngs.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon)),
        padding: const EdgeInsets.all(60.0),
      ),
    );
  }

  Widget _buildStartPin() {
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF0033A0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.directions_subway, color: Colors.white, size: 20),
          ),
          Container(width: 2, height: 8, color: const Color(0xFF0033A0)),
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE91E63), width: 3),
            ),
          )
        ]
    );
  }

  Widget _buildEndPin() {
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF007A33),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.check_circle, color: Colors.white, size: 20),
          ),
          Container(width: 2, height: 8, color: const Color(0xFF007A33)),
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE91E63), width: 3),
            ),
          )
        ]
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 20),
            color: const Color(0xFF1E50D6),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                const Text('Route Map', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: _pathLatLngs.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(
                    (widget.origin.lat + widget.destination.lat) / 2,
                    (widget.origin.lon + widget.destination.lon) / 2
                ),
                initialZoom: 12.0,
                onMapReady: () => _centerOnRoute(),
              ),
              children: [
                // 🌟 FIX: Uses OpenStreetMap tiles (100% Free, NO API Key needed)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.nextroute.app',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _pathLatLngs,
                      color: const Color(0xFFE91E63),
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (int i = 1; i < _pathLatLngs.length - 1; i++)
                      Marker(
                        point: _pathLatLngs[i],
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE91E63), width: 3),
                          ),
                        ),
                      ),
                    Marker(
                      point: _pathLatLngs.first,
                      width: 60,
                      height: 60,
                      alignment: Alignment.topCenter,
                      child: _buildStartPin(),
                    ),
                    Marker(
                      point: _pathLatLngs.last,
                      width: 60,
                      height: 60,
                      alignment: Alignment.topCenter,
                      child: _buildEndPin(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white,
        onPressed: _centerOnRoute,
        child: const Icon(Icons.center_focus_strong, color: Color(0xFF1E50D6)),
      ),
    );
  }
}

// =========================================================================
// MAP PICKER MOCK SCREEN (FOR SEARCH)
// =========================================================================
class MapPickerMockScreen extends StatefulWidget {
  final List<StationModel> allStations;

  const MapPickerMockScreen({super.key, required this.allStations});

  @override
  State<MapPickerMockScreen> createState() => _MapPickerMockScreenState();
}

class _MapPickerMockScreenState extends State<MapPickerMockScreen> {
  bool _showRail = true;
  bool _showBus = true;
  bool _showFeeder = false;
  bool _showLive = false;

  final MapController _mapController = MapController();
  final LatLng _myLocation = const LatLng(3.1341, 101.6861);

  List<Map<String, dynamic>> _liveBuses = [];
  Timer? _liveDataTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _liveDataTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchLiveBuses() async {
    if (!_showLive) return;

    try {
      final url = Uri.parse('https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final feed = FeedMessage.fromBuffer(response.bodyBytes);
        List<Map<String, dynamic>> updatedBuses = [];

        for (var entity in feed.entity) {
          if (entity.hasVehicle()) {
            var vehicle = entity.vehicle;
            if (vehicle.hasPosition()) {
              updatedBuses.add({
                'id': entity.id,
                'lat': vehicle.position.latitude,
                'lon': vehicle.position.longitude,
                'route': vehicle.trip.routeId,
              });
            }
          }
        }

        if (mounted) {
          setState(() {
            _liveBuses = updatedBuses;
          });
        }
      }
    } catch (e) {
      debugPrint("Live Bus fetch error: $e");
    }
  }

  void _centerOnUser() {
    _mapController.move(_myLocation, 13.0);
  }

  // 🌟 FIX: Completely overhauled the marker builder to show Full Names and prevent Overflow
  Widget _buildMarker(Map<String, dynamic> station) {
    bool isRail = station['type'] == 'Rail';
    Color bgColor = isRail ? const Color(0xFF64748B) : Colors.orange;
    IconData icon = isRail ? Icons.train : Icons.directions_bus;

    // The exact station name from GTFS
    String stationName = station['name']?.toString() ?? 'Station';

    return GestureDetector(
      onTap: () {
        Navigator.pop(context, {
          'lat': station['lat'],
          'lon': station['lon'],
          'name': station['name'],
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12), // Pill shape for names
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Text(
                  stationName,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -4),
            child: Icon(Icons.arrow_drop_down, color: bgColor, size: 20),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildStaticMapMarkers() {
    List<Marker> markers = [];
    int busCount = 0;
    int railCount = 0;

    for (var station in widget.allStations) {
      if (station.lat == 0 || station.lon == 0) continue;

      bool isRail = station.category == 'Rail';

      if (isRail && _showRail && railCount < 60) {
        markers.add(Marker(
          point: LatLng(station.lat, station.lon),
          // 🌟 FIX: Expanded the width dynamically so long names fit perfectly
          width: 140, height: 60,
          alignment: Alignment.topCenter,
          child: _buildMarker({'name': station.name, 'type': 'Rail', 'lat': station.lat, 'lon': station.lon}),
        ));
        railCount++;
      } else if (!isRail && _showBus && busCount < 60) {
        markers.add(Marker(
          point: LatLng(station.lat, station.lon),
          width: 140, height: 60,
          alignment: Alignment.topCenter,
          child: _buildMarker({'name': station.name, 'type': 'Bus', 'lat': station.lat, 'lon': station.lon}),
        ));
        busCount++;
      }
    }
    return markers;
  }

  // 🌟 FIX: Overhauled Live Tracker markers to prevent Overflow
  List<Marker> _buildLiveTrackers() {
    if (!_showLive) return [];

    List<Marker> liveMarkers = [];

    for (var bus in _liveBuses) {
      liveMarkers.add(Marker(
        point: LatLng(bus['lat'], bus['lon']),
        // 🌟 FIX: Expanded the width dynamically
        width: 100, height: 60,
        alignment: Alignment.topCenter,
        child: _buildLiveVehicleIcon(bus['route']?.toString() ?? 'BUS'),
      ));
    }

    return liveMarkers;
  }

  Widget _buildLiveVehicleIcon(String routeId) {
    String shortName = routeId.length > 6 ? routeId.substring(0, 6) : routeId;
    Color vColor = Colors.redAccent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: vColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: vColor.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 2)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.directions_bus, color: Colors.white, size: 10),
              const SizedBox(width: 4),
              Text(
                  shortName,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Icon(Icons.arrow_drop_down, color: vColor, size: 20),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, Function(bool) onToggle, {IconData? icon}) {
    return InkWell(
        onTap: () => onToggle(!isSelected),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.grey[100] : Colors.transparent,
              border: Border.all(color: isSelected ? Colors.grey[400]! : Colors.grey[200]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
                children: [
                  if (isSelected && icon == null) ...[
                    const Icon(Icons.check, size: 14, color: Colors.black87),
                    const SizedBox(width: 4),
                  ],
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: isSelected ? Colors.red : Colors.grey[700]),
                    const SizedBox(width: 4),
                  ],
                  Text(label, style: TextStyle(color: isSelected && icon != null ? Colors.red : Colors.black87, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                ]
            )
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    String liveText = _liveBuses.isNotEmpty ? 'Live (${_liveBuses.length})' : 'Live Tracking';

    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 20),
            color: const Color(0xFF8B5CF6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Row(
                    children: [
                      Icon(Icons.chevron_left, color: Colors.white, size: 24),
                      Text('Back', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Live Transit Map', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Choose a transport category to keep the map clear', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),

          Expanded(
            child: Stack(
              children: [
                // 🌟 FIX: Uses OpenStreetMap tiles (100% Free, NO API Key needed)
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _myLocation,
                    initialZoom: 13.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.nextroute.app',
                    ),
                    MarkerLayer(
                      markers: [
                        ..._buildStaticMapMarkers(),
                        ..._buildLiveTrackers(),

                        Marker(
                          point: _myLocation,
                          width: 40, height: 40,
                          child: Container(
                            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.2), shape: BoxShape.circle),
                            child: Center(
                              child: Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.blue, shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                Positioned(
                  top: 16, left: 16, right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                          children: [
                            _buildFilterChip('Rail', _showRail, (v) => setState(()=> _showRail = v)),
                            const SizedBox(width: 8),
                            _buildFilterChip('Bus stops', _showBus, (v) => setState(()=> _showBus = v)),
                            const SizedBox(width: 8),
                            _buildFilterChip('MRT feeder', _showFeeder, (v) => setState(()=> _showFeeder = v)),
                            const SizedBox(width: 8),

                            _buildFilterChip(liveText, _showLive, (v) {
                              setState(() => _showLive = v);
                              if (v) {
                                _fetchLiveBuses();
                                _liveDataTimer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchLiveBuses());
                              } else {
                                _liveDataTimer?.cancel();
                              }
                            }, icon: Icons.sensors),

                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.grey),
                              onPressed: _showLive ? _fetchLiveBuses : null,
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                          ]
                      ),
                    ),
                  ),
                ),

                Positioned(
                  bottom: 24, right: 24,
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    onPressed: _centerOnUser,
                    child: const Icon(Icons.my_location, color: Color(0xFF8B5CF6)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}