import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_realtime_service.dart';

class VehiclePositionDebugScreen extends StatefulWidget {
  const VehiclePositionDebugScreen({super.key});

  @override
  State<VehiclePositionDebugScreen> createState() =>
      _VehiclePositionDebugScreenState();
}

class _VehiclePositionDebugScreenState
    extends State<VehiclePositionDebugScreen> {
  static const int _sampleSize = 10;

  final GtfsRealtimeService _service = GtfsRealtimeService();
  late Future<VehiclePositionFeed> _feedFuture;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _feedFuture = _loadFeed();
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
      _feedFuture = _loadFeed();
    });

    try {
      await _feedFuture;
    } on Object {
      return;
    }
  }

  Future<VehiclePositionFeed> _loadFeed() async {
    try {
      return await _service.fetchVehiclePositions();
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
        title: const Text('Rapid Bus KL Realtime'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _refresh,
            tooltip: 'Refresh realtime feed',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<VehiclePositionFeed>(
        future: _feedFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingState();
          }

          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error, onRetry: _refresh);
          }

          final feed = snapshot.data;
          if (feed == null) {
            return _ErrorState(
              error: 'No feed result was returned.',
              onRetry: _refresh,
            );
          }

          if (feed.vehicles.isEmpty) {
            return _EmptyState(feed: feed, onRefresh: _refresh);
          }

          return _SuccessState(feed: feed, onRefresh: _refresh);
        },
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Downloading GTFS-Realtime vehicle positions...'),
        ],
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
              'Unable to load the realtime feed',
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.feed, required this.onRefresh});

  final VehiclePositionFeed feed;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_bus_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'No usable vehicle positions',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The feed returned ${feed.totalEntities} raw entities, but none '
              'contained both latitude and longitude.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessState extends StatelessWidget {
  const _SuccessState({required this.feed, required this.onRefresh});

  final VehiclePositionFeed feed;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final sample = feed.vehicles.take(
      _VehiclePositionDebugScreenState._sampleSize,
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live feed summary',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Total raw entities: ${feed.totalEntities}'),
                  Text(
                    'Usable vehicle-position records: '
                    '${feed.usableVehiclePositions}',
                  ),
                  Text(
                    'Showing up to '
                    '${_VehiclePositionDebugScreenState._sampleSize} records',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final indexedVehicle in sample.indexed)
            _VehicleCard(
              number: indexedVehicle.$1 + 1,
              vehicle: indexedVehicle.$2,
            ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.number, required this.vehicle});

  final int number;
  final RealtimeVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vehicle $number',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _DataRow(label: 'Vehicle ID', value: _value(vehicle.vehicleId)),
            _DataRow(label: 'Route ID', value: _value(vehicle.routeId)),
            _DataRow(label: 'Trip ID', value: _value(vehicle.tripId)),
            _DataRow(
              label: 'Latitude',
              value: vehicle.latitude.toStringAsFixed(6),
            ),
            _DataRow(
              label: 'Longitude',
              value: vehicle.longitude.toStringAsFixed(6),
            ),
            _DataRow(
              label: 'Timestamp',
              value: vehicle.timestamp?.toIso8601String() ?? 'Not provided',
            ),
          ],
        ),
      ),
    );
  }

  static String _value(String? value) => value ?? 'Not provided';
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text('$label:')),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
