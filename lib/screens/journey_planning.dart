// journey_planning.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' show asin, cos, sqrt;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/estimated_lrt_layer.dart';
import '../services/route_geometry.dart';
import '../services/personal_travel_service.dart';
import '../services/personal_assistance_functions.dart';
import '../services/module5_user_route_context.dart';
import 'analytics_centre.dart';
import 'favourite_routes.dart';
import 'auth_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// =========================================================================
// 🌟 内存状态缓存（防止切换 Tab 页面被销毁后状态重置）
// =========================================================================
class JourneyStateCache {
  static String originName = '';
  static StationModel? originStation;
  static String destName = '';
  static StationModel? destStation;
  static List<Map<String, dynamic>> routes = [];
  static bool hasSearched = false;
  static int selectedIndex = 0;
  static bool isMy50Active = false;

  static void clear() {
    originName = '';
    originStation = null;
    destName = '';
    destStation = null;
    routes = [];
    hasSearched = false;
    selectedIndex = 0;
    isMy50Active = false;
  }
}

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

class JourneyPlanningScreen extends StatefulWidget {
  const JourneyPlanningScreen({
    super.key,
    this.savedRoute,
    this.apiService,
    this.savedRoutesRepository,
    this.savedPlacesRepository,
    this.authenticate,
    this.selectForDailyCommute = false,
  });

  final SavedRoute? savedRoute;
  final ApiService? apiService;
  final SavedRoutesRepository? savedRoutesRepository;
  final SavedPlacesRepository? savedPlacesRepository;
  final Future<bool> Function(BuildContext)? authenticate;
  final bool selectForDailyCommute;

  @override
  State<JourneyPlanningScreen> createState() => _JourneyPlanningScreenState();
}

