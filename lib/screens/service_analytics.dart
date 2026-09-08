import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:nextroute_assignment/services/analytics_service.dart';
import 'package:nextroute_assignment/services/module5_route_preferences.dart';
import 'package:nextroute_assignment/services/module5_user_route_context.dart';

const _autoRefreshInterval = Duration(seconds: 30);
const _activeJourneyScope = module5ActiveJourneyScope;
const _routineRoutesScope = module5RoutineRoutesScope;
const _myRoutesScope = module5MyRoutesScope;
const _allNetworkScope = module5AllNetworkScope;

class _RouteAvailabilityPresentation {
  const _RouteAvailabilityPresentation(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

_RouteAvailabilityPresentation _availabilityForRoute(
  BusRouteInfo route,
  ServiceAnalytics? analytics,
) {
  if (analytics == null) {
    return const _RouteAvailabilityPresentation(
      'Checking realtime availability',
      Icons.sync,
      Colors.blueGrey,
    );
  }
  final matches = analytics.sourceStatuses.where(
    (source) => source.category == route.sourceCategory,
  );
  if (matches.isEmpty) {
    return const _RouteAvailabilityPresentation(
      'Timetable only',
      Icons.event_note,
      Colors.blueGrey,
    );
  }
  final source = matches.first;
  if (source.availability == RealtimeFeedAvailability.unavailable ||
      source.availability == RealtimeFeedAvailability.noVehicleData) {
    return const _RouteAvailabilityPresentation(
      'Realtime unavailable',
      Icons.cloud_off_outlined,
      Colors.orange,
    );
  }
  if (source.availability == RealtimeFeedAvailability.stale) {
    return const _RouteAvailabilityPresentation(
      'Realtime data is stale',
      Icons.update_disabled,
      Colors.orange,
    );
  }
  final active = analytics.vehiclesByRoute.keys.any(
    (id) => BusRouteCatalog.matches(id, route.routeCode, {
      id: route,
      route.id: route,
      route.routeCode: route,
    }),
  );
  return active
      ? const _RouteAvailabilityPresentation(
          'Live now',
          Icons.location_on,
          Colors.green,
        )
      : const _RouteAvailabilityPresentation(
          'No active vehicles now',
          Icons.directions_bus_outlined,
          Colors.blueGrey,
        );
}

bool _routeIncluded(
  String? routeId,
  String scope,
  Set<String> followedRoutes,
  Map<String, BusRouteInfo> busRoutes, {
  Set<String> activeRoutes = const {},
  Set<String> routineRoutes = const {},
}) {
  if (scope == _allNetworkScope) return true;

  if (routeId == null) return true;
  final scopedRoutes = switch (scope) {
    _activeJourneyScope => activeRoutes,
    _routineRoutesScope => routineRoutes,
    _myRoutesScope => followedRoutes,
    _ => const <String>{},
  };
  if (scopedRoutes.isEmpty &&
      scope != _activeJourneyScope &&
      scope != _routineRoutesScope &&
      scope != _myRoutesScope) {
    return BusRouteCatalog.matches(routeId, scope, busRoutes);
  }
  return scopedRoutes.any(
    (route) => BusRouteCatalog.matches(routeId, route, busRoutes),
  );
}

String _scopeLabel(
  String scope,
  Set<String> followedRoutes, {
  Set<String> activeRoutes = const {},
  Set<String> routineRoutes = const {},
}) => switch (scope) {
  _allNetworkScope => 'All network',
  _activeJourneyScope => 'Active Journey (${activeRoutes.length})',
  _routineRoutesScope => 'Daily Commute / Favourites (${routineRoutes.length})',
  _myRoutesScope => 'My Routes (${followedRoutes.length})',
  _ => 'Route $scope',
};

Set<String> _catalogRouteCodes(
  Iterable<String> rawRoutes,
  Map<String, BusRouteInfo> busRoutes,
) {
  final normalized = {
    for (final route in rawRoutes)
      if (route.trim().isNotEmpty) route.trim().toUpperCase(),
  };
  if (busRoutes.isEmpty) return normalized;
  return {
    for (final route in BusRouteCatalog.selectable(busRoutes))
      if (normalized.any(
        (raw) => BusRouteCatalog.matches(raw, route.routeCode, busRoutes),
      ))
        route.routeCode.toUpperCase(),
  };
}

class ServiceAnalyticsScreen extends StatefulWidget {
  const ServiceAnalyticsScreen({
    this.embedded = false,
    this.routePreferences,
    this.routeContext,
    super.key,
  });

  final bool embedded;
  final Module5RoutePreferences? routePreferences;
  final Module5UserRouteContext? routeContext;

  @override
  State<ServiceAnalyticsScreen> createState() => _ServiceAnalyticsScreenState();
}

class _ServiceAnalyticsScreenState extends State<ServiceAnalyticsScreen> {
  final GtfsRealtimeService _service = GtfsRealtimeService(
    endpoints: GtfsRealtimeService.kualaLumpurBusEndpoints,
  );
  final ServiceAnalyticsCalculator _calculator =
      const ServiceAnalyticsCalculator();

  late final SupabaseAnalyticsRepository _history;
  late final Module5RoutePreferences _routePreferences;
  late final Module5UserRouteContext _routeContext;
  late final bool _ownsRoutePreferences;
  late final bool _ownsRouteContext;
  late Future<ServiceAnalytics> _analyticsFuture;
  ServiceAnalytics? _lastAnalytics;
  List<DailyAnalyticsSummary> _dailySummaries = const [];
  List<AnalyticsAlert> _alerts = const [];
  Object? _alertsError;
  DateTime? _historyUpdatedAt;
  bool _historyRequestRunning = false;
  Map<String, BusRouteInfo> _busRoutes = const {};
  Object? _historyError;
  Timer? _refreshTimer;
  int _selectedTab = 0;
  bool _isLoading = true;
  bool _isHistoryLoading = true;
  String _routeScope = _allNetworkScope;
  bool _routeScopeChosenByUser = false;

  @override
  void initState() {
    super.initState();
    _ownsRoutePreferences = widget.routePreferences == null;
    _routePreferences = widget.routePreferences ?? Module5RoutePreferences();
    _ownsRouteContext = widget.routeContext == null;
    _routeContext = widget.routeContext ?? Module5UserRouteContext();
    _routePreferences.addListener(_routePreferencesChanged);
    _routeContext.addListener(_routeContextChanged);
    if (!_routePreferences.loaded) _routePreferences.load();
    _routeContext.load();
    _history = SupabaseAnalyticsRepository();
    _analyticsFuture = _loadAnalytics();
    _loadCloudHistory();
    _loadBusRoutes();
    _refreshTimer = Timer.periodic(_autoRefreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _service.close();
    _routePreferences.removeListener(_routePreferencesChanged);
    _routeContext.removeListener(_routeContextChanged);
    if (_ownsRoutePreferences) _routePreferences.dispose();
    if (_ownsRouteContext) _routeContext.dispose();
    super.dispose();
  }

  void _routePreferencesChanged() {
    if (!mounted) return;
    _synchroniseRouteScope();
    setState(() {});
  }

  void _routeContextChanged() {
    if (!mounted) return;
    _synchroniseRouteScope(prioritiseNewActiveJourney: true);
    setState(() {});
  }

  Set<String> get _activeRoutes =>
      _catalogRouteCodes(_routeContext.activeRoutes, _busRoutes);

  Set<String> get _routineRoutes =>
      _catalogRouteCodes(_routeContext.routineRoutes, _busRoutes);

  void _synchroniseRouteScope({bool prioritiseNewActiveJourney = false}) {
    final active = _activeRoutes;
    final routine = _routineRoutes;
    final followed = _routePreferences.followedRoutes;
    final availableIndividualRoutes = {...active, ...routine, ...followed};
    final valid = switch (_routeScope) {
      _activeJourneyScope => active.isNotEmpty,
      _routineRoutesScope => routine.isNotEmpty,
      _myRoutesScope => followed.isNotEmpty,
      _allNetworkScope => true,
      _ => availableIndividualRoutes.contains(_routeScope),
    };
    if (prioritiseNewActiveJourney && active.isNotEmpty) {
      _routeScope = _activeJourneyScope;
      _routeScopeChosenByUser = false;
    } else if (!valid || !_routeScopeChosenByUser) {
      _routeScope = module5PreferredScope(
        activeRoutes: active,
        routineRoutes: routine,
        myRoutes: followed,
      );
    }
  }

  Future<void> _refresh() async {
    if (_isLoading) {
      return;
    }
    setState(() {
      _isLoading = true;
      _analyticsFuture = _loadAnalytics();
    });
    _loadCloudHistory();
    unawaited(_routeContext.refreshPersonalRoutes(force: true));
    try {
      await _analyticsFuture;
    } on Object {

    }
  }

  Future<ServiceAnalytics> _loadAnalytics() async {
    try {
      final feed = await _service.fetchVehiclePositions();
      final analytics = _calculator.calculate(feed);
      _lastAnalytics = analytics;
      return analytics;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCloudHistory() async {
    if (_historyRequestRunning) return;
    _historyRequestRunning = true;
    if (mounted) {
      setState(() {
        _isHistoryLoading = true;
        _historyError = null;
      });
    }
    try {
      final today = AnalyticsPeriod.day(DateTime.now());
      final start = AnalyticsPeriod.monday(
        today,
      ).subtract(const Duration(days: 56));
      final end = today.add(const Duration(days: 1));
      List<DailyAnalyticsSummary>? summaries;
      List<AnalyticsAlert>? alerts;
      Object? summaryError;
      Object? alertError;
      await Future.wait([
        _history
            .loadSummaries(start: start, end: end)
            .then((value) {
              summaries = value;
            })
            .catchError((Object error) {
              summaryError = error;
            }),
        _history
            .loadAlerts(start: start, end: end)
            .then((value) {
              alerts = value;
            })
            .catchError((Object error) {
              alertError = error;
            }),
      ]);
      if (mounted) {
        setState(() {
          if (summaries != null) _dailySummaries = summaries!;
          if (alerts != null) _alerts = alerts!;
          _historyError = summaryError;
          _alertsError = alertError;
          if (summaryError == null && alertError == null) {
            _historyUpdatedAt = DateTime.now();
          }
          _isHistoryLoading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _historyError = error;
          _isHistoryLoading = false;
        });
      }
    } finally {
      _historyRequestRunning = false;
    }
  }

  Future<void> _loadBusRoutes() async {
    try {
      final routes = await BusRouteCatalog.load();
      if (mounted) {
        setState(() {
          _busRoutes = routes;
          _synchroniseRouteScope();
        });
      }
    } on Object {

    }
  }

  Future<void> _manageRoutes() async {
    if (_busRoutes.isEmpty) return;
    final selected = Set<String>.from(_routePreferences.followedRoutes);
    final routes = BusRouteCatalog.selectable(_busRoutes);
    var query = '';
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visible = routes.where((route) {
            final value = query.toLowerCase();
            return route.routeCode.toLowerCase().contains(value) ||
                route.longName.toLowerCase().contains(value);
          }).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.82,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Choose My Routes',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(sheetContext, selected),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search bus route',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = value.trim()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final route = visible[index];
                        final code = route.routeCode.toUpperCase();
                        final availability = _availabilityForRoute(
                          route,
                          _lastAnalytics,
                        );
                        return CheckboxListTile(
                          value: selected.contains(code),
                          onChanged: (checked) => setSheetState(() {
                            checked == true
                                ? selected.add(code)
                                : selected.remove(code);
                          }),
                          title: Text('Route ${route.routeCode}'),
                          subtitle: Text(
                            '${route.longName}\n${availability.label}',
                          ),
                          secondary: Icon(
                            availability.icon,
                            color: availability.color,
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result != null) await _routePreferences.replace(result);
  }

  @override
  Widget build(BuildContext context) {
    _synchroniseRouteScope();
    final activeRoutes = _activeRoutes;
    final routineRoutes = _routineRoutes;
    final content = Column(
      children: [
        _AnalyticsTabs(
          selectedIndex: _selectedTab,
          onSelected: (index) => setState(() => _selectedTab = index),
        ),
        _RouteScopeBar(
          routes: _routePreferences.followedRoutes,
          activeRoutes: activeRoutes,
          routineRoutes: routineRoutes,
          selected: _routeScope,
          onSelected: (value) => setState(() {
            _routeScope = value;
            _routeScopeChosenByUser = true;
          }),
          onManage: _manageRoutes,
        ),
        Expanded(
          child: _buildSelectedTab(
            activeRoutes: activeRoutes,
            routineRoutes: routineRoutes,
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Analytics'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _refresh,
            tooltip: 'Refresh analytics',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildSelectedTab({
    required Set<String> activeRoutes,
    required Set<String> routineRoutes,
  }) {
    return switch (_selectedTab) {
      0 => FutureBuilder<ServiceAnalytics>(
        future: _analyticsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error, onRetry: _refresh);
          }
          final analytics = snapshot.data;
          return analytics == null
              ? _ErrorState(error: 'No data returned.', onRetry: _refresh)
              : _LiveServiceView(
                  analytics: analytics,
                  busRoutes: _busRoutes,
                  followedRoutes: _routePreferences.followedRoutes,
                  activeRoutes: activeRoutes,
                  routineRoutes: routineRoutes,
                  routeScope: _routeScope,
                  alerts: _alerts,
                  isLoading: _isLoading,
                  onRefresh: _refresh,
                );
        },
      ),
      _ => AnalyticsHistoryView(
        key: ValueKey(_selectedTab),
        report: _selectedTab == 2,
        summaries: _dailySummaries,
        alerts: _alerts,
        alertsError: _alertsError,
        updatedAt: _historyUpdatedAt,
        isLoading: _isHistoryLoading,
        error: _historyError,
        onRetry: _loadCloudHistory,
        routeScope: _routeScope,
        followedRoutes: _routePreferences.followedRoutes,
        activeRoutes: activeRoutes,
        routineRoutes: routineRoutes,
        busRoutes: _busRoutes,
      ),
    };
  }
}

class _AnalyticsTabs extends StatelessWidget {
  const _AnalyticsTabs({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['Live Service', 'Trend Dashboard', 'Reports'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            ChoiceChip(
              label: Text(labels[index]),
              selected: selectedIndex == index,
              onSelected: (_) => onSelected(index),
            ),
            if (index != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RouteScopeBar extends StatelessWidget {
  const _RouteScopeBar({
    required this.routes,
    required this.activeRoutes,
    required this.routineRoutes,
    required this.selected,
    required this.onSelected,
    required this.onManage,
  });

  final Set<String> routes;
  final Set<String> activeRoutes;
  final Set<String> routineRoutes;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final values = {...activeRoutes, ...routineRoutes, ...routes}.toList()
      ..sort();
    final validSelected =
        (selected == _activeJourneyScope && activeRoutes.isNotEmpty) ||
        (selected == _routineRoutesScope && routineRoutes.isNotEmpty) ||
        selected == _myRoutesScope ||
        selected == _allNetworkScope ||
        values.contains(selected);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: validSelected ? selected : _allNetworkScope,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Analytics for',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                if (activeRoutes.isNotEmpty)
                  DropdownMenuItem(
                    value: _activeJourneyScope,
                    child: Text(
                      'Active Journey · ${(activeRoutes.toList()..sort()).join(', ')}',
                    ),
                  ),
                if (routineRoutes.isNotEmpty)
                  DropdownMenuItem(
                    value: _routineRoutesScope,
                    child: Text(
                      'Daily Commute / Favourites (${routineRoutes.length})',
                    ),
                  ),
                DropdownMenuItem(
                  value: _myRoutesScope,
                  child: Text('My Routes (${routes.length})'),
                ),
                const DropdownMenuItem(
                  value: _allNetworkScope,
                  child: Text('All network'),
                ),
                for (final route in values)
                  DropdownMenuItem(value: route, child: Text('Route $route')),
              ],
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.star_outline),
            label: const Text('Manage'),
          ),
        ],
      ),
    );
  }
}

class _LiveServiceView extends StatelessWidget {
  const _LiveServiceView({
    required this.analytics,
    required this.busRoutes,
    required this.followedRoutes,
    required this.activeRoutes,
    required this.routineRoutes,
    required this.routeScope,
    required this.alerts,
    required this.isLoading,
    required this.onRefresh,
  });

  final ServiceAnalytics analytics;
  final Map<String, BusRouteInfo> busRoutes;
  final Set<String> followedRoutes;
  final Set<String> activeRoutes;
  final Set<String> routineRoutes;
  final String routeScope;
  final List<AnalyticsAlert> alerts;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final emptyFeed = analytics.vehicleCount == 0;
    final visibleRoutes = <String, int>{
      for (final entry in analytics.vehiclesByRoute.entries)
        if (_routeIncluded(
          entry.key,
          routeScope,
          followedRoutes,
          busRoutes,
          activeRoutes: activeRoutes,
          routineRoutes: routineRoutes,
        ))
          entry.key: entry.value,
    };
    final now = DateTime.now().toUtc();
    final currentAlerts = alerts.where(
      (alert) =>
          alert.isCurrentAt(now) &&
          !alert.isDataHealth &&
          _routeIncluded(
            alert.routeId,
            routeScope,
            followedRoutes,
            busRoutes,
            activeRoutes: activeRoutes,
            routineRoutes: routineRoutes,
          ),
    );
    final delayAlerts = currentAlerts
        .where((alert) => alert.type == TransitNotificationType.delay)
        .length;
    final slowAlerts = currentAlerts
        .where((alert) => alert.type == TransitNotificationType.crowd)
        .length;
    final scopedVehicleCount = visibleRoutes.values.fold<int>(
      0,
      (a, b) => a + b,
    );
    final specificRoute =
        routeScope == _myRoutesScope ||
            routeScope == _activeJourneyScope ||
            routeScope == _routineRoutesScope ||
            routeScope == _allNetworkScope
        ? null
        : busRoutes[routeScope];
    final availability = specificRoute == null
        ? null
        : _availabilityForRoute(specificRoute, analytics);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
            children: [
              _StatusCard(
                emptyFeed: emptyFeed,
                latestUpdate: analytics.latestUpdate,
                isLoading: isLoading,
                onRefresh: onRefresh,
              ),
              if (routeScope == _myRoutesScope && followedRoutes.isEmpty) ...[
                const SizedBox(height: 12),
                const _InformationCard(
                  icon: Icons.star_outline,
                  title: 'Choose the bus routes you use',
                  message:
                      'Use Manage to follow routes. Live service, trends and notifications will then focus on My Routes.',
                ),
              ],
              if (specificRoute != null && availability != null) ...[
                const SizedBox(height: 12),
                _InformationCard(
                  icon: availability.icon,
                  iconColor: availability.color,
                  title:
                      'Route ${specificRoute.routeCode} • ${availability.label}',
                  message: availability.label == 'Realtime unavailable'
                      ? '${specificRoute.longName}. The timetable remains available, but delay and congestion cannot be calculated until its realtime feed returns vehicles.'
                      : specificRoute.longName,
                ),
              ],
              const SizedBox(height: 12),
              _CompactCardGrid(
                wideColumns: 4,
                children: [
                  _MetricTile(
                    label: 'Observed buses',
                    value:
                        '${routeScope == _allNetworkScope ? analytics.vehicleCount : scopedVehicleCount}',
                    color: const Color(0xFF2962FF),
                    icon: Icons.directions_bus,
                  ),
                  _MetricTile(
                    label: 'Observed bus routes',
                    value:
                        '${routeScope == _allNetworkScope ? analytics.routeCount : visibleRoutes.length}',
                    color: const Color(0xFF7C3AED),
                    icon: Icons.route,
                  ),
                  _MetricTile(
                    label: 'Active delay alerts',
                    value: '$delayAlerts',
                    color: const Color(0xFFF59E0B),
                    icon: Icons.traffic,
                  ),
                  _MetricTile(
                    label: 'Possible slow movement',
                    value: '$slowAlerts',
                    color: const Color(0xFFEF4444),
                    icon: Icons.warning_amber,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _InformationCard(
                icon: Icons.info_outline,
                title: 'How live congestion is handled',
                message:
                    'The public feed does not currently provide usable congestion levels. '
                    'NextRoute only publishes Possible slow movement after repeated fresh GPS observations; '
                    'normal stop dwell and missing data are not treated as congestion.',
              ),
              const SizedBox(height: 12),
              _FeedStatusCard(statuses: analytics.sourceStatuses),
              const SizedBox(height: 12),
              Text(
                'ROUTE ACTIVITY',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF71809F),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              if (visibleRoutes.isEmpty)
                _InformationCard(
                  icon: Icons.info_outline,
                  title: routeScope == _myRoutesScope && followedRoutes.isEmpty
                      ? 'No routes selected'
                      : 'No active realtime vehicles for this selection',
                  message: emptyFeed
                      ? 'No configured Kuala Lumpur bus feed returned vehicle records. Refresh later; missing data is not zero service.'
                      : 'Other routes may have live vehicles. This selection can remain followed and will update automatically when its feed reports service.',
                )
              else
                _RouteActivityCard(routes: visibleRoutes, busRoutes: busRoutes),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.emptyFeed,
    required this.latestUpdate,
    required this.isLoading,
    required this.onRefresh,
  });

  final bool emptyFeed;
  final DateTime? latestUpdate;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final age = latestUpdate == null
        ? null
        : DateTime.now().toUtc().difference(latestUpdate!.toUtc());
    final freshnessUnknown = age == null || age.inSeconds < -60;
    final stale = age != null && age > const Duration(minutes: 5);
    final warning = emptyFeed || freshnessUnknown || stale;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (warning ? Colors.orange : Colors.green).withValues(
                  alpha: 0.12,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                emptyFeed
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
                color: warning ? Colors.orange : Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    emptyFeed
                        ? 'Feed online — no vehicles'
                        : freshnessUnknown
                        ? 'Feed received — freshness unknown'
                        : stale
                        ? 'Feed received — vehicle data is stale'
                        : 'Feed received — recent positions available',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    latestUpdate == null
                        ? 'Vehicle timestamp not provided'
                        : 'Latest update ${_formatDataAge(latestUpdate!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: isLoading ? null : onRefresh,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedStatusCard extends StatelessWidget {
  const _FeedStatusCard({required this.statuses});

  final List<RealtimeFeedStatus> statuses;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.cloud_queue),
        title: const Text('Realtime source status'),
        subtitle: const Text(
          'A feed response and a bus route being active are different things.',
        ),
        children: [
          if (statuses.isEmpty)
            const ListTile(title: Text('Source diagnostics unavailable')),
          for (final status in statuses)
            ListTile(
              leading: Icon(
                status.availability == RealtimeFeedAvailability.live
                    ? Icons.check_circle_outline
                    : status.availability ==
                          RealtimeFeedAvailability.unavailable
                    ? Icons.error_outline
                    : Icons.info_outline,
              ),
              title: Text(_sourceLabel(status.category)),
              subtitle: Text(_feedStatusText(status)),
            ),
        ],
      ),
    );
  }
}

String _sourceLabel(String category) => switch (category) {
  'rapid-bus-kl' => 'Rapid Bus KL',
  'rapid-bus-mrtfeeder' => 'MRT feeder buses',
  _ => category,
};

String _feedStatusText(
  RealtimeFeedStatus status,
) => switch (status.availability) {
  RealtimeFeedAvailability.live =>
    '${status.vehicleCount ?? 0} live vehicle(s) • latest ${status.latestUpdate == null ? 'timestamp unavailable' : _formatDataAge(status.latestUpdate!)}',
  RealtimeFeedAvailability.noVehicleData =>
    'Feed responded but returned no usable vehicle positions. Realtime analytics are unavailable.',
  RealtimeFeedAvailability.stale =>
    '${status.vehicleCount ?? 0} vehicle position(s), but the latest timestamp is stale.',
  RealtimeFeedAvailability.unavailable =>
    'Could not read this feed${status.error == null ? '' : ': ${status.error}'}',
};

class _CompactCardGrid extends StatelessWidget {
  const _CompactCardGrid({required this.children, this.wideColumns = 3});

  final List<Widget> children;
  final int wideColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? wideColumns : 2;
        const spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 100),
                  child: child,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteActivityCard extends StatelessWidget {
  const _RouteActivityCard({required this.routes, required this.busRoutes});

  final Map<String, int> routes;
  final Map<String, BusRouteInfo> busRoutes;

  @override
  Widget build(BuildContext context) {
    final maximum = routes.values.fold<int>(1, math.max);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final route in routes.entries.take(8)) ...[
              Builder(
                builder: (context) {
                  final info = busRoutes[route.key];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              info == null
                                  ? route.key
                                  : '${info.displayName} (${route.key})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text('${route.value} vehicles'),
                        ],
                      ),
                      if (info != null)
                        Text(
                          info.longName,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: route.value / maximum,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}


class AnalyticsHistoryView extends StatefulWidget {
  const AnalyticsHistoryView({
    required this.report,
    required this.summaries,
    required this.alerts,
    required this.isLoading,
    required this.error,
    required this.alertsError,
    required this.onRetry,
    this.updatedAt,
    this.now,
    this.saveReport,
    this.routeScope = _allNetworkScope,
    this.followedRoutes = const {},
    this.activeRoutes = const {},
    this.routineRoutes = const {},
    this.busRoutes = const {},
    super.key,
  });
  final bool report;
  final List<DailyAnalyticsSummary> summaries;
  final List<AnalyticsAlert> alerts;
  final bool isLoading;
  final Object? error;
  final Object? alertsError;
  final Future<void> Function() onRetry;
  final DateTime? updatedAt;
  final DateTime? now;
  final Future<String?> Function(String name, Uint8List bytes)? saveReport;
  final String routeScope;
  final Set<String> followedRoutes;
  final Set<String> activeRoutes;
  final Set<String> routineRoutes;
  final Map<String, BusRouteInfo> busRoutes;
  @override
  State<AnalyticsHistoryView> createState() => _AnalyticsHistoryViewState();
}

class _AnalyticsHistoryViewState extends State<AnalyticsHistoryView> {
  int _weekOffset = 0;
  int? _selectedDay;
  TransitNotificationType? _trendType;
  bool _isExporting = false;

  Future<void> _downloadReport(
    DateTime start,
    DateTime now,
    String summary,
    List<AnalyticsAlert> alerts,
    List<DailyAnalyticsSummary> days,
  ) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final name = 'NextRoute-weekly-${WeeklyReportExport.date(start)}';
      final bytes = Uint8List.fromList(
        utf8.encode(
          WeeklyReportExport.csv(
            start: start,
            now: now,
            summary: summary,
            alerts: alerts,
            days: days,
          ),
        ),
      );
      final save = widget.saveReport;

      final saveDirectlyToDownloads =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux);
      final result = save != null
          ? await save(name, bytes)
          : saveDirectlyToDownloads
          ? await FileSaver.instance.saveFile(
              name: name,
              bytes: bytes,
              fileExtension: 'csv',
              mimeType: MimeType.custom,
              customMimeType: 'text/csv',
            )
          : await FileSaver.instance.saveAs(
              name: name,
              bytes: bytes,
              fileExtension: 'csv',
              mimeType: MimeType.custom,
              customMimeType: 'text/csv',
            );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == null || result.isEmpty
                ? 'Export cancelled; no report saved.'
                : kIsWeb
                ? 'Download requested. Check your browser downloads.'
                : saveDirectlyToDownloads
                ? 'Report downloaded: $result'
                : 'Report saved: $result',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save report. Try again or use Copy weekly report.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading &&
        widget.updatedAt == null &&
        widget.summaries.isEmpty &&
        widget.alerts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final now = widget.now ?? DateTime.now();
    final today = AnalyticsPeriod.day(now);
    final start = widget.report
        ? AnalyticsPeriod.monday(
            today,
          ).subtract(Duration(days: _weekOffset * 7))
        : today.subtract(const Duration(days: 6));
    final end = start.add(const Duration(days: 7));
    final all = AnalyticsPeriod.deduplicate(widget.alerts);
    final periodAlerts = AnalyticsPeriod.alertsIn(all, start, end);
    final alerts = periodAlerts
        .where(
          (alert) => _routeIncluded(
            alert.routeId,
            widget.routeScope,
            widget.followedRoutes,
            widget.busRoutes,
            activeRoutes: widget.activeRoutes,
            routineRoutes: widget.routineRoutes,
          ),
        )
        .toList();
    final health = AnalyticsPeriod.alertsIn(all, start, end, dataHealth: true);
    final days = AnalyticsPeriod.summariesIn(widget.summaries, start, end);
    final available = widget.alertsError == null;
    final trendAlerts = _trendType == null
        ? alerts
        : alerts.where((alert) => alert.type == _trendType).toList();
    final counts = List.generate(
      7,
      (i) => AnalyticsPeriod.alertsIn(
        trendAlerts,
        start.add(Duration(days: i)),
        start.add(Duration(days: i + 1)),
      ).length,
    );
    final partial = widget.report && _weekOffset == 0;
    final emptySelectedScope = switch (widget.routeScope) {
      _activeJourneyScope => widget.activeRoutes.isEmpty,
      _routineRoutesScope => widget.routineRoutes.isEmpty,
      _myRoutesScope => widget.followedRoutes.isEmpty,
      _ => false,
    };
    final scopeLabel = _scopeLabel(
      widget.routeScope,
      widget.followedRoutes,
      activeRoutes: widget.activeRoutes,
      routineRoutes: widget.routineRoutes,
    );
    final summary = !available
        ? 'Alert history could not be refreshed. No event totals or conclusions are shown.'
        : emptySelectedScope
        ? widget.routeScope == _myRoutesScope
              ? 'Choose at least one route using Manage, or select All network to see network-wide analytics.'
              : 'No routes are available for this personal scope. Choose My Routes or select All network.'
        : alerts.isEmpty
        ? 'No published travel alerts were found for $scopeLabel. '
              'This does not prove that no disruptions occurred.'
        : '${alerts.length} published travel alert(s) for $scopeLabel mention '
              '${alerts.map((a) => a.routeId).whereType<String>().toSet().length} identified route(s). '
              '${health.length} collector-health notice(s) are tracked separately, not counted as travel disruptions.';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: RefreshIndicator(
          onRefresh: widget.onRetry,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.report
                          ? 'Weekly service report'
                          : 'Explore service alerts',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.isLoading ? null : widget.onRetry,
                    tooltip: 'Refresh cloud history',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Text(
                widget.report
                    ? 'A Monday–Sunday summary of published alerts and collection quality.'
                    : 'See when and where travel alerts were published over the last seven days.',
              ),
              const SizedBox(height: 12),
              if (widget.report && !emptySelectedScope)
                DropdownButtonFormField<int>(
                  initialValue: _weekOffset,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reporting week • Malaysia time',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(8, (i) {
                    final monday = AnalyticsPeriod.monday(
                      today,
                    ).subtract(Duration(days: i * 7));
                    return DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${_formatShortDate(monday)} – ${_formatDate(monday.add(const Duration(days: 6)))}'
                        '${i == 0 ? ' • In progress' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                  onChanged: (value) => setState(() {
                    _weekOffset = value ?? 0;
                    _selectedDay = null;
                  }),
                ),
              if (!widget.report && !emptySelectedScope)
                DropdownButtonFormField<TransitNotificationType?>(
                  initialValue: _trendType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Trend metric',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('All travel alerts'),
                    ),
                    DropdownMenuItem(
                      value: TransitNotificationType.delay,
                      child: Text('Delay alerts'),
                    ),
                    DropdownMenuItem(
                      value: TransitNotificationType.crowd,
                      child: Text('Possible slow movement'),
                    ),
                    DropdownMenuItem(
                      value: TransitNotificationType.service,
                      child: Text('Service notices'),
                    ),
                  ],
                  onChanged: available
                      ? (value) => setState(() {
                          _trendType = value;
                          _selectedDay = null;
                        })
                      : null,
                ),
              const SizedBox(height: 12),
              if (widget.isLoading) const LinearProgressIndicator(),
              if (widget.alertsError != null || widget.error != null)
                _InformationCard(
                  icon: Icons.warning_amber,
                  title: 'Cloud history needs attention',
                  message:
                      '${widget.alertsError != null ? 'Alert archive unavailable. Apply the Module 5 analytics migration if it has not been deployed. ' : ''}'
                      '${widget.error != null ? 'Collection history could not be refreshed. ' : ''}'
                      'Check the connection and database permissions, then refresh. '
                      '${widget.updatedAt == null ? '' : 'Last complete refresh: ${_formatDataAge(widget.updatedAt!)}.'}',
                ),
              _InformationCard(
                icon: emptySelectedScope
                    ? Icons.route_outlined
                    : widget.report
                    ? Icons.summarize_outlined
                    : Icons.insights,
                title: emptySelectedScope
                    ? 'No routes selected'
                    : widget.report
                    ? (partial
                          ? 'Week in progress — not a final report'
                          : 'Week at a glance')
                    : '${_formatShortDate(start)} – ${_formatShortDate(end.subtract(const Duration(days: 1)))}',
                message: summary,
              ),
              const SizedBox(height: 12),
              if (available && !emptySelectedScope) ...[
                if (widget.report) ...[
                  _CompactCardGrid(
                    children: [
                      _SummaryCard(
                        label: 'Delay alerts',
                        value:
                            '${alerts.where((a) => a.type == TransitNotificationType.delay).length}',
                        color: const Color(0xFF2962FF),
                      ),
                      _SummaryCard(
                        label: 'Average known delay',
                        value: _averageDelayLabel(alerts),
                        color: const Color(0xFF7C3AED),
                      ),
                      _SummaryCard(
                        label: 'Possible slow movement',
                        value:
                            '${alerts.where((a) => a.type == TransitNotificationType.crowd).length}',
                        color: const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _section(
                    'ALERTS BY CATEGORY',
                    Column(
                      children: [
                        for (final type in TransitNotificationType.values)
                          _CategoryBar(
                            label: _typeLabel(type),
                            count: alerts.where((a) => a.type == type).length,
                            maximum: math.max(1, alerts.length),
                            color: _typeColor(type),
                          ),
                        const Text(
                          'Bar length: published alert count, not delay minutes or passenger counts.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  _InformationCard(
                    icon: Icons.compare_arrows,
                    title: 'Comparison with the previous week',
                    message: partial
                        ? 'This week is still in progress. A full-week increase/decrease would be misleading.'
                        : '${alerts.length} published alerts this week; '
                              '${AnalyticsPeriod.alertsIn(all, start.subtract(const Duration(days: 7)), start).where((alert) => _routeIncluded(alert.routeId, widget.routeScope, widget.followedRoutes, widget.busRoutes, activeRoutes: widget.activeRoutes, routineRoutes: widget.routineRoutes)).length} '
                              'in the previous week. These are archive counts, not actual service reliability.',
                  ),
                  const SizedBox(height: 12),
                  _section('ROUTES MENTIONED', _routeSummary(alerts)),
                ] else
                  _section(
                    'DAILY ${_trendType == null ? 'TRAVEL ALERTS' : _typeLabel(_trendType!).toUpperCase()}',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Y-axis: alert count • X-axis: day and date (Malaysia time)',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        _AlertTrendChart(
                          start: start,
                          counts: counts,
                          alerts: trendAlerts,
                          onSelected: (index) =>
                              setState(() => _selectedDay = index),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          trendAlerts.isEmpty
                              ? 'No published alerts. Zero records does not mean zero disruptions.'
                              : 'Hover for daily values. Tap a day to inspect its alerts.',
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                _section(
                  widget.report
                      ? 'IMPORTANT ALERTS • NEWEST FIRST'
                      : _selectedDay == null
                      ? 'RECENT ALERTS • TAP A DAY TO FILTER'
                      : 'ALERTS ON ${_formatShortDate(start.add(Duration(days: _selectedDay!))).toUpperCase()}',
                  _alertList(
                    widget.report || _selectedDay == null
                        ? alerts
                        : AnalyticsPeriod.alertsIn(
                            trendAlerts,
                            start.add(Duration(days: _selectedDay!)),
                            start.add(Duration(days: _selectedDay! + 1)),
                          ),
                  ),
                ),
              ],
              if (!emptySelectedScope) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.data_usage_outlined),
                  title: const Text('Data source & quality details'),
                  subtitle: Text(
                    '${health.length} collector-health notice(s) in this period',
                  ),
                  children: [
                    _qualityCard(days, start, end, now, widget.error != null),
                  ],
                ),
                const SizedBox(height: 12),
                const _InformationCard(
                  icon: Icons.info_outline,
                  title: 'What these analytics can — and cannot — tell you',
                  message:
                      'Counts refer to public alerts in the shared archive, including expired alerts; '
                      'withdrawn alerts are excluded. An event may have multiple manually published updates. '
                      'These are not unique incident counts. Bus road congestion is not station crowding. '
                      'Delay minutes are never inferred from vehicle counts or missing data. '
                      'A labelled NextRoute delay estimate appears only when a fresh near-stop GPS position '
                      'can be matched safely to the published timetable. Possible slow movement requires at least three '
                      'qualifying low-speed GPS intervals over six minutes; bus-stop dwell and GPS jitter are excluded. '
                      'It is a NextRoute estimate, not an operator-confirmed incident.',
                ),
                if (widget.report) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed:
                          available && widget.error == null && !_isExporting
                          ? () => _downloadReport(
                              start,
                              now,
                              summary,
                              alerts,
                              days,
                            )
                          : null,
                      icon: const Icon(Icons.download),
                      label: Text(
                        _isExporting ? 'Saving report…' : 'Download weekly CSV',
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: available && widget.error == null
                          ? () async {
                              try {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: _reportText(
                                      start,
                                      end,
                                      summary,
                                      alerts,
                                      days,
                                      partial,
                                    ),
                                  ),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Report copied. Paste into a document to save or share.',
                                      ),
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not copy the report on this device.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            }
                          : null,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy weekly report'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeSummary(List<AnalyticsAlert> alerts) {
    final counts = <String, int>{};
    for (final alert in alerts) {
      counts.update(
        alert.routeId ?? 'Route not specified',
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.isEmpty
        ? const Text('No routes can be identified without alert records.')
        : Column(
            children: [
              for (final entry in sorted.take(5))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.route),
                  title: Text(entry.key),
                  trailing: Text('${entry.value} alert(s)'),
                ),
              if (sorted.length > 5)
                Text('Top 5 of ${sorted.length} route groups.'),
            ],
          );
  }

  Widget _alertList(List<AnalyticsAlert> alerts) {
    if (alerts.isEmpty) {
      return const Text('No published travel alerts for this selection.');
    }
    final sorted = alerts.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      children: [
        for (final alert in sorted.take(30))
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: Icon(
              Icons.notifications_outlined,
              color: _typeColor(alert.type),
            ),
            title: Text(alert.title),
            subtitle: Text(
              '${_formatShortDate(AnalyticsPeriod.day(alert.createdAt))} • '
              '${_typeLabel(alert.type)} • ${alert.routeId ?? 'Route not specified'}',
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SelectableText(
                    [
                      if (_alertAuditText(alert).isNotEmpty)
                        _alertAuditText(alert),
                      alert.message,
                    ].join('\n\n'),
                  ),
                ),
              ),
            ],
          ),
        if (alerts.length > 30)
          Text(
            'Showing the latest 30 of ${alerts.length} alerts. Totals include all records.',
          ),
      ],
    );
  }
}

String _alertAuditText(AnalyticsAlert alert) {
  final lines = <String>[];
  if (alert.isEstimatedCongestion) {
    if (alert.observedSpeedKmh != null) {
      lines.add(
        'Observed average speed: ${alert.observedSpeedKmh!.toStringAsFixed(1)} km/h',
      );
    }
    if (alert.observationDurationMinutes != null) {
      lines.add('Observation window: ${alert.observationDurationMinutes} min');
    }
    if (alert.vehicleLabel != null) {
      lines.add('Vehicle ID: ${alert.vehicleLabel}');
    }
    lines.add(
      'NextRoute estimate from consecutive GPS intervals; not operator-confirmed congestion.',
    );
    return lines.join('\n');
  }
  if (alert.type != TransitNotificationType.delay) return '';
  if (alert.delayMinutes != null) {
    lines.add(
      '${alert.isEstimatedDelay ? 'Estimated' : 'Reported'} delay: ${alert.delayMinutes} min',
    );
  }
  if (alert.scheduledArrival != null) {
    lines.add(
      'Scheduled arrival: ${_formatMalaysiaInstant(alert.scheduledArrival!)}',
    );
  }
  if (alert.estimatedArrival != null) {
    lines.add(
      'Estimated arrival: ${_formatMalaysiaInstant(alert.estimatedArrival!)}',
    );
  }
  if (alert.vehicleLabel != null) {
    lines.add('Vehicle ID: ${alert.vehicleLabel}');
  }
  if (alert.fromStop != null) lines.add('Observed at: ${alert.fromStop}');
  if (alert.toStop != null) lines.add('Towards: ${alert.toStop}');
  if (alert.isEstimatedDelay) {
    lines.add(
      'NextRoute near-stop GPS/timetable estimate; not an operator Trip Update.',
    );
  }
  return lines.join('\n');
}

String _formatMalaysiaInstant(DateTime instant) {
  final local = instant.toUtc().add(const Duration(hours: 8));
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${_formatShortDate(AnalyticsPeriod.day(instant))}, '
      '$hour:$minute $period MYT';
}

Widget _section(String title, Widget child) => Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF52627D),
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  ),
);

