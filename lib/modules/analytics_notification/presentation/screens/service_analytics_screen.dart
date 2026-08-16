import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/service_analytics_calculator.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/service_analytics.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_realtime_service.dart';

class ServiceAnalyticsScreen extends StatefulWidget {
  const ServiceAnalyticsScreen({super.key});

  @override
  State<ServiceAnalyticsScreen> createState() => _ServiceAnalyticsScreenState();
}

class _ServiceAnalyticsScreenState extends State<ServiceAnalyticsScreen> {
  final GtfsRealtimeService _service = GtfsRealtimeService();
  final ServiceAnalyticsCalculator _calculator =
      const ServiceAnalyticsCalculator();

  late Future<ServiceAnalytics> _analyticsFuture;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _analyticsFuture = _loadAnalytics();
  }

  @override
  void dispose() {
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

    try {
      await _analyticsFuture;
    } on Object {
      return;
    }
  }

  Future<ServiceAnalytics> _loadAnalytics() async {
    try {
      final feed = await _service.fetchVehiclePositions();
      return _calculator.calculate(feed);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: FutureBuilder<ServiceAnalytics>(
        future: _analyticsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error, onRetry: _refresh);
          }

          final analytics = snapshot.data;
          if (analytics == null) {
            return _ErrorState(
              error: 'No analytics result was returned.',
              onRetry: _refresh,
            );
          }

          return _AnalyticsContent(analytics: analytics, onRefresh: _refresh);
        },
      ),
    );
  }
}

class _AnalyticsContent extends StatelessWidget {
  const _AnalyticsContent({required this.analytics, required this.onRefresh});

  final ServiceAnalytics analytics;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'SERVICE ANALYTICS',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _MetricCard(
            label: 'Vehicles in Latest Feed',
            value: '${analytics.vehicleCount}',
          ),
          _MetricCard(
            label: 'Routes Represented',
            value: '${analytics.routeCount}',
          ),
          _MetricCard(
            label: 'Latest Vehicle Update',
            value: _formatDataAge(analytics.latestUpdate),
            detail:
                analytics.latestUpdate?.toUtc().toIso8601String() ??
                'Timestamp not provided',
          ),
          const SizedBox(height: 16),
          Text(
            'VEHICLES BY ROUTE',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (analytics.vehiclesByRoute.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No vehicle records included a route ID.'),
              ),
            )
          else
            for (final route in analytics.vehiclesByRoute.entries)
              Card(
                child: ListTile(
                  title: Text(route.key),
                  trailing: Text('${route.value}'),
                ),
              ),
        ],
      ),
    );
  }

  static String _formatDataAge(DateTime? latestUpdate) {
    if (latestUpdate == null) {
      return 'Not provided';
    }

    final age = DateTime.now().toUtc().difference(latestUpdate.toUtc());
    if (age.isNegative) {
      return '${_formatDuration(age.abs())} from now';
    }
    return '${_formatDuration(age)} ago';
  }

  static String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds} seconds';
    }
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} minutes';
    }
    if (duration.inHours < 24) {
      return '${duration.inHours} hours';
    }
    return '${duration.inDays} days';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            if (detail != null) ...[const SizedBox(height: 4), Text(detail!)],
          ],
        ),
      ),
    );
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
            const SizedBox(height: 16),
            Text(
              'Unable to load service analytics',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
