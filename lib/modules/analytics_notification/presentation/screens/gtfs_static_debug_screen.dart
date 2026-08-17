import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_route.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_static_service.dart';

class GtfsStaticDebugScreen extends StatefulWidget {
  const GtfsStaticDebugScreen({super.key});

  @override
  State<GtfsStaticDebugScreen> createState() => _GtfsStaticDebugScreenState();
}

class _GtfsStaticDebugScreenState extends State<GtfsStaticDebugScreen> {
  final GtfsStaticService _service = GtfsStaticService();

  GtfsStaticFeed? _feed;
  Object? _error;
  bool _isLoading = false;
  bool _requestActive = false;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    if (_requestActive) {
      return;
    }
    _requestActive = true;
    setState(() {
      _isLoading = true;
      _feed = null;
      _error = null;
    });

    try {
      final feed = await _service.fetchStaticFeed();
      if (!mounted) {
        return;
      }
      setState(() {
        _feed = feed;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
    } finally {
      _requestActive = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GTFS Static Schedule'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadFeed,
            tooltip: 'Refresh static schedule',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final feed = _feed;
    if (feed == null) {
      return _StaticFeedError(error: _error, onRetry: _loadFeed);
    }

    return _StaticFeedContent(feed: feed);
  }
}

class _StaticFeedContent extends StatelessWidget {
  const _StaticFeedContent({required this.feed});

  final GtfsStaticFeed feed;

  @override
  Widget build(BuildContext context) {
    final stopTimesByTrip = <String, List<GtfsStopTime>>{};
    for (final stopTime in feed.stopTimes) {
      stopTimesByTrip.putIfAbsent(stopTime.tripId, () => []).add(stopTime);
    }

    final sampleTrip = feed.trips.firstWhere(
      (trip) => stopTimesByTrip[trip.tripId]?.isNotEmpty ?? false,
      orElse: () => feed.trips.first,
    );
    final sampleStopTimes =
        List<GtfsStopTime>.of(stopTimesByTrip[sampleTrip.tripId] ?? const [])
          ..sort(
            (first, second) =>
                first.stopSequence.compareTo(second.stopSequence),
          );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'GTFS STATIC — RAPID BUS KL',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        const Text('Data Source: Malaysia Open Data / Prasarana GTFS Static'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountCard(label: 'Routes', count: feed.routes.length),
            _CountCard(label: 'Trips', count: feed.trips.length),
            _CountCard(label: 'Stop Times', count: feed.stopTimes.length),
            _CountCard(label: 'Stops', count: feed.stops.length),
          ],
        ),
        const SizedBox(height: 20),
        Text('ROUTES', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final route in feed.routes.take(5)) _RouteCard(route: route),
        const SizedBox(height: 20),
        Text('SAMPLE TRIP', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _TripCard(trip: sampleTrip),
        const SizedBox(height: 20),
        Text(
          'SAMPLE STOP TIMES',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (sampleStopTimes.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No stop times are available for this sample trip.'),
            ),
          )
        else
          for (final stopTime in sampleStopTimes.take(5))
            _StopTimeCard(stopTime: stopTime),
      ],
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 4),
              Text('$count', style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route});

  final GtfsRoute route;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(route.routeShortName ?? 'Short name not provided'),
        subtitle: Text(
          'Route ID: ${route.routeId}\n'
          'Long name: ${route.routeLongName ?? 'Not provided'}\n'
          'Route type: ${route.routeType}',
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final GtfsTrip trip;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Trip ID: ${trip.tripId}\n'
          'Route ID: ${trip.routeId}\n'
          'Service ID: ${trip.serviceId}\n'
          'Headsign: ${trip.tripHeadsign ?? 'Not provided'}\n'
          'Direction: ${trip.directionId?.toString() ?? 'Not provided'}',
        ),
      ),
    );
  }
}

class _StopTimeCard extends StatelessWidget {
  const _StopTimeCard({required this.stopTime});

  final GtfsStopTime stopTime;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Trip ID: ${stopTime.tripId}\n'
          'Stop ID: ${stopTime.stopId}\n'
          'Arrival: ${stopTime.arrivalTime}\n'
          'Departure: ${stopTime.departureTime}\n'
          'Sequence: ${stopTime.stopSequence}',
        ),
      ),
    );
  }
}

class _StaticFeedError extends StatelessWidget {
  const _StaticFeedError({required this.error, required this.onRetry});

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
            Text(
              'Unable to load GTFS Static schedule',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
