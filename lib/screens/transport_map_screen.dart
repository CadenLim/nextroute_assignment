part of 'transport_data.dart';

class _TransitRoutePicker extends StatefulWidget {
  final String serviceName;
  final List<TransitRoute> routes;
  final TransitRoute? selectedRoute;

  const _TransitRoutePicker({
    required this.serviceName,
    required this.routes,
    required this.selectedRoute,
  });

  @override
  State<_TransitRoutePicker> createState() => _TransitRoutePickerState();
}

class _TransitRoutePickerState extends State<_TransitRoutePicker> {
  String query = '';

  String _badgeLabel(TransitRoute route) {
    final name = route.displayName;
    final abbreviation = RegExp(r'\(([^()]{1,10})\)\s*$').firstMatch(name);
    return abbreviation?.group(1) ?? name;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = widget.routes.where((route) {
      if (normalizedQuery.isEmpty) return true;
      return route.displayName.toLowerCase().contains(normalizedQuery) ||
          route.description.toLowerCase().contains(normalizedQuery);
    }).toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose a ${widget.serviceName} route',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: Navigator.of(context).pop,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Text(
                'The map will show stops and live vehicles for the selected route.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by route number or destination',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching bus route found.'))
                    : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final route = filtered[index];
                    final selected = widget.selectedRoute?.id == route.id;
                    return ListTile(
                      selected: selected,
                      leading: Container(
                        width: 72,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? _blue
                              : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          _badgeLabel(route),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.white : _blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(
                        route.description.isEmpty
                            ? '${widget.serviceName} route ${route.displayName}'
                            : route.description,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text('${route.stopIds.length} stops'),
                      trailing: selected
                          ? const Icon(Icons.check, color: _blue)
                          : const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, route),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RoadService { rapidKlBus, mrtFeeder }

extension on _RoadService {
  String get label => switch (this) {
    _RoadService.rapidKlBus => 'Rapid KL Bus',
    _RoadService.mrtFeeder => 'MRT Feeder',
  };

  String get stationSource => switch (this) {
    _RoadService.rapidKlBus => 'bus',
    _RoadService.mrtFeeder => 'mrt_feeder',
  };

  String get assetPath => switch (this) {
    _RoadService.rapidKlBus => 'assets/gtfs/bus',
    _RoadService.mrtFeeder => 'assets/gtfs/mrt_feeder',
  };

  String get realtimeCategory => switch (this) {
    _RoadService.rapidKlBus => 'rapid-bus-kl',
    _RoadService.mrtFeeder => 'rapid-bus-mrtfeeder',
  };

  Color get color => switch (this) {
    _RoadService.rapidKlBus => const Color(0xFF2563EB),
    _RoadService.mrtFeeder => const Color(0xFF0891B2),
  };
}

class TransitMapScreen extends StatefulWidget {
  const TransitMapScreen({super.key});

  @override
  State<TransitMapScreen> createState() => _TransitMapScreenState();
}

class _TransitMapScreenState extends State<TransitMapScreen> {
  final MapController mapController = MapController();
  List<Station> visibleStations = [];
  List<LiveVehicle> vehicles = [];
  List<TransitRoute> rapidBusRoutes = [];
  List<TransitRoute> feederRoutes = [];
  List<RailShape> railShapes = [];
  String? selectedRailLine;
  TransitRoute? selectedRoadRoute;
  _RoadService? selectedRoadService;
  loc.LocationData? position;
  StreamSubscription<loc.LocationData>? locationSubscription;
  Timer? vehicleRefreshTimer;
  bool loading = true;
  bool showRail = true;
  bool showRoadStops = true;
  bool showVehicles = false;
  bool refreshingVehicles = false;
  int vehicleRequestGeneration = 0;
  String? liveError;
  String? locationWarning;

  @override
  void initState() {
    super.initState();
    _loadMap();
  }

  Future<void> _loadMap() async {
    final allStations = await StationRepository.instance.loadAll();
    final availableBusRoutes = await TransitRouteRepository.load(
      _RoadService.rapidKlBus.assetPath,
    );
    final availableFeederRoutes = await TransitRouteRepository.load(
      _RoadService.mrtFeeder.assetPath,
    );
    final availableRailShapes = await RailShapeRepository.load();
    loc.LocationData? detectedPosition;
    try {
      final candidate = await DeviceLocationService.currentLocation();
      if (isInsideMalaysia(candidate.latitude, candidate.longitude)) {
        detectedPosition = candidate;
        locationSubscription = DeviceLocationService.locationStream().listen((
            data,
            ) {
          if (!mounted || !isInsideMalaysia(data.latitude, data.longitude)) {
            return;
          }
          setState(() => position = data);
        });
      } else {
        locationWarning = locationOutsideCoverageMessage(
          candidate.latitude,
          candidate.longitude,
        );
      }
    } catch (error) {
      locationWarning = error.toString().replaceFirst('Exception: ', '');
    }

    var centreLatitude = 3.1390;
    var centreLongitude = 101.6869;
    if (detectedPosition != null) {
      centreLatitude = detectedPosition.latitude;
      centreLongitude = detectedPosition.longitude;
    }

    final nearby =
    allStations
        .where((station) => station.latitude != 0 && station.longitude != 0)
        .map(
          (station) => station.withDistance(
        distanceKm(
          centreLatitude,
          centreLongitude,
          station.latitude,
          station.longitude,
        ),
      ),
    )
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));

    if (!mounted) return;
    setState(() {
      position = detectedPosition;
      visibleStations = nearby;
      rapidBusRoutes = availableBusRoutes;
      feederRoutes = availableFeederRoutes;
      railShapes = availableRailShapes;
      loading = false;
    });
  }

  Future<void> _refreshVehicles() async {
    final service = selectedRoadService;
    if (service == null || !mounted) return;
    final requestGeneration = ++vehicleRequestGeneration;
    setState(() {
      refreshingVehicles = true;
      liveError = null;
    });
    try {
      final latest = await RealtimeVehicleService.loadPrasaranaVehicles(
        service.realtimeCategory,
      );
      if (!mounted ||
          requestGeneration != vehicleRequestGeneration ||
          selectedRoadService != service) {
        return;
      }
      setState(() => vehicles = latest);
    } catch (error) {
      if (!mounted ||
          requestGeneration != vehicleRequestGeneration ||
          selectedRoadService != service) {
        return;
      }
      setState(() {
        liveError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && requestGeneration == vehicleRequestGeneration) {
        setState(() => refreshingVehicles = false);
      }
    }
  }

  void _startVehicleRefresh() {
    vehicleRefreshTimer?.cancel();
    vehicleRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
          (_) => _refreshVehicles(),
    );
  }

  void _stopVehicleRefresh() {
    vehicleRefreshTimer?.cancel();
    vehicleRefreshTimer = null;
    vehicleRequestGeneration++;
    refreshingVehicles = false;
  }

  Future<void> _toggleRoadService(_RoadService service, bool value) async {
    if (!value) {
      _stopVehicleRefresh();
      setState(() {
        selectedRoadService = null;
        selectedRoadRoute = null;
        showRoadStops = true;
        showVehicles = false;
        vehicles = [];
        liveError = null;
      });
      return;
    }

    final serviceChanged = selectedRoadService != service;
    _stopVehicleRefresh();
    setState(() {
      showRail = false;
      selectedRailLine = null;
      selectedRoadService = service;
      if (serviceChanged) selectedRoadRoute = null;
      showRoadStops = true;
      showVehicles = false;
      vehicles = [];
      liveError = null;
    });
    if (selectedRoadRoute == null) await _chooseRoadRoute(service);
  }

  void _toggleRail(bool value) {
    _stopVehicleRefresh();
    setState(() {
      showRail = value;
      if (value) {
        selectedRoadService = null;
        selectedRoadRoute = null;
        showRoadStops = true;
        showVehicles = false;
        vehicles = [];
        liveError = null;
      } else {
        selectedRailLine = null;
      }
    });
  }

  Future<void> _chooseRoadRoute(_RoadService service) async {
    final routes = service == _RoadService.rapidKlBus
        ? rapidBusRoutes
        : feederRoutes;
    final choice = await showDialog<TransitRoute>(
      context: context,
      builder: (dialogContext) => _TransitRoutePicker(
        serviceName: service.label,
        routes: routes,
        selectedRoute: selectedRoadService == service
            ? selectedRoadRoute
            : null,
      ),
    );
    if (!mounted || choice == null) return;
    setState(() {
      showRail = false;
      selectedRailLine = null;
      selectedRoadService = service;
      selectedRoadRoute = choice;
      showRoadStops = true;
      showVehicles = true;
    });
    _startVehicleRefresh();
    await _refreshVehicles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitStations(
        visibleStations.where(_stationMatchesSelectedRoadRoute).toList(),
      );
    });
  }