Widget _qualityCard(
  List<DailyAnalyticsSummary> days,
  DateTime start,
  DateTime end,
  DateTime now,
  bool failed,
) {
  if (failed) {
    return const _InformationCard(
      icon: Icons.cloud_off,
      title: 'Collection quality unavailable',
      message: 'Refresh before using collection statistics.',
    );
  }
  final checks = days.fold(0, (sum, day) => sum + day.sampleCount);
  final successful = days.fold(
    0,
    (sum, day) => sum + day.successfulSampleCount,
  );
  final expected = AnalyticsPeriod.expectedChecks(start, end, now);
  final known = days.fold(0, (sum, day) => sum + day.qualitySampleCount);
  final empty = days.fold(0, (sum, day) => sum + day.emptySampleCount);
  final stale = days.fold(0, (sum, day) => sum + day.staleSampleCount);
  final unknown = days.fold(
    0,
    (sum, day) => sum + day.unknownFreshnessSampleCount,
  );
  final suspicious = days
      .where(
        (day) => day.successfulSampleCount > 0 && day.averageVehicleCount < 1,
      )
      .toList();
  final hasCongestion = days.any((day) => day.averageCongestionRate != null);
  return _section(
    'DATA COVERAGE • NOT SERVICE PERFORMANCE',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$checks saved / $expected expected half-hour checks • '
          '${days.where((d) => d.sampleCount > 0).length} day(s) with records.',
        ),
        Text(
          checks == 0
              ? 'Request success: N/A — no checks recorded.'
              : 'Request success: ${(successful * 100 / checks).toStringAsFixed(1)}% of saved checks. '
                    'A successful request does not guarantee usable data.',
        ),
        if (checks < expected)
          Text(
            '${expected - checks} scheduled check(s) have no saved record. '
            'This may include time before collection began.',
          ),
        const SizedBox(height: 8),
        Text(
          hasCongestion
              ? 'Congestion measurements exist only for observations with a reported status.'
              : 'Congestion: N/A — no verified congestion coverage in this period.',
        ),
        Text(
          '$known of $checks checks include the new quality fields. '
          'Legacy records cannot establish that congestion was zero.',
        ),
        if (known > 0)
          Text(
            'Quality flags: $empty empty, $stale with stale vehicles, '
            '$unknown with unknown/invalid timestamps. Flags may overlap.',
          ),
        if (suspicious.isNotEmpty)
          Text(
            'Sparse feed warning: ${suspicious.map((d) => _formatShortDate(d.serviceDate)).join(', ')} '
            'averaged fewer than one observed bus per successful check. '
            'Do not interpret this as normal traffic or an actual service reduction.',
            style: const TextStyle(color: Color(0xFFB45309)),
          ),
        const SizedBox(height: 6),
        const Text(
          'Collection runs in the cloud. Closing the app does not stop the scheduled collector.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}

String _reportText(
  DateTime start,
  DateTime end,
  String summary,
  List<AnalyticsAlert> alerts,
  List<DailyAnalyticsSummary> days,
  bool partial,
) {
  final checks = days.fold(0, (sum, d) => sum + d.sampleCount);
  return [
    'NextRoute • Weekly service report',
    '${_formatDate(start)} – ${_formatDate(end.subtract(const Duration(days: 1)))} (Malaysia time)',
    if (partial) 'This week so far — incomplete week',
    summary,
    for (final type in TransitNotificationType.values)
      '${_typeLabel(type)}: ${alerts.where((a) => a.type == type).length} published alert(s)',
    'Collection: $checks saved checks across ${days.length} days.',
    'Unknown congestion is not zero. Archive counts are not unique incidents or service reliability.',
    ...alerts.map(
      (a) =>
          '${_formatShortDate(AnalyticsPeriod.day(a.createdAt))} | '
          '${a.routeId ?? 'Unspecified route'} | ${a.title}'
          '${_alertAuditText(a).isEmpty ? '' : '\n${_alertAuditText(a)}'}\n${a.message}',
    ),
  ].join('\n\n');
}

String _typeLabel(TransitNotificationType type) => switch (type) {
  TransitNotificationType.service => 'Service',
  TransitNotificationType.delay => 'Delay',
  TransitNotificationType.crowd => 'Congestion',
};
Color _typeColor(TransitNotificationType type) => switch (type) {
  TransitNotificationType.service => const Color(0xFF2962FF),
  TransitNotificationType.delay => const Color(0xFF7C3AED),
  TransitNotificationType.crowd => const Color(0xFFF59E0B),
};

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.label,
    required this.count,
    required this.maximum,
    required this.color,
  });
  final String label;
  final int count;
  final int maximum;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('$count'),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: count / maximum,
          color: color,
          minHeight: 10,
          borderRadius: BorderRadius.circular(8),
        ),
      ],
    ),
  );
}

