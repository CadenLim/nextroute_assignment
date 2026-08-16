import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_static_trip_matcher.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_realtime_service.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_static_service.dart';

class RealtimeStaticMatchDebugScreen extends StatefulWidget {
  const RealtimeStaticMatchDebugScreen({super.key});

  @override
  State<RealtimeStaticMatchDebugScreen> createState() =>
      _RealtimeStaticMatchDebugScreenState();
}

class _RealtimeStaticMatchDebugScreenState
    extends State<RealtimeStaticMatchDebugScreen> {
  final GtfsRealtimeService _realtimeService = GtfsRealtimeService();
  final GtfsStaticService _staticService = GtfsStaticService();
  final RealtimeStaticTripMatcher _matcher = const RealtimeStaticTripMatcher();

  RealtimeStaticTripMatchSummary? _summary;
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
      final summary = _matcher.match(
        realtimeFeed: feeds[0] as VehiclePositionFeed,
        staticFeed: feeds[1] as GtfsStaticFeed,
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
        title: const Text('Realtime ↔ Static Match Audit'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadAudit,
            tooltip: 'Refresh matching audit',
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
      return _AuditError(error: _error, onRetry: _loadAudit);
    }

    return _AuditContent(summary: summary);
  }
}

class _AuditContent extends StatelessWidget {
  const _AuditContent({required this.summary});

  final RealtimeStaticTripMatchSummary summary;

  @override
  Widget build(BuildContext context) {
    final matchedSamples = summary.matches.where(
      (match) =>
          match.status == RealtimeStaticTripMatchStatus.matchedWithStopTimes ||
          match.status == RealtimeStaticTripMatchStatus.matchedWithoutStopTimes,
    );
    final issueSamples = summary.matches.where(
      (match) =>
          match.status == RealtimeStaticTripMatchStatus.noTripId ||
          match.status == RealtimeStaticTripMatchStatus.noStaticTrip ||
          match.status == RealtimeStaticTripMatchStatus.routeMismatch,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'REALTIME ↔ STATIC MATCH AUDIT',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text('Rapid Bus KL'),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This screen audits data matching only. It does not calculate '
              'delay.',
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
            _AuditMetric(
              label: 'Realtime Vehicles',
              value: '${summary.totalRealtimeVehicles}',
            ),
            _AuditMetric(
              label: 'Matched With Stop Times',
              value: '${summary.matchedWithStopTimesCount}',
            ),
            _AuditMetric(
              label: 'Matched Without Stop Times',
              value: '${summary.matchedWithoutStopTimesCount}',
            ),
            _AuditMetric(
              label: 'No Static Trip Match',
              value: '${summary.noStaticTripCount}',
            ),
            _AuditMetric(
              label: 'No Realtime Trip ID',
              value: '${summary.noTripIdCount}',
            ),
            _AuditMetric(
              label: 'Route Mismatch',
              value: '${summary.routeMismatchCount}',
            ),
            _AuditMetric(
              label: 'Exact Trip ID Match Rate',
              value: '${summary.exactMatchPercentage.toStringAsFixed(1)}%',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('MATCHED SAMPLE', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (matchedSamples.isEmpty)
          const _NoSamplesCard(message: 'No matched samples are available.')
        else
          for (final match in matchedSamples.take(5))
            _MatchCard(match: match, showStaticDetails: true),
        const SizedBox(height: 20),
        Text(
          'UNMATCHED / ISSUE SAMPLE',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (issueSamples.isEmpty)
          const _NoSamplesCard(
            message: 'No unmatched or issue samples are available.',
          )
        else
          for (final match in issueSamples.take(5))
            _MatchCard(match: match, showStaticDetails: false),
      ],
    );
  }
}

class _AuditMetric extends StatelessWidget {
  const _AuditMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
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

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.showStaticDetails});

  final RealtimeStaticTripMatch match;
  final bool showStaticDetails;

  @override
  Widget build(BuildContext context) {
    final vehicle = match.vehicle;
    final staticTrip = match.staticTrip;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Vehicle ID: ${vehicle.vehicleId ?? 'Not provided'}\n'
          'Realtime Trip ID: ${vehicle.tripId ?? 'Not provided'}\n'
          'Realtime Route ID: ${vehicle.routeId ?? 'Not provided'}\n'
          '${showStaticDetails ? 'Static Trip ID: ${staticTrip?.tripId ?? 'Not available'}\n' : ''}'
          '${showStaticDetails ? 'Static Route ID: ${staticTrip?.routeId ?? 'Not available'}\n' : ''}'
          '${showStaticDetails ? 'Stop Times: ${match.stopTimes.length}\n' : ''}'
          'Status: ${_statusLabel(match.status)}',
        ),
      ),
    );
  }

  static String _statusLabel(RealtimeStaticTripMatchStatus status) {
    return switch (status) {
      RealtimeStaticTripMatchStatus.noTripId => 'No realtime trip ID',
      RealtimeStaticTripMatchStatus.noStaticTrip => 'No static trip match',
      RealtimeStaticTripMatchStatus.routeMismatch => 'Route mismatch',
      RealtimeStaticTripMatchStatus.matchedWithoutStopTimes =>
        'Matched without stop times',
      RealtimeStaticTripMatchStatus.matchedWithStopTimes =>
        'Matched with stop times',
    };
  }
}

class _NoSamplesCard extends StatelessWidget {
  const _NoSamplesCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

class _AuditError extends StatelessWidget {
  const _AuditError({required this.error, required this.onRetry});

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
              'Unable to complete the matching audit',
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