  void _toggleLiveVehicles(bool value) {
    if (value) {
      setState(() => showVehicles = true);
      _startVehicleRefresh();
      _refreshVehicles();
    } else {
      _stopVehicleRefresh();
      setState(() => showVehicles = false);
    }
  }

  void _toggleRoadStops(bool value) {
    setState(() => showRoadStops = value);
  }

  void _selectRailLine(String line, bool selected) {
    setState(() => selectedRailLine = selected ? line : null);
    final points = railShapes
        .where((shape) => !selected || shape.routeId == line)
        .expand((shape) => shape.points)
        .toList();
    _fitPoints(points);
  }

  void _fitStations(List<Station> stations) {
    _fitPoints(
      stations
          .map((station) => LatLng(station.latitude, station.longitude))
          .toList(),
    );
  }

  void _fitPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    var minimumLatitude = points.first.latitude;
    var maximumLatitude = points.first.latitude;
    var minimumLongitude = points.first.longitude;
    var maximumLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      minimumLatitude = math.min(minimumLatitude, point.latitude);
      maximumLatitude = math.max(maximumLatitude, point.latitude);
      minimumLongitude = math.min(minimumLongitude, point.longitude);
      maximumLongitude = math.max(maximumLongitude, point.longitude);
    }
    final span = math.max(
      maximumLatitude - minimumLatitude,
      maximumLongitude - minimumLongitude,
    );
    final zoom = switch (span) {
      > 1.2 => 8.0,
      > .7 => 9.0,
      > .35 => 10.0,
      > .18 => 11.0,
      > .09 => 12.0,
      > .045 => 13.0,
      _ => 14.0,
    };
    mapController.move(
      LatLng(
        (minimumLatitude + maximumLatitude) / 2,
        (minimumLongitude + maximumLongitude) / 2,
      ),
      zoom,
    );
  }

  bool _stationMatchesSelectedRoadRoute(Station station) {
    final service = selectedRoadService;
    final route = selectedRoadRoute;
    if (service == null || route == null) return false;
    if (!station.sources.contains(service.stationSource)) return false;
    return station.stopIds.any(route.stopIds.contains);
  }

  bool _vehicleMatchesSelectedRoadRoute(LiveVehicle vehicle) {
    final route = selectedRoadRoute;
    if (route == null) return false;
    final vehicleRoute = vehicle.routeId.trim().toUpperCase();
    return vehicleRoute == route.id.trim().toUpperCase() ||
        vehicleRoute == route.displayName.toUpperCase();
  }

  @override
  void dispose() {
    _stopVehicleRefresh();
    locationSubscription?.cancel();
    mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centre = position == null
        ? const LatLng(3.1390, 101.6869)
        : LatLng(position!.latitude, position!.longitude);
    final selectedRoadStops = visibleStations
        .where(_stationMatchesSelectedRoadRoute)
        .toList();
    final filteredStations = visibleStations.where((station) {
      final matchesRail =
          showRail &&
              station.sources.contains('rail') &&
              (selectedRailLine == null ||
                  station.lines.contains(selectedRailLine));
      final matchesRoad =
          showRoadStops &&
              selectedRoadService != null &&
              _stationMatchesSelectedRoadRoute(station);
      return matchesRail || matchesRoad;
    }).toList();
    final filteredVehicles = vehicles
        .where(_vehicleMatchesSelectedRoadRoute)
        .toList();
    final railLineIds = railShapes.map((shape) => shape.routeId).toSet().toList()
      ..sort();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _SimpleHeader(
              title: 'Transit Map',
              subtitle: 'Select rail or a bus route to explore the network',
              color: Color(0xFF6D28D9),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                children: [
                  FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      initialCenter: centre,
                      initialZoom: 13,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                        'com.example.nextroute_assignment',
                      ),
                      if (showRail && railShapes.isNotEmpty)
                        PolylineLayer(
                          polylines: railShapes
                              .map(
                                (shape) => Polyline(
                              points: shape.points,
                              color: shape.color.withValues(
                                alpha:
                                selectedRailLine == null ||
                                    selectedRailLine ==
                                        shape.routeId
                                    ? .85
                                    : .18,
                              ),
                              strokeWidth:
                              selectedRailLine == shape.routeId
                                  ? 6
                                  : 4,
                            ),
                          )
                              .toList(),
                        ),
                      if (selectedRoadService != null &&
                          selectedRoadRoute?.shapePoints.isNotEmpty ==
                              true)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: selectedRoadRoute!.shapePoints,
                              color: selectedRoadService!.color
                                  .withValues(alpha: .85),
                              strokeWidth: 5,
                            ),
                          ],
                        ),
                      if (filteredStations.isNotEmpty)
                        MarkerLayer(
                          markers: filteredStations.map((station) {
                            final isRoadStop =
                                selectedRoadService != null &&
                                    _stationMatchesSelectedRoadRoute(station);
                            final markerColor = isRoadStop
                                ? selectedRoadService!.color
                                : station.lines.isEmpty
                                ? const Color(0xFF7C3AED)
                                : lineColor(station.lines.first);
                            final markerForeground = isRoadStop
                                ? Colors.white
                                : station.lines.isEmpty
                                ? Colors.white
                                : lineForegroundColor(
                              station.lines.first,
                            );
                            final markerIcon = isRoadStop
                                ? Icons.directions_bus
                                : Icons.train;
                            final routeText = isRoadStop
                                ? selectedRoadRoute?.displayName
                                : null;
                            return Marker(
                              point: LatLng(
                                station.latitude,
                                station.longitude,
                              ),
                              width: 42,
                              height: 42,
                              child: Tooltip(
                                message: routeText == null
                                    ? '${station.name}\n'
                                    '${station.lines.map(railLineName).join(', ')}'
                                    : '${station.name}\n'
                                    '${selectedRoadService!.label} '
                                    'route $routeText',
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: markerColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 5,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    tooltip: station.name,
                                    padding: EdgeInsets.zero,
                                    onPressed: () => openStationDetails(
                                      context,
                                      station,
                                    ),
                                    icon: Icon(
                                      markerIcon,
                                      color: markerForeground,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      if (selectedRoadService != null &&
                          selectedRoadRoute != null &&
                          showVehicles)
                        MarkerLayer(
                          markers: filteredVehicles.map((vehicle) {
                            return Marker(
                              point: LatLng(
                                vehicle.latitude,
                                vehicle.longitude,
                              ),
                              width: 38,
                              height: 38,
                              child: Tooltip(
                                message:
                                'Bus ${vehicle.id}\nRoute ${vehicle.routeId}',
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color:
                                    selectedRoadService ==
                                        _RoadService.mrtFeeder
                                        ? const Color(0xFF0F766E)
                                        : Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.directions_bus,
                                    color: Colors.white,
                                    size: 23,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      if (position != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: centre,
                              width: 44,
                              height: 44,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(blurRadius: 8)],
                                ),
                                child: Icon(
                                  Icons.my_location,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            'OpenStreetMap contributors',
                            onTap: () => launchUrl(
                              Uri.parse(
                                'https://www.openstreetmap.org/copyright',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 10,
                    child: Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('Rail lines'),
                              selected: showRail,
                              onSelected: _toggleRail,
                            ),
                            if (showRail)
                              ...railLineIds.map(
                                    (line) => Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: railLineName(line),
                                    child: ChoiceChip(
                                      avatar: CircleAvatar(
                                        backgroundColor: lineColor(line),
                                        child: Text(
                                          line,
                                          style: TextStyle(
                                            color: lineForegroundColor(
                                              line,
                                            ),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      label: Text(railLineName(line)),
                                      selected:
                                      selectedRailLine == line,
                                      onSelected: (selected) =>
                                          _selectRailLine(line, selected),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            FilterChip(
                              avatar: const Icon(
                                Icons.directions_bus,
                                size: 18,
                              ),
                              label: const Text('Bus routes & stops'),
                              selected:
                              selectedRoadService ==
                                  _RoadService.rapidKlBus,
                              selectedColor: const Color(0xFFBFDBFE),
                              side: BorderSide(
                                color:
                                selectedRoadService ==
                                    _RoadService.rapidKlBus
                                    ? _blue
                                    : const Color(0xFFCBD5E1),
                                width:
                                selectedRoadService ==
                                    _RoadService.rapidKlBus
                                    ? 1.5
                                    : 1,
                              ),
                              onSelected: (value) => _toggleRoadService(
                                _RoadService.rapidKlBus,
                                value,
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilterChip(
                              avatar: const Icon(
                                Icons.airport_shuttle,
                                size: 18,
                              ),
                              label: const Text('MRT feeder'),
                              selected:
                              selectedRoadService ==
                                  _RoadService.mrtFeeder,
                              selectedColor: const Color(0xFFCFFAFE),
                              onSelected: (value) => _toggleRoadService(
                                _RoadService.mrtFeeder,
                                value,
                              ),
                            ),
                            if (selectedRoadService != null) ...[
                              const SizedBox(width: 6),
                              InputChip(
                                avatar: const Icon(
                                  Icons.alt_route,
                                  size: 17,
                                ),
                                label: Text(
                                  selectedRoadRoute == null
                                      ? 'Choose a '
                                      '${selectedRoadService!.label} route'
                                      : selectedRoadRoute!
                                      .description
                                      .isEmpty
                                      ? 'Route '
                                      '${selectedRoadRoute!.displayName}'
                                      : 'Route '
                                      '${selectedRoadRoute!.displayName}: '
                                      '${selectedRoadRoute!.description}',
                                ),
                                backgroundColor: const Color(0xFFFFF7ED),
                                selectedColor: const Color(0xFFDBEAFE),
                                side: BorderSide(
                                  color: selectedRoadRoute == null
                                      ? const Color(0xFFF59E0B)
                                      : selectedRoadService!.color,
                                  width: 1.5,
                                ),
                                selected: selectedRoadRoute != null,
                                onPressed: () => _chooseRoadRoute(
                                  selectedRoadService!,
                                ),
                                onDeleted: selectedRoadRoute == null
                                    ? null
                                    : () {
                                  _stopVehicleRefresh();
                                  setState(() {
                                    selectedRoadRoute = null;
                                    showRoadStops = true;
                                    showVehicles = false;
                                    vehicles = [];
                                    liveError = null;
                                  });
                                },
                              ),
                            ],
                            if (selectedRoadService != null &&
                                selectedRoadRoute != null) ...[
                              const SizedBox(width: 6),
                              FilterChip(
                                avatar: const Icon(
                                  Icons.place_outlined,
                                  size: 17,
                                ),
                                label: Text(
                                  'Stops on '
                                      '${selectedRoadRoute!.displayName} '
                                      '(${selectedRoadStops.length})',
                                ),
                                selected: showRoadStops,
                                selectedColor: const Color(0xFFDBEAFE),
                                onSelected: _toggleRoadStops,
                              ),
                              const SizedBox(width: 6),
                              FilterChip(
                                avatar: const Icon(
                                  Icons.directions_bus,
                                  size: 17,
                                ),
                                label: Text(
                                  'Live buses on '
                                      '${selectedRoadRoute!.displayName} '
                                      '(${filteredVehicles.length})',
                                ),
                                selected: showVehicles,
                                selectedColor: const Color(0xFFFED7AA),
                                onSelected: _toggleLiveVehicles,
                              ),
                              IconButton(
                                tooltip:
                                'Refresh live buses on route '
                                    '${selectedRoadRoute!.displayName}',
                                onPressed: refreshingVehicles
                                    ? null
                                    : _refreshVehicles,
                                icon: refreshingVehicles
                                    ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                    : const Icon(Icons.refresh),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    bottom: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'map_fit_stops',
                          tooltip: 'Show all visible stops',
                          onPressed: () => _fitStations(filteredStations),
                          child: const Icon(Icons.zoom_out_map),
                        ),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                          heroTag: 'map_recentre',
                          tooltip: position == null
                              ? 'Klang Valley overview'
                              : 'My location',
                          onPressed: () => mapController.move(centre, 13),
                          child: Icon(
                            position == null
                                ? Icons.home_work
                                : Icons.my_location,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (locationWarning != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 78,
                      child: _MapNotice(message: locationWarning!),
                    ),
                  if (selectedRoadService != null &&
                      selectedRoadRoute != null &&
                      showVehicles &&
                      liveError != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 76,
                      child: Material(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            liveError!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  if (selectedRoadService != null &&
                      selectedRoadRoute != null &&
                      showVehicles &&
                      !refreshingVehicles &&
                      liveError == null &&
                      filteredVehicles.isEmpty)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 76,
                      child: Material(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'No live buses are available for Route '
                                '${selectedRoadRoute!.displayName} right now. '
                                '${showRoadStops ? 'Scheduled stops are still shown.' : 'Turn on Stops to view scheduled stops.'}',
                            style: const TextStyle(color: Colors.white),
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
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageCard({
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(color: _ink, height: 1.4)),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _MapNotice extends StatelessWidget {
  final String message;
  const _MapNotice({required this.message});

  @override
  Widget build(BuildContext context) => Material(
    elevation: 2,
    color: const Color(0xFFFFFBEB),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_off_outlined, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$message The map is showing the Klang Valley overview.',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, height: 1.35),
            ),
          ),
        ],
      ),
    ),
  );
}