class _AlertTrendChart extends StatelessWidget {
  const _AlertTrendChart({
    required this.start,
    required this.counts,
    required this.alerts,
    required this.onSelected,
  });
  final DateTime start;
  final List<int> counts;
  final List<AnalyticsAlert> alerts;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final maximum = math.max(2, ((counts.fold(0, math.max) + 1) ~/ 2) * 2);
    return Column(
      children: [
        SizedBox(
          height: 190,
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$maximum'),
                    Text('${maximum ~/ 2}'),
                    const Text('0'),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _AlertPainter(counts, maximum),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final date = start.add(Duration(days: i));
                                final daily = AnalyticsPeriod.alertsIn(
                                  alerts,
                                  date,
                                  date.add(const Duration(days: 1)),
                                );
                                final detail =
                                    '${_formatDate(date)}\n${counts[i]} published travel alert(s)\n'
                                    '${TransitNotificationType.values.map((type) => '${_typeLabel(type)}: ${daily.where((a) => a.type == type).length}').join(' • ')}';
                                return Tooltip(
                                  message: detail,
                                  child: Semantics(
                                    label: detail,
                                    button: true,
                                    child: InkWell(
                                      onTap: () => onSelected(i),
                                      child: const SizedBox(
                                        height: 190,
                                        width: double.infinity,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(
                    '${i + 1}\n${start.add(Duration(days: i)).day}/${start.add(Duration(days: i)).month}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertPainter extends CustomPainter {
  _AlertPainter(this.counts, this.maximum);
  final List<int> counts;
  final int maximum;
  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - 5;
    const top = 5.0;
    final grid = Paint()..color = const Color(0xFFE1E6F0);
    for (var i = 0; i <= 4; i++) {
      final y = top + (bottom - top) * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final pen = Paint()
      ..color = const Color(0xFF2962FF)
      ..strokeWidth = 2.5;
    Offset? previous;
    for (var i = 0; i < 7; i++) {
      final point = Offset(
        size.width * (i + .5) / 7,
        bottom - (bottom - top) * counts[i] / maximum,
      );
      if (previous != null) canvas.drawLine(previous, point, pen);
      canvas.drawCircle(point, 4, pen);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(covariant _AlertPainter old) =>
      old.counts != counts || old.maximum != maximum;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor = const Color(0xFF2962FF),
  });
  final IconData icon;
  final String title;
  final String message;
  final Color iconColor;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text('$error', textAlign: TextAlign.center),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

String _formatDataAge(DateTime latestUpdate) {
  final age = DateTime.now().toUtc().difference(latestUpdate.toUtc());
  if (age.isNegative) return 'timestamp is in the future';
  if (age.inSeconds < 60) return '${age.inSeconds} seconds ago';
  if (age.inMinutes < 60) return '${age.inMinutes} minutes ago';
  return '${age.inHours} hours ago';
}

String _formatShortDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}';
}

String _formatDate(DateTime value) =>
    '${_formatShortDate(value)}, ${value.year}';

String _averageDelayLabel(Iterable<AnalyticsAlert> alerts) {
  final values = alerts
      .where((alert) => alert.type == TransitNotificationType.delay)
      .map((alert) => alert.delayMinutes)
      .whereType<int>()
      .toList();
  if (values.isEmpty) return 'N/A';
  final average = values.fold<int>(0, (a, b) => a + b) / values.length;
  return '${average.toStringAsFixed(1)} min';
}