class _JourneyPlanningScreenState extends State<JourneyPlanningScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _apiService;
  SavedRoutesRepository? _savedRoutesRepository;
  SavedPlacesRepository? _savedPlacesRepository;

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
  bool _isCompletingNavigation = false;
  bool _isSavingRoute = false;
  bool _isMy50Active = false;

  final Set<String> _savedRouteKeys = {};
  String? _searchError;

  List<Map<String, dynamic>> _recentJourneys = [];
  List<SavedPlace> _savedPlaces = [];
  bool _isLoadingRecent = true;

  final Color _primaryBlue = const Color(0xFF1E50D6);
  final Color _bgLight = const Color(0xFFF4F7FC);
  final Color _textDark = const Color(0xFF1E293B);
  final Color _textGrey = const Color(0xFF64748B);

  Timer? _debounceTimer;
  StreamSubscription<AuthState>? _authSubscription;
  List<Map<String, dynamic>> _livePlaces = [];
  bool _isSearchingPlaces = false;

  Timer? _liveVehiclesTimer;
  List<LiveVehicle> _liveVehicles = [];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _savedRoutesRepository = widget.savedRoutesRepository;
    _savedPlacesRepository = widget.savedPlacesRepository;

    if (_savedRoutesRepository == null && widget.authenticate == null) {
      _savedRoutesRepository = SupabaseSavedRoutesRepository();
    }
    if (_savedPlacesRepository == null && widget.authenticate == null) {
      _savedPlacesRepository = SupabaseSavedPlacesRepository();
    }

    if (widget.authenticate == null) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (!mounted) return;
            if (state.event == AuthChangeEvent.signedIn ||
                state.event == AuthChangeEvent.signedOut) {
              setState(() {
                _savedRouteKeys.clear();
                _recentJourneys = [];
                _savedPlaces = [];
              });
              _loadRecentJourneys();
              _loadSavedRouteKeys();
              _loadSavedPlaces();
            }
          });
    }

    // Only the main Journey tab restores its previous search. A Favourite Route
    // replanning screen must start from its own saved endpoints and identity.
    if (widget.savedRoute == null && !widget.selectForDailyCommute) {
      _originDisplayName = JourneyStateCache.originName;
      _originGtfsStation = JourneyStateCache.originStation;
      _destinationDisplayName = JourneyStateCache.destName;
      _destinationGtfsStation = JourneyStateCache.destStation;
      _realRoutes = JourneyStateCache.routes;
      _hasSearched = JourneyStateCache.hasSearched;
      _selectedRouteIndex = JourneyStateCache.selectedIndex;
      _isMy50Active = JourneyStateCache.isMy50Active;
    }

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _initializeData();
        _loadSavedPlaces();
        _startLiveVehiclesTracking();
      }
    });
  }

  void _updateCache() {
    if (widget.savedRoute != null || widget.selectForDailyCommute) return;
    JourneyStateCache.originName = _originDisplayName;
    JourneyStateCache.originStation = _originGtfsStation;
    JourneyStateCache.destName = _destinationDisplayName;
    JourneyStateCache.destStation = _destinationGtfsStation;
    JourneyStateCache.routes = _realRoutes;
    JourneyStateCache.hasSearched = _hasSearched;
    JourneyStateCache.selectedIndex = _selectedRouteIndex;
    JourneyStateCache.isMy50Active = _isMy50Active;
  }

  void _startLiveVehiclesTracking() {
    _fetchLiveVehicles();
    _liveVehiclesTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchLiveVehicles(),
    );
  }

  Future<void> _fetchLiveVehicles() async {
    try {
      final dynamic api = _apiService;
      final busFeed = await api.getLiveVehicles('bus');
      final feederFeed = await api.getLiveVehicles('mrt_feeder');
      final List<LiveVehicle> vehicles = [];
      if (busFeed is List) vehicles.addAll(busFeed.whereType<LiveVehicle>());
      if (feederFeed is List)
        vehicles.addAll(feederFeed.whereType<LiveVehicle>());
      if (mounted) {
        setState(() {
          _liveVehicles = vehicles;
        });
      }
    } catch (e) {
      debugPrint('Live vehicles fetch error in JourneyPlanning: $e');
    }
  }

  Future<void> _loadSavedPlaces() async {
    final repository = _savedPlacesRepository;
    if (repository == null) return;
    try {
      final places = await repository.load();
      if (mounted) setState(() => _savedPlaces = places);
    } catch (error) {
      debugPrint('Unable to load saved places: $error');
      if (mounted) setState(() => _savedPlaces = []);
    }
  }

  void _selectSavedPlace(
    BuildContext sheetContext,
    SavedPlace place,
    bool isOrigin,
  ) {
    final station = place.resolveStation(_allStations);
    setState(() {
      if (isOrigin) {
        _originDisplayName = station.name;
        _originGtfsStation = station;
      } else {
        _destinationDisplayName = station.name;
        _destinationGtfsStation = station;
      }
      _hasSearched = false;
      _searchError = null;
      _updateCache();
    });
    Navigator.pop(sheetContext);
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
        _updateCache();
        if (_originGtfsStation == null || _destinationGtfsStation == null) {
          setState(
            () => _searchError =
                'A saved station is no longer available. Please select your locations again.',
          );
        } else {
          await _handleSearch(preferredRoute: saved);
        }
      }
    }
  }

  Future<void> _loadSavedRouteKeys() async {
    final repository = _savedRoutesRepository;
    if (repository == null) return;
    final userId = widget.savedRoutesRepository == null
        ? Supabase.instance.client.auth.currentUser?.id
        : null;
    if (widget.savedRoutesRepository == null && userId == null) {
      if (mounted) setState(_savedRouteKeys.clear);
      return;
    }
    try {
      final routes = await repository.load();
      if (!mounted) return;
      if (widget.savedRoutesRepository == null &&
          Supabase.instance.client.auth.currentUser?.id != userId)
        return;
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
    _liveVehiclesTimer?.cancel();
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
        final dynamic response = await PersonalAssistanceFunctions().invoke(
          'journey-history',
          'list',
          payload: {'limit': 3},
        );

        if (mounted &&
            Supabase.instance.client.auth.currentUser?.id == user.id) {
          List<Map<String, dynamic>> parsedList = [];
          if (response is List) {
            parsedList = response
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          } else if (response is Map) {
            final data = response['data'] ?? response['result'] ?? response;
            if (data is List) {
              parsedList = data
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            } else if (data is Map) {
              parsedList = [Map<String, dynamic>.from(data)];
            }
          }
          setState(() {
            _recentJourneys = parsedList;
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
      _updateCache();
    });
  }

  void _resetSearch() {
    JourneyStateCache.clear();
    setState(() {
      _originDisplayName = '';
      _originGtfsStation = null;
      _destinationDisplayName = '';
      _destinationGtfsStation = null;
      _realRoutes = [];
      _hasSearched = false;
      _searchError = null;
      _isMy50Active = false;
    });
  }

  void _toggleMy50(bool value) {
    setState(() {
      _isMy50Active = value;
      _updateCache();
      for (var route in _realRoutes) {
        route['fare'] = _calculateRealisticFare(route);
      }
    });
  }

  String _calculateRealisticFare(Map<String, dynamic> route) {
    if (_isMy50Active) return 'RM 0.00';

    final legs = route['legs'] as List? ?? [];
    double totalFare = 0.0;

    for (var leg in legs) {
      if (leg is! Map) continue;
      final mode = (leg['mode'] ?? '').toString();
      final name = (leg['name'] ?? '').toString().toUpperCase().trim();
      final durMins =
          int.tryParse(
            leg['duration'].toString().replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          15;

      if (mode == 'Walk' || mode == 'Wait') {
        continue;
      } else if (name.startsWith('T') || name.contains('FEEDER')) {
        totalFare += 1.00;
      } else if (mode == 'Bus') {
        if (durMins <= 15) {
          totalFare += 1.00;
        } else if (durMins <= 30) {
          totalFare += 1.90;
        } else if (durMins <= 50) {
          totalFare += 2.50;
        } else {
          totalFare += 3.00;
        }
      } else if (mode == 'Rail') {
        double railFare = 1.20 + (durMins * 0.08);
        totalFare += railFare.clamp(1.20, 6.40);
      }
    }

    if (totalFare == 0.0) totalFare = 1.00;
    return 'RM ${totalFare.toStringAsFixed(2)}';
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    var p = 0.017453292519943295;
    var a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a.clamp(0.0, 1.0)));
  }

  StationModel _findNearestGtfsStation(
    double lat,
    double lon,
    String placeName,
  ) {
    String cleanSearchName = placeName
        .toUpperCase()
        .replaceAll(RegExp(r'\([^)]+\)'), '')
        .trim();
    List<String> combinedIds = [];
    Set<String> combinedLines = {};
    String determinedCategory = 'Mixed';

    if (lat == 0 && lon == 0) {
      String normSearch = cleanSearchName.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      for (var station in _allStations) {
        String normStation = station.name
            .replaceAll(RegExp(r'\s*\([^)]+\)'), '')
            .replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (normStation == normSearch && station.lat != 0 && station.lon != 0) {
          lat = station.lat;
          lon = station.lon;
          break;
        }
      }
      if (lat == 0 && lon == 0 && normSearch.length >= 4) {
        for (var station in _allStations) {
          String normStation = station.name
              .replaceAll(RegExp(r'\s*\([^)]+\)'), '')
              .replaceAll(RegExp(r'[^A-Z0-9]'), '');
          if ((normStation.contains(normSearch) ||
                  normSearch.contains(normStation)) &&
              station.lat != 0 &&
              station.lon != 0) {
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
          double distance = _calculateDistance(
            lat,
            lon,
            station.lat,
            station.lon,
          );
          if (distance < minDistance) {
            minDistance = distance;
            absoluteNearest = station;
          }

          bool isExactMatch =
              cleanSearchName.isNotEmpty &&
              station.name.toUpperCase() == cleanSearchName;
          bool isSafeSubstring =
              cleanSearchName.length >= 4 &&
              station.name.toUpperCase().contains(cleanSearchName);

          if (distance <= 0.4 || isExactMatch || isSafeSubstring) {
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
      if (absoluteNearest != null && minDistance < 0.1)
        determinedCategory = absoluteNearest.category;
      if (placeName == 'Selected on Map' && absoluteNearest != null)
        placeName = absoluteNearest.name;
    } else {
      String normSearch = cleanSearchName.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      for (var station in _allStations) {
        String stationBaseName = station.name
            .replaceAll(RegExp(r'\s*\([^)]+\)'), '')
            .trim();
        String normStation = stationBaseName.replaceAll(
          RegExp(r'[^A-Z0-9]'),
          '',
        );
        bool isExact = normStation == normSearch;
        bool isSub1 =
            normSearch.length >= 4 && normStation.contains(normSearch);
        bool isSub2 =
            normStation.length >= 4 && normStation.contains(normStation);
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

  bool _matchesSavedRoute(Map<String, dynamic> route, SavedRoute savedRoute) =>
      savedRoute.matchesJourney(route);

  Future<void> _handleSearch({SavedRoute? preferredRoute}) async {
    if (_isLoading || _isSavingRoute || _isStartingNavigation) return;
    if (_originGtfsStation != null && _destinationGtfsStation != null) {
      final bool isSameStation =
          _originDisplayName.trim().toUpperCase() ==
              _destinationDisplayName.trim().toUpperCase() ||
          (_originGtfsStation!.name.trim().toUpperCase() ==
                  _destinationGtfsStation!.name.trim().toUpperCase() &&
              (_originGtfsStation!.lat - _destinationGtfsStation!.lat).abs() <
                  0.0001 &&
              (_originGtfsStation!.lon - _destinationGtfsStation!.lon).abs() <
                  0.0001);

      if (isSameStation) {
        setState(() {
          _searchError = 'Choose different origin and destination stations.';
          _hasSearched = false;
        });
        return;
      }

      StationModel searchOrigin = _originGtfsStation!;
      StationModel searchDest = _destinationGtfsStation!;
      int walkStartMins = 0;
      int walkEndMins = 0;

      if (searchOrigin.ids.isEmpty && _allStations.isNotEmpty) {
        final validOrigins = _allStations
            .where((s) => s.ids.isNotEmpty)
            .toList();
        if (validOrigins.isNotEmpty) {
          searchOrigin = validOrigins.reduce(
            (a, b) =>
                _calculateDistance(
                      searchOrigin.lat,
                      searchOrigin.lon,
                      a.lat,
                      a.lon,
                    ) <
                    _calculateDistance(
                      searchOrigin.lat,
                      searchOrigin.lon,
                      b.lat,
                      b.lon,
                    )
                ? a
                : b,
          );
          walkStartMins =
              (_calculateDistance(
                        _originGtfsStation!.lat,
                        _originGtfsStation!.lon,
                        searchOrigin.lat,
                        searchOrigin.lon,
                      ) /
                      4.0 *
                      60)
                  .round();
        }
      }

      if (searchDest.ids.isEmpty && _allStations.isNotEmpty) {
        final validDests = _allStations.where((s) => s.ids.isNotEmpty).toList();
        if (validDests.isNotEmpty) {
          searchDest = validDests.reduce(
            (a, b) =>
                _calculateDistance(
                      searchDest.lat,
                      searchDest.lon,
                      a.lat,
                      a.lon,
                    ) <
                    _calculateDistance(
                      searchDest.lat,
                      searchDest.lon,
                      b.lat,
                      b.lon,
                    )
                ? a
                : b,
          );
          walkEndMins =
              (_calculateDistance(
                        _destinationGtfsStation!.lat,
                        _destinationGtfsStation!.lon,
                        searchDest.lat,
                        searchDest.lon,
                      ) /
                      4.0 *
                      60)
                  .round();
        }
      }

      setState(() {
        _isLoading = true;
        _hasSearched = true;
        _searchError = null;
        _realRoutes = [];
      });

      try {
        final results = await _apiService.findRoutes(searchOrigin, searchDest);
        if (!mounted) return;
        // Preserve the planner's normal ranked top four for ordinary searches.
        // The complete result list is retained only so Favourite Plan Again can
        // locate a stable service sequence outside that display window.
        final normallyRankedResults = results.take(4).toList();

        for (var route in results) {
          int transitDur =
              int.tryParse(route['duration'].toString().split(' ')[0]) ?? 0;
          int waitMins = route['wait'] as int? ?? 0;
          int totalWalk = walkStartMins + walkEndMins;

          int totalDur = transitDur + totalWalk + waitMins;
          route['duration'] = '$totalDur min';

          try {
            String dep =
                route['scheduledDepart']?.toString() ??
                DateFormat('HH:mm').format(DateTime.now());
            final parts = dep.split(':');
            final dt = DateTime(
              2000,
              1,
              1,
              int.parse(parts[0]),
              int.parse(parts[1]),
            ).subtract(Duration(minutes: walkStartMins + waitMins));
            route['scheduledDepart'] = DateFormat('HH:mm').format(dt);
          } catch (_) {}

          List<dynamic> legs = List.from(route['legs'] ?? []);
          if (walkStartMins > 0) {
            legs.insert(0, {
              'mode': 'Walk',
              'name': 'Walk',
              'duration': '$walkStartMins min',
              'icon': Icons.directions_walk,
              'color': Colors.grey,
              'desc':
                  'Walk from ${_originGtfsStation!.name} to ${searchOrigin.name}',
              'from': {
                'lat': _originGtfsStation!.lat,
                'lon': _originGtfsStation!.lon,
              },
              'to': {'lat': searchOrigin.lat, 'lon': searchOrigin.lon},
            });
          }
          if (legs.length > (walkStartMins > 0 ? 1 : 0)) {
            final firstRide = legs[walkStartMins > 0 ? 1 : 0];
            firstRide['desc'] = '${firstRide['desc']} (Wait: $waitMins min)';
          }
          if (walkEndMins > 0) {
            legs.add({
              'mode': 'Walk',
              'name': 'Walk',
              'duration': '$walkEndMins min',
              'icon': Icons.directions_walk,
              'color': Colors.grey,
              'desc':
                  'Walk from ${searchDest.name} to ${_destinationGtfsStation!.name}',
              'from': {'lat': searchDest.lat, 'lon': searchDest.lon},
              'to': {
                'lat': _destinationGtfsStation!.lat,
                'lon': _destinationGtfsStation!.lon,
              },
            });
          }
          route['legs'] = legs;

          route['fare'] = _calculateRealisticFare(route);
        }

        results.sort((a, b) {
          int da = int.parse(a['duration'].toString().split(' ')[0]);
          int db = int.parse(b['duration'].toString().split(' ')[0]);
          return da.compareTo(db);
        });
        normallyRankedResults.sort((a, b) {
          final first = int.parse(a['duration'].toString().split(' ')[0]);
          final second = int.parse(b['duration'].toString().split(' ')[0]);
          return first.compareTo(second);
        });

        final allResultsPreferredIndex = preferredRoute == null
            ? -1
            : results.indexWhere(
                (route) => _matchesSavedRoute(route, preferredRoute),
              );
        final visibleResults = normallyRankedResults;
        if (allResultsPreferredIndex >= 0 &&
            preferredRoute != null &&
            !visibleResults.any(
              (route) => _matchesSavedRoute(route, preferredRoute),
            )) {
          if (visibleResults.length == 4) visibleResults.removeLast();
          visibleResults.add(results[allResultsPreferredIndex]);
        }
        final preferredIndex = preferredRoute == null
            ? -1
            : visibleResults.indexWhere(
                (route) => _matchesSavedRoute(route, preferredRoute),
              );

        setState(() {
          _realRoutes = visibleResults;
          _selectedRouteIndex = preferredIndex < 0 ? 0 : preferredIndex;
          if (visibleResults.isEmpty)
            _searchError =
                'No routes found. Try another origin or destination.';
          _updateCache();
        });

        if (preferredRoute != null &&
            allResultsPreferredIndex < 0 &&
            results.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your saved route is unavailable. Showing other routes for these locations.',
              ),
            ),
          );
        }
      } catch (_) {
        if (mounted)
          setState(
            () => _searchError = 'Unable to find routes. Please try again.',
          );
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
        signature: SavedRoute.stableSignatureFromJourney(route),
        lineName: (route['name'] ?? _getLineDetails(route)['name']).toString(),
        serviceSequence: SavedRoute.servicesFromJourney(route),
        transportModes: SavedRoute.transportModesFromJourney(route),
      );

  Future<void> _saveRoute(Map<String, dynamic> route) async {
    if (_isSavingRoute) return;
    if (_originGtfsStation == null || _destinationGtfsStation == null) return;
    final defaultName = '$_originDisplayName → $_destinationDisplayName';
    final draft = _routeToSave(route, defaultName);

    if (!await (widget.authenticate ?? requireSignIn)(context) || !mounted)
      return;

    final name = await showRouteNameDialog(
      context,
      initialName: defaultName.length > 80
          ? defaultName.substring(0, 80)
          : defaultName,
    );

    if (name == null || !mounted) return;
    setState(() => _isSavingRoute = true);

    try {
      final repository = _savedRoutesRepository ??=
          SupabaseSavedRoutesRepository();
      await repository.save(
        SavedRoute(
          name: name,
          origin: draft.origin,
          destination: draft.destination,
          signature: draft.signature,
          lineName: draft.lineName,
          serviceSequence: draft.serviceSequence,
          transportModes: draft.transportModes,
        ),
      );
      if (!mounted) return;
      setState(() => _savedRouteKeys.add(draft.routeKey));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route saved. Find it in Profile > Favourite Routes.'),
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save route. Please try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _isSavingRoute = false);
    }
  }

  Future<void> _removeSavedRoute(Map<String, dynamic> route) async {
    if (_isSavingRoute) return;
    if (_originGtfsStation == null || _destinationGtfsStation == null) return;
    final draft = _routeToSave(route, '');
    setState(() => _isSavingRoute = true);
    try {
      final repository = _savedRoutesRepository ??=
          SupabaseSavedRoutesRepository();
      final routes = await repository.load();
      final saved = routes
          .where(
            (candidate) =>
                candidate.routeKey == draft.routeKey && candidate.id != null,
          )
          .firstOrNull;
      if (saved == null) {
        if (mounted) setState(() => _savedRouteKeys.remove(draft.routeKey));
        return;
      }
      await repository.delete(saved.id!);
      if (!mounted) return;
      setState(() => _savedRouteKeys.remove(draft.routeKey));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route removed from Favourite Routes.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to remove route. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingRoute = false);
    }
  }

  void _onSearchQueryChanged(String query) {
    final q = query.trim().toUpperCase();
    setState(() {
      _filteredStations = _allStations.where((s) {
        if (s.name.toUpperCase().contains(q)) return true;
        if (q == 'KJL' || q == 'KJ')
          return s.lines.any((l) => l.toUpperCase().contains('KELANA JAYA')) ||
              s.ids.any((id) => id.contains('_KJ'));
        if (q == 'LRT') return s.category == 'Rail';
        if (q == 'MRT')
          return s.category == 'Rail' || s.category == 'MRT Feeder';
        return s.lines.any((l) => l.toUpperCase().contains(q));
      }).toList();
    });

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      if (query.trim().isEmpty) return;
      setState(() => _isSearchingPlaces = true);
      try {
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=$query, Malaysia&format=json&limit=5',
        );
        final response = await http.get(
          url,
          headers: {'User-Agent': 'NextRoute_Project'},
        );
        if (response.statusCode == 200) {
          final List data = json.decode(response.body);
          if (mounted) {
            setState(() {
              _livePlaces = data
                  .map(
                    (e) => {
                      'name': e['name'] ?? 'Unknown Place',
                      'desc': e['display_name'] ?? '',
                      'lat': double.tryParse(e['lat'].toString()) ?? 0.0,
                      'lon': double.tryParse(e['lon'].toString()) ?? 0.0,
                    },
                  )
                  .toList();
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
      MaterialPageRoute(
        builder: (context) => MapPickerMockScreen(
          allStations: _allStations,
          apiService: _apiService,
        ),
      ),
    );

    if (result != null) {
      final StationModel selectedStation = (result['station'] is StationModel)
          ? (result['station'] as StationModel)
          : _findNearestGtfsStation(
              result['lat'],
              result['lon'],
              result['name'],
            );

      setState(() {
        if (isOrigin) {
          _originDisplayName = selectedStation.name;
          _originGtfsStation = selectedStation;
        } else {
          _destinationDisplayName = selectedStation.name;
          _destinationGtfsStation = selectedStation;
        }
        _hasSearched = false;
        _searchError = null;
        _updateCache();
      });
    }
  }

  Future<void> _showLocationSearch(bool isOrigin) async {
    if (_isLoading || _isSavingRoute || _isStartingNavigation) return;
    await _loadSavedPlaces();
    if (!mounted) return;
    setState(() {
      _filteredStations = List.from(_allStations);
      _livePlaces = [];
    });

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
              heightFactor: 0.9,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      isOrigin ? 'Start from' : 'Where to?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_savedPlaces.isNotEmpty) ...[
                      Text(
                        'SAVED PLACES',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _textGrey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _savedPlaces
                            .map(
                              (place) => ActionChip(
                                avatar: Icon(
                                  switch (place.type) {
                                    SavedPlaceType.home => Icons.home_outlined,
                                    SavedPlaceType.university =>
                                      Icons.school_outlined,
                                    SavedPlaceType.work => Icons.work_outline,
                                  },
                                  size: 17,
                                  color: _primaryBlue,
                                ),
                                label: Text(place.type.label),
                                onPressed: () =>
                                    _selectSavedPlace(context, place, isOrigin),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search map, places, or stations...',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        suffixIcon: _isSearchingPlaces
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        _onSearchQueryChanged(value);
                        Future.delayed(const Duration(milliseconds: 900), () {
                          if (mounted) setModalState(() {});
                        });
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: _primaryBlue.withValues(
                                alpha: 0.1,
                              ),
                              child: Icon(
                                Icons.map_rounded,
                                color: _primaryBlue,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'Choose on map',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _primaryBlue,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: Colors.grey[300],
                            ),
                            onTap: () => _openMapPicker(isOrigin),
                          ),
                          const Divider(height: 32),

                          if (_livePlaces.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'PLACES FROM MAP',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _textGrey,
                                ),
                              ),
                            ),
                            ..._livePlaces.map(
                              (place) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.orange[50],
                                  child: const Icon(
                                    Icons.place,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  place['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  place['desc'],
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  final nearestStation =
                                      _findNearestGtfsStation(
                                        place['lat'],
                                        place['lon'],
                                        place['name'],
                                      );
                                  setState(() {
                                    if (isOrigin) {
                                      _originDisplayName = place['name'];
                                      _originGtfsStation = nearestStation;
                                    } else {
                                      _destinationDisplayName = place['name'];
                                      _destinationGtfsStation = nearestStation;
                                    }
                                    _hasSearched = false;
                                    _searchError = null;
                                    _updateCache();
                                  });
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                            const Divider(height: 32),
                          ],
                          if (_filteredStations.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'STATIONS & BUS STOPS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _textGrey,
                                ),
                              ),
                            ),
                            ..._filteredStations.map((station) {
                              final isRail = station.category == 'Rail';
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: isRail
                                      ? Colors.blue[50]
                                      : Colors.red[50],
                                  child: Icon(
                                    isRail ? Icons.train : Icons.directions_bus,
                                    color: isRail ? Colors.blue : Colors.red,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  station.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  station.lines.join(' • '),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () {
                                  final finalStation = _findNearestGtfsStation(
                                    station.lat,
                                    station.lon,
                                    station.name,
                                  );
                                  setState(() {
                                    if (isOrigin) {
                                      _originDisplayName = station.name;
                                      _originGtfsStation = finalStation;
                                    } else {
                                      _destinationDisplayName = station.name;
                                      _destinationGtfsStation = finalStation;
                                    }
                                    _hasSearched = false;
                                    _searchError = null;
                                    _updateCache();
                                  });
                                  Navigator.pop(context);
                                },
                              );
                            }),
                          ],
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

  Future<void> _startNavigation(
    Map<String, dynamic> route,
    int totalMins,
    String departTime,
    String arriveTime,
  ) async {
    setState(() => _isStartingNavigation = true);
    try {
      double farePrice =
          double.tryParse(
            route['fare'].toString().replaceAll('RM ', '').trim(),
          ) ??
          0.0;
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
      if (mounted) {
        setState(() => _isStartingNavigation = false);
        final activeBusRoutes = module5BusRoutesFromJourneySteps(dbSafeSteps);
        // Module 5 tracking is local and cannot interrupt Journey navigation.
        unawaited(
          Module5UserRouteContext.shared.startJourney(
            busRoutes: activeBusRoutes,
            origin: _originDisplayName,
            destination: _destinationDisplayName,
            expiresAt: DateTime.now().add(Duration(minutes: totalMins + 60)),
          ),
        );
        _showLiveNavigationModal(
          route,
          totalMins,
          departTime,
          arriveTime,
          signedIn,
          farePrice,
          dbSafeSteps,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStartingNavigation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _completeNavigation({
    required BuildContext modalContext,
    required Map<String, dynamic> route,
    required bool signedIn,
    required double fare,
    required int totalMins,
    required String departTime,
    required String arriveTime,
    required List<Map<String, dynamic>> transitSteps,
  }) async {
    if (_isCompletingNavigation) return;
    _isCompletingNavigation = true;
    try {
      if (signedIn) {
        await _apiService.saveNavigationHistory(
          origin: _originDisplayName,
          destination: _destinationDisplayName,
          fare: fare,
          durationMinutes: totalMins,
          departureTime: departTime,
          estimatedArrivalTime: arriveTime,
          transitSteps: transitSteps,
          originStation: _originGtfsStation,
          destinationStation: _destinationGtfsStation,
          routeSignature: (route['sig'] ?? '').toString(),
          lineName: (route['name'] ?? _getLineDetails(route)['name'])
              .toString(),
        );
        await _loadRecentJourneys();
      }
      // This only clears Module 5's device-local tracking state.
      unawaited(Module5UserRouteContext.shared.endJourney());
      if (!mounted || !modalContext.mounted) return;
      Navigator.pop(modalContext);
      _resetSearch();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            signedIn
                ? 'Journey completed and added to Travel History.'
                : 'Journey completed. Sign in to save your travel history.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isCompletingNavigation = false;
    }
  }

  bool _isVehicleOnRoute(
    LiveVehicle vehicle,
    Map<String, dynamic>? activeRoute,
  ) {
    if (activeRoute == null) return true;
    final String vRouteId = vehicle.routeId.toUpperCase().trim();
    if (vRouteId.isEmpty) return false;

    final legs = activeRoute['legs'] as List? ?? [];
    for (var leg in legs) {
      if (leg is Map) {
        final legName = (leg['name'] ?? '').toString().toUpperCase();
        if (legName == vRouteId ||
            legName.contains(vRouteId) ||
            vRouteId.contains(legName)) {
          return true;
        }
      }
    }

    final mainName = (activeRoute['name'] ?? '').toString().toUpperCase();
    final sig = (activeRoute['sig'] ?? '').toString().toUpperCase();
    if (mainName.contains(vRouteId) || sig.contains(vRouteId)) return true;

    return false;
  }

  void _showLiveNavigationModal(
    Map<String, dynamic> route,
    int totalMins,
    String departTime,
    String arriveTime,
    bool signedIn,
    double fare,
    List<Map<String, dynamic>> transitSteps,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.95,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(
                  top: 24,
                  left: 20,
                  right: 20,
                  bottom: 20,
                ),
                decoration: BoxDecoration(
                  color: _primaryBlue,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.navigation,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'LIVE NAVIGATION',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View journey alerts',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const AnalyticsCentreScreen(
                                    showBackButton: true,
                                  ),
                                ),
                              ),
                              icon: const Icon(
                                Icons.notifications_active_outlined,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              arriveTime,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Heading to $_destinationDisplayName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$totalMins mins remaining',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[50],
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => _completeNavigation(
                      modalContext: context,
                      route: route,
                      signedIn: signedIn,
                      fare: fare,
                      totalMins: totalMins,
                      departTime: departTime,
                      arriveTime: arriveTime,
                      transitSteps: transitSteps,
                    ),
                    child: const Text(
                      'End Journey',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLiveMapCard({Map<String, dynamic>? route}) {
    double lat = _originGtfsStation?.lat ?? 3.1341;
    double lon = _originGtfsStation?.lon ?? 101.6861;
    final activeRoute =
        route ??
        (_realRoutes.isNotEmpty ? _realRoutes[_selectedRouteIndex] : null);
    final List<LiveVehicle> liveOnRoute = _liveVehicles
        .where((v) => _isVehicleOnRoute(v, activeRoute))
        .toList();

    return GestureDetector(
      onTap: () {
        if (_originGtfsStation != null && _destinationGtfsStation != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RouteMapViewerScreen(
                origin: _originGtfsStation!,
                destination: _destinationGtfsStation!,
                route: activeRoute,
                allStations: _allStations,
                apiService: _apiService,
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
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
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.nextroute.app',
                    ),
                    EstimatedLrtLayer(route: activeRoute),
                    MarkerLayer(
                      markers: [
                        ...liveOnRoute.map(
                          (vehicle) => Marker(
                            point: LatLng(vehicle.lat, vehicle.lon),
                            width: 50,
                            height: 50,
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE11D48),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    vehicle.routeId,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Transform.rotate(
                                  angle: vehicle.bearing * (pi / 180),
                                  child: const Icon(
                                    Icons.navigation,
                                    color: Color(0xFFE11D48),
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Marker(
                          point: LatLng(lat, lon),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 80,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.zoom_out_map,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Live Boarding Location',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _originDisplayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        liveOnRoute.isNotEmpty
                            ? '${liveOnRoute.length} LIVE'
                            : 'NO LIVE BUS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
          walkMins +=
              int.tryParse(
                leg['duration'].toString().replaceAll(RegExp(r'[^0-9]'), ''),
              ) ??
              0;
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
    Color color = (mainLeg['color'] is Color)
        ? mainLeg['color'] as Color
        : _primaryBlue;

    if (name.contains('KELANA JAYA')) {
      code = 'KJ';
      color = const Color(0xFFE11D48);
    } else if (name.contains('KAJANG')) {
      code = 'KG';
      color = const Color(0xFF15803D);
    } else if (name.contains('PUTRAJAYA')) {
      code = 'PY';
      color = const Color(0xFF059669);
    } else if (name.contains('AMPANG')) {
      code = 'AG';
      color = const Color(0xFFF97316);
    } else if (name.contains('SRI PETALING')) {
      code = 'SP';
      color = const Color(0xFF7F1D1D);
    } else if (name.contains('MONORAIL')) {
      code = 'MR';
      color = const Color(0xFF84CC16);
    } else if (name.contains('BRT')) {
      code = 'B1';
      color = const Color(0xFF14532D);
    }

    return {'code': code, 'color': color, 'name': mainLeg['name'] ?? name};
  }

  String _formatTime(String? time24) {
    if (time24 == null || !time24.contains(':')) return '8:00 AM';
    try {
      final parts = time24.split(':');
      final now = DateTime.now();
      final dt = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
      return DateFormat('h:mm a').format(dt);
    } catch (e) {
      return time24;
    }
  }

  String _calculateArrival(String? time24, int durationMins) {
    if (time24 == null || !time24.contains(':')) return '8:30 AM';
    try {
      final parts = time24.split(':');
      final now = DateTime.now();
      final dt = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      ).add(Duration(minutes: durationMins));
      return DateFormat('h:mm a').format(dt);
    } catch (e) {
      return time24;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.savedRoute != null && !widget.selectForDailyCommute) {
      return _buildSavedRouteView();
    }
    return Scaffold(
      backgroundColor: _bgLight,
      appBar: widget.selectForDailyCommute
          ? AppBar(title: const Text('Choose commute route'))
          : widget.savedRoute == null
          ? null
          : AppBar(title: const Text('Current route status')),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Stack(
          children: [
            Container(height: 280, color: _primaryBlue),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ROUTE OPTIMIZATION',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Journey Planning',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                        child: Text(
                          _searchError!,
                          style: const TextStyle(color: Color(0xFF7C2D12)),
                        ),
                      ),

                    const SizedBox(height: 32),

                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (!_hasSearched)
                      _buildRecentJourneys()
                    else if (_realRoutes.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.directions_transit_outlined,
                                size: 64,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No transit routes found.',
                                style: TextStyle(
                                  color: _textGrey,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedRouteView() {
    final savedRoute = widget.savedRoute!;
    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(title: Text(savedRoute.name)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _handleSearch(preferredRoute: savedRoute),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('refresh-saved-route'),
                  onPressed:
                      _isLoading ||
                          _isSavingRoute ||
                          _isStartingNavigation ||
                          _originGtfsStation == null ||
                          _destinationGtfsStation == null
                      ? null
                      : () => _handleSearch(preferredRoute: savedRoute),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh live status'),
                ),
              ),
              if (_searchError != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _searchError!,
                    style: const TextStyle(color: Color(0xFF7C2D12)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_realRoutes.isNotEmpty)
                _buildJourneySummaryCard()
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(
                      'No transit routes found.',
                      style: TextStyle(
                        color: _textGrey,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ROAD SEARCH',
            style: TextStyle(
              color: _textGrey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),

          Stack(
            alignment: Alignment.center,
            children: [
              Column(
                children: [
                  _buildSearchField(
                    label: 'ORIGIN',
                    value: _originDisplayName.isEmpty
                        ? 'Origin Location'
                        : _originDisplayName,
                    isHint: _originDisplayName.isEmpty,
                    dotColor: _primaryBlue,
                    onTap: () => _showLocationSearch(true),
                  ),
                  const SizedBox(height: 12),
                  _buildSearchField(
                    label: 'DESTINATION',
                    value: _destinationDisplayName.isEmpty
                        ? 'Destination Location'
                        : _destinationDisplayName,
                    isHint: _destinationDisplayName.isEmpty,
                    dotColor: const Color(0xFFEF4444),
                    onTap: () => _showLocationSearch(false),
                  ),
                ],
              ),
              Positioned(
                child: GestureDetector(
                  onTap: _isLoading || _isSavingRoute || _isStartingNavigation
                      ? null
                      : _swapLocations,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(Icons.swap_vert, color: _textGrey, size: 20),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _isMy50Active
                  ? _primaryBlue.withValues(alpha: 0.1)
                  : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isMy50Active
                    ? _primaryBlue.withValues(alpha: 0.3)
                    : Colors.grey[200]!,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.credit_card,
                  size: 20,
                  color: _isMy50Active ? _primaryBlue : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My50 Unlimited Pass',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _isMy50Active ? _primaryBlue : _textDark,
                        ),
                      ),
                      Text(
                        'Zero fare for Rapid KL rides',
                        style: TextStyle(fontSize: 10, color: _textGrey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isMy50Active,
                  activeTrackColor: _primaryBlue,
                  activeThumbColor: Colors.white,
                  onChanged: _toggleMy50,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textGrey,
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text(
                    'Reset',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed:
                      _isLoading || _isSavingRoute || _isStartingNavigation
                      ? null
                      : _resetSearch,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  icon: Icon(
                    widget.savedRoute == null ? Icons.search : Icons.refresh,
                    size: 18,
                  ),
                  label: Text(
                    widget.savedRoute == null
                        ? 'Find Routes'
                        : 'Refresh live status',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed:
                      !_isLoading &&
                          !_isSavingRoute &&
                          !_isStartingNavigation &&
                          _originGtfsStation != null &&
                          _destinationGtfsStation != null
                      ? () => _handleSearch(preferredRoute: widget.savedRoute)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField({
    required String label,
    required String value,
    required bool isHint,
    required Color dotColor,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _textGrey,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      color: isHint ? Colors.grey[400] : _textDark,
                      fontWeight: isHint ? FontWeight.normal : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: _textGrey, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentJourneys() {
    if (_isLoadingRecent) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
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
            Text(
              'RECENT JOURNEYS',
              style: TextStyle(
                color: _textGrey,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            TextButton(
              onPressed: () async {
                final user = Supabase.instance.client.auth.currentUser;
                if (user != null) {
                  setState(() => _isLoadingRecent = true);
                  try {
                    await PersonalAssistanceFunctions().invoke(
                      'journey-history',
                      'clear',
                    );
                  } catch (_) {
                    await Supabase.instance.client
                        .from('navigation_history')
                        .delete()
                        .eq('user_id', user.id);
                  }
                  await _loadRecentJourneys();
                }
              },
              child: Text(
                'Clear all',
                style: TextStyle(
                  color: _primaryBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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

          if (journey['transit_steps'] != null) {
            try {
              List steps = [];
              if (journey['transit_steps'] is List) {
                steps = journey['transit_steps'] as List;
              } else if (journey['transit_steps'] is Map) {
                final stepMap = journey['transit_steps'] as Map;
                if (stepMap.containsKey('data') && stepMap['data'] is List) {
                  steps = stepMap['data'] as List;
                } else {
                  steps = [stepMap];
                }
              } else if (journey['transit_steps'] is String) {
                final decoded = json.decode(
                  journey['transit_steps'].toString(),
                );
                if (decoded is List) steps = decoded;
              }

              if (steps.isNotEmpty) {
                Map<String, dynamic> mainStep = {};
                for (var s in steps) {
                  if (s is Map && s['mode'] == 'Rail') {
                    mainStep = Map<String, dynamic>.from(s);
                    break;
                  }
                }
                if (mainStep.isEmpty && steps.first is Map)
                  mainStep = Map<String, dynamic>.from(steps.first as Map);

                lineName = (mainStep['name'] ?? 'Transit').toString();
                String upperName = lineName.toUpperCase();

                if (upperName.contains('KELANA JAYA')) {
                  lineCode = 'KJ';
                  lineColor = const Color(0xFFE11D48);
                } else if (upperName.contains('KAJANG')) {
                  lineCode = 'KG';
                  lineColor = const Color(0xFF15803D);
                } else if (upperName.contains('PUTRAJAYA')) {
                  lineCode = 'PY';
                  lineColor = const Color(0xFF059669);
                } else if (upperName.contains('AMPANG')) {
                  lineCode = 'AG';
                  lineColor = const Color(0xFFF97316);
                } else if (upperName.contains('MONORAIL')) {
                  lineCode = 'MR';
                  lineColor = const Color(0xFF84CC16);
                }
              }
            } catch (e) {
              debugPrint('Error parsing transit_steps: $e');
            }
          }

          return GestureDetector(
            onTap: () {
              final matchedOrigin = _findNearestGtfsStation(0, 0, origin);
              final matchedDest = _findNearestGtfsStation(0, 0, dest);
              setState(() {
                _originDisplayName = origin;
                _destinationDisplayName = dest;
                _originGtfsStation = matchedOrigin;
                _destinationGtfsStation = matchedDest;
                _updateCache();
              });
              _handleSearch();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: lineColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      lineCode,
                      style: TextStyle(
                        color: lineColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                origin,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _textDark,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 12,
                                color: Colors.grey,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                dest,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _textDark,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$lineName • RM ${fare.toStringAsFixed(2)} • $duration min',
                          style: TextStyle(color: _textGrey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[300]),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRouteComparisonList() {
    if (_realRoutes.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROUTE COMPARISON',
          style: TextStyle(
            color: _textGrey,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(_realRoutes.length, (index) {
          final route = _realRoutes[index];
          final isSelected = _selectedRouteIndex == index;
          final isSaved = _savedRouteKeys.contains(
            _routeToSave(route, '').routeKey,
          );
          final lineDetails = _getLineDetails(route);
          final walkMins = _calculateWalkMins(route);
          final String durationStr = route['duration'] ?? '20 min';
          final String fareStr = route['fare'] ?? 'RM 2.00';

          String tagText = '';
          Color tagColor = Colors.grey;
          IconData tagIcon = Icons.star;
          if (index == 0) {
            tagText = 'Fastest';
            tagColor = Colors.orange;
            tagIcon = Icons.bolt;
          } else if (route['badge'] == 'Direct') {
            tagText = 'Direct';
            tagColor = Colors.green;
            tagIcon = Icons.check_circle;
          } else if (index == 1) {
            tagText = 'Scenic';
            tagColor = Colors.blue;
            tagIcon = Icons.landscape;
          } else {
            tagText = 'Budget';
            tagColor = Colors.purple;
            tagIcon = Icons.savings;
          }

          return GestureDetector(
            onTap: () => setState(() {
              _selectedRouteIndex = index;
              _updateCache();
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? _primaryBlue : Colors.grey[200]!,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: _primaryBlue.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Column(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: lineDetails['color'],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          lineDetails['code'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(tagIcon, size: 10, color: tagColor),
                          const SizedBox(width: 2),
                          Text(
                            tagText,
                            style: TextStyle(
                              color: _textGrey,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route['badge'] == 'Direct'
                              ? lineDetails['name']
                              : (route['name'] ?? ''),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _buildRouteMetric(Icons.schedule, durationStr),
                            _buildRouteMetric(Icons.payments_outlined, fareStr),
                            _buildRouteMetric(
                              Icons.directions_walk,
                              '$walkMins min walk',
                            ),
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
                          child: Icon(
                            Icons.favorite,
                            color: Color(0xFFE11D48),
                            size: 23,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? _primaryBlue : Colors.white,
                          border: Border.all(
                            color: isSelected
                                ? _primaryBlue
                                : Colors.grey[300]!,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 16,
                              )
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildJourneySummaryCard() {
    if (_realRoutes.isEmpty) return const SizedBox();

    final route = _realRoutes[_selectedRouteIndex];
    final isSaved = _savedRouteKeys.contains(_routeToSave(route, '').routeKey);
    final lineDetails = _getLineDetails(route);

    int totalMins =
        int.tryParse(route['duration'].toString().split(' ')[0]) ?? 20;
    int walkMins = _calculateWalkMins(route);

    final String departStr = _formatTime(
      route['scheduledDepart'] ?? DateFormat('HH:mm').format(DateTime.now()),
    );
    final String arriveStr = _calculateArrival(
      route['scheduledDepart'] ?? DateFormat('HH:mm').format(DateTime.now()),
      totalMins,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'JOURNEY SUMMARY',
          style: TextStyle(
            color: _textGrey,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _originDisplayName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _primaryBlue,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(
                        Icons.arrow_forward,
                        color: _primaryBlue.withValues(alpha: 0.5),
                        size: 16,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _destinationDisplayName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _primaryBlue,
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: lineDetails['color'],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  lineDetails['code'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    lineDetails['name'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        const Flexible(
                          child: Text(
                            'Recommended Route',
                            maxLines: 2,
                            style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(child: _buildInfoBlock('DEPART', departStr)),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey[200],
                        ),
                        Expanded(child: _buildInfoBlock('ARRIVE', arriveStr)),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey[200],
                        ),
                        Expanded(
                          child: _buildInfoBlock('DURATION', '$totalMins min'),
                        ),
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
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.credit_card,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ESTIMATED FARE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: _textGrey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      route['fare'] ?? 'RM 2.00',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: _textDark,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.directions_walk,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'WALK TO STATION',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: _textGrey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$walkMins min',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: _textDark,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('toggle-saved-route'),
                        onPressed: _isSavingRoute || _isStartingNavigation
                            ? null
                            : () => isSaved
                                  ? _removeSavedRoute(route)
                                  : _saveRoute(route),
                        icon: _isSavingRoute
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                isSaved
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                              ),
                        label: Text(isSaved ? 'Saved' : 'Save route'),
                      ),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isStartingNavigation || _isSavingRoute
                            ? null
                            : widget.selectForDailyCommute
                            ? () => Navigator.pop(
                                context,
                                _routeToSave(
                                  route,
                                  '$_originDisplayName → $_destinationDisplayName',
                                ),
                              )
                            : () => _startNavigation(
                                route,
                                totalMins,
                                departStr,
                                arriveStr,
                              ),
                        child: _isStartingNavigation
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                widget.selectForDailyCommute
                                    ? 'Use for Daily Commute'
                                    : 'Start Journey',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        Text(
          label,
          style: TextStyle(
            color: _textGrey,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: _textDark,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMoovitTimeline(
    Map<String, dynamic> route,
    String departTime,
    String arriveTime,
  ) {
    List<Widget> nodes = [];
    List<dynamic> rawLegs = route['legs'] ?? [];

    nodes.add(_buildStationNode(_originDisplayName, departTime, type: 'start'));

    String currentStation = _originDisplayName;

    for (int i = 0; i < rawLegs.length; i++) {
      var leg = rawLegs[i];

      if (leg['mode'] == 'Walk') {
        String transferStation = leg['desc']
            .replaceAll('Walk from ', '')
            .replaceAll(' to ', ' -> ');
        nodes.add(_buildWalkLeg(transferStation, leg['duration']));
        currentStation = transferStation.split(' -> ').last;
        if (i < rawLegs.length - 1 && rawLegs[i + 1]['mode'] != 'Walk') {
          nodes.add(
            _buildStationNode(currentStation, 'Boarding', type: 'transfer'),
          );
        }
      } else {
        String endStation = _destinationDisplayName;
        if (i + 1 < rawLegs.length && rawLegs[i + 1]['mode'] == 'Walk') {
          endStation = 'Next Transfer';
        }

        nodes.add(
          ExpandableTransitLeg(
            leg: leg as Map<String, dynamic>,
            startStation: currentStation,
            endStation: endStation,
          ),
        );
        currentStation = endStation;
      }
    }

    nodes.add(
      _buildStationNode(_destinationDisplayName, arriveTime, type: 'end'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: nodes,
    );
  }

  Widget _buildStationNode(String title, String time, {required String type}) {
    Color color = type == 'start'
        ? Colors.black
        : (type == 'end' ? Colors.green : Colors.orange);
    IconData icon = type == 'start'
        ? Icons.location_on
        : (type == 'end' ? Icons.location_on : Icons.adjust);

    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Icon(icon, color: color, size: type == 'transfer' ? 16 : 24),
        ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        Text(
          time,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
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
              child: const Text(
                '......',
                style: TextStyle(
                  color: Colors.grey,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const Icon(Icons.directions_walk, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  duration,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

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
    List<String> realStops =
        (widget.leg['intermediate_stops'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    int stopCount = realStops.length;

    if (stopCount == 0) {
      int durationMins =
          int.tryParse(
            widget.leg['duration'].toString().replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          15;
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
                height: _isExpanded
                    ? (realStops.isEmpty
                          ? stopCount * 28.0 + 60
                          : realStops.length * 28.0 + 60)
                    : 60,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        widget.leg['duration'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.grey[500],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (!_isExpanded)
                    Text(
                      realStops.isEmpty
                          ? 'Non-stop service'
                          : 'Ride ${realStops.length} stops towards ${widget.endStation}',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
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
                                Text(
                                  'Board at: ${widget.startStation}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                if (realStops.isNotEmpty)
                                  for (String stopName in realStops)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                        horizontal: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.circle,
                                            size: 6,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              stopName,
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                else
                                  for (int i = 1; i <= stopCount; i++)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                        horizontal: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.circle,
                                            size: 6,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            'Intermediate Stop $i',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                const SizedBox(height: 8),
                                Text(
                                  'Alight at: ${widget.endStation}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
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
// ROUTE MAP VIEWER SCREEN
// =========================================================================
class RouteMapViewerScreen extends StatefulWidget {
  final StationModel origin;
  final StationModel destination;
  final Map<String, dynamic>? route;
  final List<StationModel> allStations;
  final ApiService? apiService;

  const RouteMapViewerScreen({
    super.key,
    required this.origin,
    required this.destination,
    this.route,
    required this.allStations,
    this.apiService,
  });

  @override
  State<RouteMapViewerScreen> createState() => _RouteMapViewerScreenState();
}

class _RouteMapViewerScreenState extends State<RouteMapViewerScreen> {
  final MapController _mapController = MapController();
  List<LegGeometry> _legGeometries = [];

  late final ApiService _apiService;
  Timer? _liveTimer;
  List<LiveVehicle> _liveVehicles = [];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _calculatePath();
    _startLiveTracking();
  }

  void _startLiveTracking() {
    _fetchLiveVehicles();
    _liveTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchLiveVehicles(),
    );
  }

  Future<void> _fetchLiveVehicles() async {
    try {
      final dynamic api = _apiService;
      final busFeed = await api.getLiveVehicles('bus');
      final feederFeed = await api.getLiveVehicles('mrt_feeder');

      List<LiveVehicle> vehicles = [];
      if (busFeed is List) vehicles.addAll(busFeed.whereType<LiveVehicle>());
      if (feederFeed is List)
        vehicles.addAll(feederFeed.whereType<LiveVehicle>());

      if (mounted) {
        setState(() {
          _liveVehicles = vehicles;
        });
      }
    } catch (e) {
      debugPrint('Error fetching live vehicles in RouteMapViewer: $e');
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  bool _isVehicleOnRoute(LiveVehicle vehicle) {
    if (widget.route == null) return true;
    final String vRoute = vehicle.routeId.toUpperCase().trim();
    if (vRoute.isEmpty) return false;

    final legs = widget.route!['legs'] as List? ?? [];
    for (var leg in legs) {
      if (leg is Map) {
        final legName = (leg['name'] ?? '').toString().toUpperCase();
        if (legName == vRoute ||
            legName.contains(vRoute) ||
            vRoute.contains(legName))
          return true;
      }
    }

    final mainName = (widget.route!['name'] ?? '').toString().toUpperCase();
    final sig = (widget.route!['sig'] ?? '').toString().toUpperCase();
    if (mainName.contains(vRoute) || sig.contains(vRoute)) return true;

    return false;
  }

  List<Marker> _buildLiveVehicleMarkers() {
    final vehiclesToShow = _liveVehicles.where(_isVehicleOnRoute).toList();

    return vehiclesToShow.map((vehicle) {
      return Marker(
        point: LatLng(vehicle.lat, vehicle.lon),
        width: 60,
        height: 60,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE11D48),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                vehicle.routeId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Transform.rotate(
              angle: vehicle.bearing * (pi / 180),
              child: const Icon(
                Icons.navigation,
                color: Color(0xFFE11D48),
                size: 22,
                shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  void _calculatePath() async {
    if (widget.route != null && widget.route!['legs'] is List) {
      try {
        final legs = widget.route!['legs'] as List;
        final resolved = await RouteGeometry.resolve(legs);
        if (mounted && resolved.isNotEmpty) {
          setState(() {
            _legGeometries = resolved;
          });
          return;
        }
      } catch (e) {
        debugPrint('RouteGeometry resolve failed: $e');
      }
    }

    List<LatLng> fallback = [
      LatLng(widget.origin.lat, widget.origin.lon),
      LatLng(widget.destination.lat, widget.destination.lon),
    ];
    if (mounted) {
      setState(() {
        _legGeometries = [LegGeometry('Transit', 'fallback', fallback)];
      });
    }
  }

  Color _legColor(String mode) {
    if (mode == 'Walk') return Colors.green;
    if (mode == 'Rail') return const Color(0xFF1E50D6);
    if (mode == 'Bus') return const Color(0xFFE11D48);
    return const Color(0xFFE91E63);
  }

  List<Marker> _buildWaypointMarkers() {
    const dotsPerLeg = 3;
    final markers = <Marker>[];
    for (final leg in _legGeometries) {
      if (leg.points.length < 3) continue;
      final color = _legColor(leg.mode);
      for (var i = 1; i <= dotsPerLeg; i++) {
        final t = i / (dotsPerLeg + 1);
        final idx = (t * (leg.points.length - 1)).round().clamp(
          1,
          leg.points.length - 2,
        );
        markers.add(
          Marker(
            point: leg.points[idx],
            width: 14,
            height: 14,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  void _centerOnRoute() {
    if (_legGeometries.isEmpty) return;
    List<LatLng> allPoints = _legGeometries.expand((l) => l.points).toList();
    if (allPoints.isEmpty) return;

    double minLat = allPoints
        .map((p) => p.latitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLat = allPoints
        .map((p) => p.latitude)
        .reduce((a, b) => a > b ? a : b);
    double minLon = allPoints
        .map((p) => p.longitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLon = allPoints
        .map((p) => p.longitude)
        .reduce((a, b) => a > b ? a : b);

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
          child: const Icon(
            Icons.directions_subway,
            color: Colors.white,
            size: 20,
          ),
        ),
        Container(width: 2, height: 8, color: const Color(0xFF0033A0)),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE91E63), width: 3),
          ),
        ),
      ],
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE91E63), width: 3),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final liveVehiclesOnRoute = _liveVehicles.where(_isVehicleOnRoute).toList();
    List<LatLng> allPoints = _legGeometries.expand((l) => l.points).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
              top: 50,
              left: 16,
              right: 16,
              bottom: 20,
            ),
            color: const Color(0xFF1E50D6),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Route Map',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (liveVehiclesOnRoute.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.satellite_alt,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${liveVehiclesOnRoute.length} LIVE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _legGeometries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(
                        (widget.origin.lat + widget.destination.lat) / 2,
                        (widget.origin.lon + widget.destination.lon) / 2,
                      ),
                      initialZoom: 13.0,
                      onMapReady: () => _centerOnRoute(),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.nextroute.app',
                      ),
                      PolylineLayer(
                        polylines: _legGeometries.map((leg) {
                          return Polyline(
                            points: leg.points,
                            color: _legColor(leg.mode),
                            strokeWidth: 5.0,
                          );
                        }).toList(),
                      ),
                      EstimatedLrtLayer(route: widget.route),
                      MarkerLayer(markers: _buildWaypointMarkers()),
                      MarkerLayer(
                        markers: [
                          ..._buildLiveVehicleMarkers(),
                          if (allPoints.isNotEmpty) ...[
                            Marker(
                              point: allPoints.first,
                              width: 60,
                              height: 60,
                              alignment: Alignment.topCenter,
                              child: _buildStartPin(),
                            ),
                            Marker(
                              point: allPoints.last,
                              width: 60,
                              height: 60,
                              alignment: Alignment.topCenter,
                              child: _buildEndPin(),
                            ),
                          ],
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
// MAP PICKER MOCK SCREEN
// =========================================================================
class MapPickerMockScreen extends StatefulWidget {
  final List<StationModel> allStations;
  final ApiService apiService;

  const MapPickerMockScreen({
    super.key,
    required this.allStations,
    required this.apiService,
  });

  @override
  State<MapPickerMockScreen> createState() => _MapPickerMockScreenState();
}

class _MapPickerMockScreenState extends State<MapPickerMockScreen> {
  final MapController _mapController = MapController();
  LatLng _myLocation = const LatLng(3.1341, 101.6861);
  final TextEditingController _searchController = TextEditingController();

  String _routeFilter = '';
  bool _isLocating = false;

  Timer? _liveDataTimer;
  List<LiveVehicle> _liveBuses = [];
  bool _fetchingLiveBuses = false;

  List<Marker> _cachedStaticMarkers = [];

  @override
  void initState() {
    super.initState();
    _updateStaticMarkers();
    _getUserLocation();
    _startLiveTracking();
  }

  void _startLiveTracking() {
    _fetchLiveBuses();
    _liveDataTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchLiveBuses();
    });
  }

  Future<void> _fetchLiveBuses() async {
    if (_fetchingLiveBuses) return;
    _fetchingLiveBuses = true;
    try {
      final feeds = await Future.wait<List<LiveVehicle>>([
        widget.apiService.getLiveVehicles('bus'),
        widget.apiService.getLiveVehicles('mrt_feeder'),
      ]);
      final busFeed = feeds[0];
      final feederFeed = feeds[1];
      if (mounted) {
        final List<LiveVehicle> vehicles = [];
        vehicles.addAll(busFeed);
        vehicles.addAll(feederFeed);
        setState(() {
          _liveBuses = vehicles;
        });
      }
    } catch (e) {
      debugPrint('Live vehicles feed unavailable: $e');
    } finally {
      _fetchingLiveBuses = false;
    }
  }

  Future<void> _getUserLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _myLocation = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_myLocation, 15.0);
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  void dispose() {
    _liveDataTimer?.cancel();
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildMarker(StationModel station) {
    Color bgColor;
    IconData icon;

    if (station.category == 'Rail') {
      bgColor = Colors.blue;
      icon = Icons.train;
    } else if (station.category == 'MRT Feeder') {
      bgColor = Colors.teal;
      icon = Icons.directions_bus;
    } else {
      bgColor = Colors.orange;
      icon = Icons.directions_bus;
    }

    String stationName = station.name;

    return GestureDetector(
      onTap: () {
        Navigator.pop(context, {
          'lat': station.lat,
          'lon': station.lon,
          'name': station.name,
          'station': station,
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    stationName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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

  bool _matchesStationFilter(StationModel station, String filter) {
    if (filter.isEmpty) return true;
    final q = filter.toUpperCase().trim();

    if (station.name.toUpperCase().contains(q)) return true;

    final cat = station.category.toUpperCase();
    if ((q == 'LRT' || q == 'RAIL' || q == 'TRAIN') &&
        (cat == 'RAIL' ||
            station.lines.any(
              (l) =>
                  l.toUpperCase().contains('LINE') ||
                  l.toUpperCase().contains('LRT'),
            )))
      return true;
    if (q == 'MRT' && (cat == 'RAIL' || cat == 'MRT FEEDER')) return true;
    if (q == 'BUS' && (cat == 'BUS' || cat == 'MRT FEEDER')) return true;

    final isKjl =
        q == 'KJL' || q == 'KJ' || q == 'LINE 5' || q == 'KELANA JAYA';
    final isAgl = q == 'AGL' || q == 'AG' || q == 'LINE 3' || q == 'AMPANG';
    final isSpl =
        q == 'SPL' ||
        q == 'SP' ||
        q == 'PH' ||
        q == 'LINE 4' ||
        q == 'SRI PETALING';
    final isKgl =
        q == 'KGL' || q == 'KG' || q == 'SBK' || q == 'LINE 9' || q == 'KAJANG';
    final isPyl =
        q == 'PYL' ||
        q == 'PY' ||
        q == 'SSP' ||
        q == 'LINE 12' ||
        q == 'PUTRAJAYA';
    final isMrl = q == 'MRL' || q == 'MR' || q == 'LINE 8' || q == 'MONORAIL';
    final isBrt = q == 'BRT' || q == 'B1' || q == 'SUNWAY';

    for (var line in station.lines) {
      final upperLine = line.toUpperCase();
      if (upperLine.contains(q)) return true;
      if (isKjl &&
          (upperLine.contains('KELANA JAYA') ||
              upperLine.contains('LINE 5') ||
              upperLine.contains('KJL') ||
              upperLine.contains('KJ')))
        return true;
      if (isAgl &&
          (upperLine.contains('AMPANG') ||
              upperLine.contains('LINE 3') ||
              upperLine.contains('AGL') ||
              upperLine.contains('AG')))
        return true;
      if (isSpl &&
          (upperLine.contains('SRI PETALING') ||
              upperLine.contains('LINE 4') ||
              upperLine.contains('SPL') ||
              upperLine.contains('SP')))
        return true;
      if (isKgl &&
          (upperLine.contains('KAJANG') ||
              upperLine.contains('LINE 9') ||
              upperLine.contains('KGL') ||
              upperLine.contains('KG') ||
              upperLine.contains('SBK')))
        return true;
      if (isPyl &&
          (upperLine.contains('PUTRAJAYA') ||
              upperLine.contains('LINE 12') ||
              upperLine.contains('PYL') ||
              upperLine.contains('PY') ||
              upperLine.contains('SSP')))
        return true;
      if (isMrl &&
          (upperLine.contains('MONORAIL') ||
              upperLine.contains('LINE 8') ||
              upperLine.contains('MR')))
        return true;
      if (isBrt &&
          (upperLine.contains('BRT') ||
              upperLine.contains('B1') ||
              upperLine.contains('SUNWAY')))
        return true;
      List<String> routeTokens = upperLine.split(RegExp(r'[^A-Z0-9]+'));
      if (routeTokens.contains(q)) return true;
    }

    for (var id in station.ids) {
      final upperId = id.toUpperCase();
      if (isKjl && (upperId.contains('_KJ') || upperId.startsWith('KJ')))
        return true;
      if (isAgl && (upperId.contains('_AG') || upperId.startsWith('AG')))
        return true;
      if (isSpl &&
          (upperId.contains('_SP') ||
              upperId.startsWith('SP') ||
              upperId.contains('_PH')))
        return true;
      if (isKgl &&
          (upperId.contains('_KG') ||
              upperId.startsWith('KG') ||
              upperId.contains('_SBK')))
        return true;
      if (isPyl &&
          (upperId.contains('_PY') ||
              upperId.startsWith('PY') ||
              upperId.contains('_SSP')))
        return true;
      if (isMrl && (upperId.contains('_MR') || upperId.startsWith('MR')))
        return true;
    }

    return false;
  }

  void _updateStaticMarkers() {
    List<Marker> markers = [];
    int busCount = 0;

    for (var station in widget.allStations) {
      if (station.lat == 0 || station.lon == 0) continue;

      if (_routeFilter.isNotEmpty) {
        if (!_matchesStationFilter(station, _routeFilter)) continue;
      } else {
        if (station.category != 'Rail') {
          if (busCount >= 300) continue;
          busCount++;
        }
      }

      markers.add(
        Marker(
          point: LatLng(station.lat, station.lon),
          width: 200,
          height: 60,
          alignment: Alignment.topCenter,
          child: _buildMarker(station),
        ),
      );
    }
    _cachedStaticMarkers = markers;
  }

  List<Marker> _buildLiveBusMarkers() {
    List<Marker> markers = [];
    for (var bus in _liveBuses) {
      if (_routeFilter.isNotEmpty) {
        List<String> routeTokens = bus.routeId.toUpperCase().split(
          RegExp(r'[^A-Z0-9]+'),
        );
        bool matchesRoute =
            routeTokens.contains(_routeFilter) ||
            bus.routeId.toUpperCase() == _routeFilter;
        if (!matchesRoute) continue;
      }

      markers.add(
        Marker(
          point: LatLng(bus.lat, bus.lon),
          width: 60,
          height: 60,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  bus.routeId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Transform.rotate(
                angle: bus.bearing * (pi / 180),
                child: const Icon(
                  Icons.navigation,
                  color: Color(0xFFE11D48),
                  size: 24,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    List<Marker> activeLiveMarkers = _buildLiveBusMarkers();

    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
              top: 50,
              left: 16,
              right: 16,
              bottom: 20,
            ),
            color: const Color(0xFF8B5CF6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Row(
                    children: [
                      Icon(Icons.chevron_left, color: Colors.white, size: 24),
                      Text(
                        'Back',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Transit Map',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: activeLiveMarkers.isEmpty
                            ? Colors.grey
                            : Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.satellite_alt,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${activeLiveMarkers.length} LIVE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Live buses + estimated LRT squares. Search T250, T455, KJL or LRT.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),

          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _myLocation,
                    initialZoom: 13.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.nextroute.app',
                    ),
                    EstimatedLrtLayer(query: _routeFilter),
                    MarkerLayer(
                      markers: [
                        ..._cachedStaticMarkers,
                        ...activeLiveMarkers,

                        Marker(
                          point: _myLocation,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                    ),
                                  ],
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
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search,
                              size: 18,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Filter stations by route (e.g. 250)...',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _routeFilter = val.toUpperCase().trim();
                                    _updateStaticMarkers();
                                  });
                                },
                              ),
                            ),
                            if (_routeFilter.isNotEmpty)
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  setState(() {
                                    _routeFilter = '';
                                    _searchController.clear();
                                    _updateStaticMarkers();
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Positioned(
                  bottom: 24,
                  right: 24,
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    onPressed: _isLocating ? null : _getUserLocation,
                    child: _isLocating
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.my_location,
                            color: Color(0xFF8B5CF6),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
