import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_static_trip_matcher.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_stop_context_auditor.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_stop_context_result.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_stop_context_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_realtime_service.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_static_service.dart';

class RealtimeStopContextDebugScreen extends StatefulWidget {
  const RealtimeStopContextDebugScreen({super.key});

  @override
  State<RealtimeStopContextDebugScreen> createState() =>
      _RealtimeStopContextDebugScreenState();
}

class _RealtimeStopContextDebugScreenState
    extends State<RealtimeStopContextDebugScreen> {
  final GtfsRealtimeService _realtimeService = GtfsRealtimeService();
  final GtfsStaticService _staticService = GtfsStaticService();
  final RealtimeStaticTripMatcher _tripMatcher =
      const RealtimeStaticTripMatcher();
  final RealtimeStopContextAuditor _auditor =
      const RealtimeStopContextAuditor();

  RealtimeStopContextSummary? _summary;
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
      final tripMatches = _tripMatcher.match(
        realtimeFeed: feeds[0] as VehiclePositionFeed,
        staticFeed: feeds[1] as GtfsStaticFeed,
      );
      final summary = _auditor.audit(tripMatches);
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
        title: const Text('Realtime Stop Context Audit'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadAudit,
            tooltip: 'Refresh stop context audit',
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
      return _StopContextError(error: _error, onRetry: _loadAudit);
    }
    return _StopContextContent(summary: summary);
  }
}

class _StopContextContent extends StatelessWidget {
  const _StopContextContent({required this.summary});

  final RealtimeStopContextSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'REALTIME STOP CONTEXT AUDIT',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text('Rapid Bus KL'),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This screen checks whether realtime vehicles can be located '
              'within their static trip stop sequence. It does not calculate '
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
            _ContextMetric(
              label: 'Eligible Matched Vehicles',
              value: '${summary.eligibleMatchedVehicles}',
            ),
            _ContextMetric(
              label: 'Has Current Stop Sequence',
              value: '${summary.hasCurrentStopSequenceCount}',
            ),
            _ContextMetric(
              label: 'Sequence Matched',
              value: '${summary.sequenceMatchedCount}',
            ),
            _ContextMetric(
              label: 'Sequence Not Found',
              value: '${summary.sequenceNotFoundCount}',
            ),
            _ContextMetric(
              label: 'No Current Stop Sequence',
              value: '${summary.noCurrentStopSequenceCount}',
            ),
            _ContextMetric(
              label: 'Has Realtime Stop ID',
              value: '${summary.hasRealtimeStopIdCount}',
            ),
            _ContextMetric(
              label: 'Stop ID Consistent',
              value: '${summary.stopIdConsistentCount}',
            ),
            _ContextMetric(
              label: 'Stop ID Mismatch',
              value: '${summary.stopIdMismatchCount}',
            ),
            _ContextMetric(
              label: 'Has Explicit Current Status',
              value: '${summary.hasExplicitCurrentStatusCount}',
            ),
            _ContextMetric(
              label: 'Has Vehicle Timestamp',
              value: '${summary.hasTimestampCount}',
            ),
            _ContextMetric(
              label: 'Sequence Coverage',
              value:
                  '${summary.sequenceCoveragePercentage.toStringAsFixed(1)}%',
            ),
            _ContextMetric(
              label: 'Usable Sequence Match Rate',
              value:
                  '${summary.usableSequenceMatchPercentage.toStringAsFixed(1)}%',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('SAMPLE VEHICLES', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (summary.results.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No matched vehicles with static stop times are eligible for '
                'this audit.',
              ),
            ),
          )
        else
          for (final result in summary.results.take(5))
            _StopContextCard(result: result),
      ],
    );
  }
}

class _ContextMetric extends StatelessWidget {
  const _ContextMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
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

class _StopContextCard extends StatelessWidget {
  const _StopContextCard({required this.result});

  final RealtimeStopContextResult result;

  @override
  Widget build(BuildContext context) {
    final vehicle = result.tripMatch.vehicle;
    final stopTime = result.matchedStopTime;
    final effectiveDefault =
        vehicle.currentStatus == null &&
        vehicle.effectiveCurrentStatus == RealtimeVehicleStopStatus.inTransitTo;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Vehicle ID: ${vehicle.vehicleId ?? 'Not provided'}\n'
          'Trip ID: ${vehicle.tripId ?? 'Not provided'}\n'
          'Route ID: ${vehicle.routeId ?? 'Not provided'}\n'
          'Current Stop Sequence: '
          '${vehicle.currentStopSequence?.toString() ?? 'Not provided'}\n'
          'Realtime Stop ID: ${vehicle.stopId ?? 'Not provided'}\n'
          'Current Status: ${_statusLabel(vehicle.currentStatus)}\n'
          '${effectiveDefault ? 'GTFS effective default: IN_TRANSIT_TO\n' : ''}'
          'Vehicle Timestamp: '
          '${vehicle.timestamp?.toUtc().toIso8601String() ?? 'Not provided'}\n'
          'Static Stop ID: ${stopTime?.stopId ?? 'Not found'}\n'
          'Static Arrival: ${stopTime?.arrivalTime ?? 'Not found'}\n'
          'Static Departure: ${stopTime?.departureTime ?? 'Not found'}\n'
          'Static Stop Sequence: '
          '${stopTime?.stopSequence.toString() ?? 'Not found'}\n'
          'Context Status: ${_contextStatusLabel(result.status)}',
        ),
      ),
    );
  }

  static String _statusLabel(RealtimeVehicleStopStatus? status) {
    return switch (status) {
      RealtimeVehicleStopStatus.incomingAt => 'INCOMING_AT',
      RealtimeVehicleStopStatus.stoppedAt => 'STOPPED_AT',
      RealtimeVehicleStopStatus.inTransitTo => 'IN_TRANSIT_TO',
      null => 'Not explicitly provided',
    };
  }

  static String _contextStatusLabel(RealtimeStopContextStatus status) {
    return switch (status) {
      RealtimeStopContextStatus.noCurrentStopSequence =>
        'No current stop sequence',
      RealtimeStopContextStatus.sequenceNotFoundInStaticStopTimes =>
        'Sequence not found in static stop times',
      RealtimeStopContextStatus.sequenceMatched => 'Sequence matched',
    };
  }
}

class _StopContextError extends StatelessWidget {
  const _StopContextError({required this.error, required this.onRetry});

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
              'Unable to complete the stop context audit',
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
