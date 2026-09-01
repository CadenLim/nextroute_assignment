import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:nextroute_assignment/services/analytics_service.dart';

const _autoRefreshInterval = Duration(seconds: 30);

class ServiceAnalyticsScreen extends StatefulWidget {
  const ServiceAnalyticsScreen({this.embedded = false, super.key});

  final bool embedded;

  @override
  State<ServiceAnalyticsScreen> createState() => _ServiceAnalyticsScreenState();
}

class _ServiceAnalyticsScreenState extends State<ServiceAnalyticsScreen> {
  final GtfsRealtimeService _service = GtfsRealtimeService();
  final ServiceAnalyticsCalculator _calculator =
      const ServiceAnalyticsCalculator();

  late final SupabaseAnalyticsRepository _history;
  late Future<ServiceAnalytics> _analyticsFuture;
  List<DailyAnalyticsSummary> _dailySummaries = const [];
  Map<String, BusRouteInfo> _busRoutes = const {};
  Object? _historyError;
  Timer? _refreshTimer;
  int _selectedTab = 0;
  bool _isLoading = true;
  bool _isHistoryLoading = true;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
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
    try {
      await _analyticsFuture;
    } on Object {
      // The Live Service tab displays the fetch error.
    }
  }

  Future<ServiceAnalytics> _loadAnalytics() async {
    try {
      final feed = await _service.fetchVehiclePositions();
      return _calculator.calculate(feed);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCloudHistory() async {
    if (mounted) {
      setState(() {
        _isHistoryLoading = true;
        _historyError = null;
      });
    }
    try {
      final summaries = await _history.loadLastSevenDays();
      if (mounted) {
        setState(() {
          _dailySummaries = summaries;
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
    }
  }

  Future<void> _loadBusRoutes() async {
    try {
      final routes = await BusRouteCatalog.load();
      if (mounted) setState(() => _busRoutes = routes);
    } on Object {
      // Raw route IDs remain available if the local catalogue cannot load.
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _AnalyticsTabs(
          selectedIndex: _selectedTab,
          onSelected: (index) => setState(() => _selectedTab = index),
        ),
        Expanded(child: _buildSelectedTab()),
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

  Widget _buildSelectedTab() {
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
                  isLoading: _isLoading,
                  onRefresh: _refresh,
                );
        },
      ),
      1 => _TrendDashboard(
        summaries: _dailySummaries,
        isLoading: _isHistoryLoading,
        error: _historyError,
        onRetry: _loadCloudHistory,
      ),
      _ => _WeeklyReportView(
        summaries: _dailySummaries,
        isLoading: _isHistoryLoading,
        error: _historyError,
        onRetry: _loadCloudHistory,
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

class _LiveServiceView extends StatelessWidget {
  const _LiveServiceView({
    required this.analytics,
    required this.busRoutes,
    required this.isLoading,
    required this.onRefresh,
  });

  final ServiceAnalytics analytics;
  final Map<String, BusRouteInfo> busRoutes;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final emptyFeed = analytics.vehicleCount == 0;
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
              const SizedBox(height: 12),
              _CompactCardGrid(
                wideColumns: 4,
                children: [
                  _MetricTile(
                    label: 'Live vehicles',
                    value: '${analytics.vehicleCount}',
                    color: const Color(0xFF2962FF),
                    icon: Icons.directions_bus,
                  ),
                  _MetricTile(
                    label: 'Active routes',
                    value: '${analytics.routeCount}',
                    color: const Color(0xFF7C3AED),
                    icon: Icons.route,
                  ),
                  _MetricTile(
                    label: 'Congested',
                    value: '${analytics.congestedVehicleCount}',
                    color: const Color(0xFFF59E0B),
                    icon: Icons.traffic,
                  ),
                  _MetricTile(
                    label: 'Severe',
                    value: '${analytics.severeCongestionCount}',
                    color: const Color(0xFFEF4444),
                    icon: Icons.warning_amber,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'ROUTE ACTIVITY',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF71809F),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              if (analytics.vehiclesByRoute.isEmpty)
                const _InformationCard(
                  icon: Icons.info_outline,
                  title: 'No live vehicles right now',
                  message:
                      'The provider returned a valid feed with no vehicle records. '
                      'Pull down or tap refresh to try again later.',
                )
              else
                _RouteActivityCard(
                  routes: analytics.vehiclesByRoute,
                  busRoutes: busRoutes,
                ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (emptyFeed ? Colors.orange : Colors.green).withValues(
                  alpha: 0.12,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                emptyFeed
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
                color: emptyFeed ? Colors.orange : Colors.green,
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
                        : 'Live feed online',
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
              SizedBox(width: itemWidth, height: 92, child: child),
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

class _TrendDashboard extends StatelessWidget {
  const _TrendDashboard({
    required this.summaries,
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final List<DailyAnalyticsSummary> summaries;
  final bool isLoading;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading && summaries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && summaries.isEmpty) {
      return _ErrorState(error: error, onRetry: onRetry);
    }
    final days = _sevenDaySummarySlots(summaries);
    final recorded = summaries.where((day) => day.sampleCount > 0).toList();
    final latest = recorded.isEmpty ? null : recorded.last;
    final previous = recorded.length < 2 ? null : recorded[recorded.length - 2];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
          children: [
            _InformationCard(
              icon: Icons.traffic,
              title: _trendTitle(latest, previous),
              message: _trendMessage(latest, previous, recorded.length),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '7-DAY CONGESTION TREND',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF52627D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Y-axis: average share of live buses reported as congested',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    _CongestionChart(days: days),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _CompactCardGrid(
              children: [
                _SummaryCard(
                  label: 'Days with collected data',
                  value: '${recorded.length}/7',
                  color: const Color(0xFF2962FF),
                ),
                _SummaryCard(
                  label: 'Latest congestion rate',
                  value: latest == null
                      ? '—'
                      : '${latest.averageCongestionRate.toStringAsFixed(1)}%',
                  color: const Color(0xFFF59E0B),
                ),
                _SummaryCard(
                  label: 'Latest feed availability',
                  value: latest == null
                      ? '—'
                      : '${latest.feedSuccessRate.toStringAsFixed(0)}%',
                  color: const Color(0xFF16A34A),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _trendTitle(
    DailyAnalyticsSummary? latest,
    DailyAnalyticsSummary? previous,
  ) {
    if (latest == null) return 'No cloud analytics collected yet';
    if (previous == null) return 'More history is needed to identify a trend';
    final difference =
        latest.averageCongestionRate - previous.averageCongestionRate;
    if (difference.abs() < 0.5) return 'Congestion remained broadly stable';
    return difference > 0
        ? 'Congestion increased on the latest recorded day'
        : 'Congestion decreased on the latest recorded day';
  }

  static String _trendMessage(
    DailyAnalyticsSummary? latest,
    DailyAnalyticsSummary? previous,
    int daysRecorded,
  ) {
    if (latest == null) {
      return 'The Supabase collector has not stored a successful day yet. '
          'This page will update for every user after cloud collection begins.';
    }
    if (previous == null) {
      return 'Only $daysRecorded of the last 7 days has data. The latest '
          'average congestion rate was '
          '${latest.averageCongestionRate.toStringAsFixed(1)}%. Missing days '
          'are not treated as zero.';
    }
    final difference =
        latest.averageCongestionRate - previous.averageCongestionRate;
    return 'The latest rate was '
        '${latest.averageCongestionRate.toStringAsFixed(1)}%, '
        '${difference.abs().toStringAsFixed(1)} percentage points '
        '${difference >= 0 ? 'higher' : 'lower'} than the previous recorded '
        'day. This measures reported bus congestion, not passenger ridership.';
  }
}

class _WeeklyReportView extends StatelessWidget {
  const _WeeklyReportView({
    required this.summaries,
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final List<DailyAnalyticsSummary> summaries;
  final bool isLoading;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading && summaries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && summaries.isEmpty) {
      return _ErrorState(error: error, onRetry: onRetry);
    }

    final days = _sevenDaySummarySlots(summaries);
    final recorded = summaries.where((day) => day.sampleCount > 0).toList();
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 6));
    final totalSamples = recorded.fold<int>(
      0,
      (sum, day) => sum + day.sampleCount,
    );
    final successfulSamples = recorded.fold<int>(
      0,
      (sum, day) => sum + day.successfulSampleCount,
    );
    final failedSamples = recorded.fold<int>(
      0,
      (sum, day) => sum + day.failedSampleCount,
    );
    final feedSuccessRate = totalSamples == 0
        ? 0.0
        : successfulSamples / totalSamples * 100;
    final averageCongestionRate = recorded.isEmpty
        ? 0.0
        : recorded.fold<double>(
                0,
                (sum, day) => sum + day.averageCongestionRate,
              ) /
              recorded.length;
    final peakDay = recorded.isEmpty
        ? null
        : recorded.reduce(
            (current, next) =>
                next.averageCongestionRate > current.averageCongestionRate
                ? next
                : current,
          );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
          children: [
            Card(
              color: const Color(0xFFEAF1FF),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WEEKLY SERVICE REPORT',
                      style: TextStyle(
                        color: Color(0xFF2962FF),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_formatDate(start)} — ${_formatDate(today)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$totalSamples scheduled cloud checks across '
                      '${recorded.length} of the last 7 days.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _InformationCard(
              icon: recorded.length < 4
                  ? Icons.hourglass_top
                  : feedSuccessRate >= 90
                  ? Icons.check_circle_outline
                  : Icons.warning_amber,
              title: recorded.length < 4
                  ? 'Partial report — more days are needed'
                  : 'Weekly congestion and feed summary',
              message: recorded.isEmpty
                  ? 'No cloud snapshots are available yet. The scheduled '
                        'collector must run before a real report can be created.'
                  : 'Average reported congestion was '
                        '${averageCongestionRate.toStringAsFixed(1)}%. '
                        '${peakDay == null ? '' : 'The highest daily rate was ${peakDay.averageCongestionRate.toStringAsFixed(1)}% on ${_formatShortDate(peakDay.serviceDate)}. '}'
                        'Feed availability was '
                        '${feedSuccessRate.toStringAsFixed(0)}%.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DAILY CONGESTION RATE',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF52627D),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _CongestionChart(days: days),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _CompactCardGrid(
              children: [
                _SummaryCard(
                  label: 'Feed availability',
                  value: '${feedSuccessRate.toStringAsFixed(0)}%',
                  color: const Color(0xFF16A34A),
                ),
                _SummaryCard(
                  label: 'Failed cloud checks',
                  value: '$failedSamples',
                  color: const Color(0xFFEF4444),
                ),
                _SummaryCard(
                  label: 'Average congestion rate',
                  value: '${averageCongestionRate.toStringAsFixed(1)}%',
                  color: const Color(0xFFF59E0B),
                ),
                _SummaryCard(
                  label: 'Highest severe vehicles in one check',
                  value: peakDay == null
                      ? '—'
                      : '${peakDay.peakSevereCongestionCount}',
                  color: const Color(0xFFD92D3A),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CongestionChart extends StatefulWidget {
  const _CongestionChart({required this.days});

  final List<DailyAnalyticsSummary?> days;

  @override
  State<_CongestionChart> createState() => _CongestionChartState();
}

class _CongestionChartState extends State<_CongestionChart> {
  static const _leftPadding = 38.0;
  static const _rightPadding = 10.0;
  int? _selectedIndex;

  void _selectNearest(Offset position, double width) {
    final chartWidth = math.max(1.0, width - _leftPadding - _rightPadding);
    final ratio = ((position.dx - _leftPadding) / chartWidth).clamp(0.0, 1.0);
    final index = (ratio * 6).round();
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final selected = _selectedIndex == null
                ? null
                : widget.days[_selectedIndex!];
            final chartWidth = math.max(
              1.0,
              constraints.maxWidth - _leftPadding - _rightPadding,
            );
            final pointX = _selectedIndex == null
                ? 0.0
                : _leftPadding + chartWidth * _selectedIndex! / 6;
            final tooltipLeft = (pointX - 80)
                .clamp(0.0, math.max(0.0, constraints.maxWidth - 160))
                .toDouble();

            return MouseRegion(
              onHover: (event) =>
                  _selectNearest(event.localPosition, constraints.maxWidth),
              onExit: (_) => setState(() => _selectedIndex = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    _selectNearest(details.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (details) =>
                    _selectNearest(details.localPosition, constraints.maxWidth),
                child: SizedBox(
                  height: 190,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TrendChartPainter(
                            widget.days,
                            highlightIndex: _selectedIndex,
                          ),
                        ),
                      ),
                      if (_selectedIndex != null)
                        Positioned(
                          left: tooltipLeft,
                          top: 6,
                          width: 160,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(10),
                            color: const Color(0xFF17233C),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selected == null
                                        ? 'Day ${_selectedIndex! + 1}'
                                        : _formatShortDate(
                                            selected.serviceDate,
                                          ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (selected == null)
                                    const Text(
                                      'No cloud data for this day',
                                      style: TextStyle(color: Colors.white70),
                                    )
                                  else ...[
                                    Text(
                                      '${selected.averageCongestionRate.toStringAsFixed(1)}% congested',
                                      style: const TextStyle(
                                        color: Color(0xFFFFC46B),
                                      ),
                                    ),
                                    Text(
                                      '${selected.averageCongestedVehicleCount.toStringAsFixed(1)} of '
                                      '${selected.averageVehicleCount.toStringAsFixed(1)} buses',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    Text(
                                      '${selected.feedSuccessRate.toStringAsFixed(0)}% feed availability',
                                      style: const TextStyle(
                                        color: Color(0xFFA7F3C0),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(
            left: _leftPadding,
            right: _rightPadding,
          ),
          child: Row(
            children: [
              for (var index = 0; index < 7; index++)
                Expanded(
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'X-axis: Day 1 to Day 7 • Hover or tap for the date and values',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF52627D)),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: _Legend(
            color: Color(0xFFF59E0B),
            label: 'Average congestion rate',
          ),
        ),
      ],
    );
  }
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
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF2962FF)),
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
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label),
      ],
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter(this.days, {this.highlightIndex});

  final List<DailyAnalyticsSummary?> days;
  final int? highlightIndex;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPadding = 38.0;
    const otherPadding = 10.0;
    final chart = Rect.fromLTWH(
      leftPadding,
      otherPadding,
      size.width - leftPadding - otherPadding,
      size.height - otherPadding * 2,
    );
    final gridPaint = Paint()
      ..color = const Color(0xFFE7ECF5)
      ..strokeWidth = 1;
    for (var line = 0; line <= 4; line++) {
      final y = chart.top + chart.height * line / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      if (line.isEven) {
        final labelValue = (100 * (4 - line) / 4).round();
        final label = TextPainter(
          text: TextSpan(
            text: '$labelValue%',
            style: const TextStyle(color: Color(0xFF71809F), fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: leftPadding - 6);
        label.paint(canvas, Offset(chart.left - label.width - 6, y - 6));
      }
    }

    final selected = highlightIndex;
    if (selected != null && selected >= 0 && selected < days.length) {
      final x = chart.left + chart.width * selected / 6;
      canvas.drawLine(
        Offset(x, chart.top),
        Offset(x, chart.bottom),
        Paint()
          ..color = const Color(0xFF52627D).withValues(alpha: 0.45)
          ..strokeWidth = 1.5,
      );
    }

    _drawSeries(
      canvas,
      chart,
      days
          .map((item) => item?.averageCongestionRate.clamp(0, 100).toDouble())
          .toList(),
      const Color(0xFFF59E0B),
    );
  }

  void _drawSeries(
    Canvas canvas,
    Rect chart,
    List<double?> values,
    Color color,
  ) {
    if (values.isEmpty) {
      return;
    }
    final pointPaint = Paint()..color = color;
    Offset? previous;
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      if (value == null) {
        previous = null;
        continue;
      }
      final x = values.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (values.length - 1);
      final y = chart.bottom - chart.height * value / 100;
      final point = Offset(x, y);
      if (previous != null) {
        canvas.drawLine(
          previous,
          point,
          Paint()
            ..color = color
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(point, 3.5, pointPaint);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    return oldDelegate.days != days ||
        oldDelegate.highlightIndex != highlightIndex;
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

String _formatDataAge(DateTime latestUpdate) {
  final age = DateTime.now().toUtc().difference(latestUpdate.toUtc());
  if (age.isNegative || age.inSeconds < 10) {
    return 'just now';
  }
  if (age.inSeconds < 60) {
    return '${age.inSeconds} seconds ago';
  }
  if (age.inMinutes < 60) {
    return '${age.inMinutes} minutes ago';
  }
  return '${age.inHours} hours ago';
}

List<DailyAnalyticsSummary?> _sevenDaySummarySlots(
  Iterable<DailyAnalyticsSummary> summaries,
) {
  final today = DateTime.now();
  final firstDay = DateTime(
    today.year,
    today.month,
    today.day,
  ).subtract(const Duration(days: 6));
  final byDay = <DateTime, DailyAnalyticsSummary>{};
  for (final summary in summaries) {
    final local = summary.serviceDate.toLocal();
    byDay[DateTime(local.year, local.month, local.day)] = summary;
  }
  return List.unmodifiable(
    List.generate(7, (index) => byDay[firstDay.add(Duration(days: index))]),
  );
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
  final local = value.toLocal();
  return '${months[local.month - 1]} ${local.day}';
}

String _formatDate(DateTime value) {
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
  final local = value.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
