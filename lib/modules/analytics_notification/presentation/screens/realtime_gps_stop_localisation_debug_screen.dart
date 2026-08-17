import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_gps_stop_localiser.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_static_trip_matcher.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_gps_stop_localisation_result.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_gps_stop_localisation_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_realtime_service.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_static_service.dart';

class RealtimeGpsStopLocalisationDebugScreen extends StatefulWidget {
  const RealtimeGpsStopLocalisationDebugScreen({super.key});

  @override
  State<RealtimeGpsStopLocalisationDebugScreen> createState() =>
      _RealtimeGpsStopLocalisationDebugScreenState();
}

class _RealtimeGpsStopLocalisationDebugScreenState
    extends State<RealtimeGpsStopLocalisationDebugScreen> {
  final GtfsRealtimeService _realtimeService = GtfsRealtimeService();
  final GtfsStaticService _staticService = GtfsStaticService();
  final RealtimeStaticTripMatcher _tripMatcher =
      const RealtimeStaticTripMatcher();
  final RealtimeGpsStopLocaliser _localiser = const RealtimeGpsStopLocaliser();

  RealtimeGpsStopLocalisationSummary? _summary;
  Object? _error;
  bool _isLoading = false;
  bool _requestActive = false;

  @override
  void initState() {
    super.initState();
    _loadAudit();
  }

  @override
  void dispose() {
    _realtimeService.close();
    _staticService.close();
    super.dispose();
  }

  Future<void> _loadAudit() async {
    if (_requestActive) {
      return;
    }
    _requestActive = true;
    setState(() {
      _isLoading = true;
      _summary = null;
      _error = null;
    });

    try {
      final feeds = await Future.wait<Object>([
        _realtimeService.fetchVehiclePositions(),
        _staticService.fetchStaticFeed(),
      ]);
      final staticFeed = feeds[1] as GtfsStaticFeed;
      final tripMatches = _tripMatcher.match(
        realtimeFeed: feeds[0] as VehiclePositionFeed,
        staticFeed: staticFeed,
      );
      final summary = _localiser.localise(
        tripMatchSummary: tripMatches,
        staticFeed: staticFeed,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = summary;
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
        title: const Text('GPS Stop Localisation Audit'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadAudit,
            tooltip: 'Refresh GPS stop localisation audit',
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

    final summary = _summary;
    if (summary == null) {
      return _LocalisationError(error: _error, onRetry: _loadAudit);
    }
    return _LocalisationContent(summary: summary);
  }
}

class _LocalisationContent extends StatelessWidget {
  const _LocalisationContent({required this.summary});

  final RealtimeGpsStopLocalisationSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'GPS STOP LOCALISATION AUDIT',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text('Rapid Bus KL'),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This screen estimates the nearest scheduled stop on a matched '
              'trip using realtime vehicle GPS. It does not calculate delay '
              'and does not claim the vehicle is confirmed to be at that stop.',
            ),
          ),
        ),
        const Text(
          'Data Sources:\n'
          'Malaysia Open Data / Prasarana\n'
          'GTFS Realtime Vehicle Position\n'
          'GTFS Static Schedule',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _LocalisationMetric(
              label: 'Eligible Matched Vehicles',
              value: '${summary.eligibleMatchedVehicles}',
            ),
            _LocalisationMetric(
              label: 'Nearest Scheduled Stop Found',
              value: '${summary.nearestScheduledStopFoundCount}',
            ),
            _LocalisationMetric(
              label: 'No Candidate Stops',
              value: '${summary.noCandidateStopsCount}',
            ),
            _LocalisationMetric(
              label: 'Localisation Coverage',
              value:
                  '${summary.localisationCoveragePercentage.toStringAsFixed(1)}%',
            ),
            _LocalisationMetric(
              label: '0–100 m',
              value: '${summary.within100mCount}',
            ),
            _LocalisationMetric(
              label: '>100–250 m',
              value: '${summary.over100To250mCount}',
            ),
            _LocalisationMetric(
              label: '>250–500 m',
              value: '${summary.over250To500mCount}',
            ),
            _LocalisationMetric(
              label: '>500 m',
              value: '${summary.over500mCount}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Distance bands are descriptive NextRoute audit ranges only; they '
          'are not official Rapid KL thresholds.',
        ),
        const SizedBox(height: 20),
        Text('SAMPLE VEHICLES', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (summary.results.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No exact trip matches with static stop times are eligible '
                'for this audit.',
              ),
            ),
          )
        else
          for (final result in summary.results.take(5))
            _LocalisationResultCard(result: result),
      ],
    );
  }
}

class _LocalisationMetric extends StatelessWidget {
  const _LocalisationMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalisationResultCard extends StatelessWidget {
  const _LocalisationResultCard({required this.result});

  final RealtimeGpsStopLocalisationResult result;

  @override
  Widget build(BuildContext context) {
    final vehicle = result.tripMatch.vehicle;
    final stop = result.nearestStop;
    final stopTime = result.nearestStopTime;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Vehicle ID: ${vehicle.vehicleId ?? 'Not provided'}\n'
          'Trip ID: ${vehicle.tripId ?? 'Not provided'}\n'
          'Route ID: ${vehicle.routeId ?? 'Not provided'}\n'
          'Vehicle Latitude: ${vehicle.latitude.toStringAsFixed(6)}\n'
          'Vehicle Longitude: ${vehicle.longitude.toStringAsFixed(6)}\n'
          'Nearest Scheduled Stop ID: ${stop?.stopId ?? 'Not found'}\n'
          'Stop Name: ${stop?.stopName ?? 'Not provided'}\n'
          'Stop Sequence: ${stopTime?.stopSequence.toString() ?? 'Not found'}\n'
          'Scheduled Arrival: ${stopTime?.arrivalTime ?? 'Not found'}\n'
          'Scheduled Departure: ${stopTime?.departureTime ?? 'Not found'}\n'
          'Distance to Stop: ${_distanceLabel(result.distanceMeters)}\n'
          'Localisation Status: ${_statusLabel(result.status)}',
        ),
      ),
    );
  }

  static String _distanceLabel(double? distanceMeters) {
    return distanceMeters == null
        ? 'Not available'
        : '${distanceMeters.toStringAsFixed(1)} m';
  }

  static String _statusLabel(RealtimeGpsStopLocalisationStatus status) {
    return switch (status) {
      RealtimeGpsStopLocalisationStatus.noCandidateStops =>
        'No candidate stops',
      RealtimeGpsStopLocalisationStatus.nearestScheduledStopFound =>
        'GPS-estimated nearest scheduled stop found',
    };
  }
}

class _LocalisationError extends StatelessWidget {
  const _LocalisationError({required this.error, required this.onRetry});

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
              'Unable to complete the GPS stop localisation audit',
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
