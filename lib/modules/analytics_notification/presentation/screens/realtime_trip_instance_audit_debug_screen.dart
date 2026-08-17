import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_static_trip_matcher.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_trip_instance_auditor.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_frequency.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_trip_instance_audit_result.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_trip_instance_audit_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_realtime_service.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_static_service.dart';

class RealtimeTripInstanceAuditDebugScreen extends StatefulWidget {
  const RealtimeTripInstanceAuditDebugScreen({super.key});

  @override
  State<RealtimeTripInstanceAuditDebugScreen> createState() =>
      _RealtimeTripInstanceAuditDebugScreenState();
}

class _RealtimeTripInstanceAuditDebugScreenState
    extends State<RealtimeTripInstanceAuditDebugScreen> {
  final GtfsRealtimeService _realtimeService = GtfsRealtimeService();
  final GtfsStaticService _staticService = GtfsStaticService();
  final RealtimeStaticTripMatcher _tripMatcher =
      const RealtimeStaticTripMatcher();
  final RealtimeTripInstanceAuditor _auditor =
      const RealtimeTripInstanceAuditor();

  RealtimeTripInstanceAuditSummary? _summary;
  GtfsStaticFeed? _staticFeed;
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
      _staticFeed = null;
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
      final summary = _auditor.audit(
        tripMatchSummary: tripMatches,
        staticFeed: staticFeed,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = summary;
        _staticFeed = staticFeed;
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
        title: const Text('Trip Instance & Service Audit'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadAudit,
            tooltip: 'Refresh trip instance audit',
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
    final staticFeed = _staticFeed;
    if (summary == null || staticFeed == null) {
      return _TripInstanceError(error: _error, onRetry: _loadAudit);
    }
    return _TripInstanceContent(summary: summary, staticFeed: staticFeed);
  }
}

class _TripInstanceContent extends StatelessWidget {
  const _TripInstanceContent({required this.summary, required this.staticFeed});

  final RealtimeTripInstanceAuditSummary summary;
  final GtfsStaticFeed staticFeed;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'TRIP INSTANCE & SERVICE METADATA AUDIT',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text('Rapid Bus KL'),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This screen audits trip-instance and service-day metadata '
              'required for correct schedule-time interpretation. It does '
              'not calculate delay.',
            ),
          ),
        ),
        Text(
          'Agency Timezone: ${staticFeed.agencyTimezone ?? 'Not provided'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'Static files detected:\n'
          'agency.txt: ${_detectedLabel(staticFeed.hasAgencyFile)}\n'
          'calendar.txt: ${_detectedLabel(staticFeed.hasCalendarFile)}\n'
          'calendar_dates.txt: '
          '${_detectedLabel(staticFeed.hasCalendarDatesFile)}\n'
          'frequencies.txt: ${_detectedLabel(staticFeed.hasFrequenciesFile)}',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AuditMetric(
              label: 'Eligible Matched Vehicles',
              value: '${summary.eligibleMatchedVehicles}',
            ),
            _AuditMetric(
              label: 'Realtime Start Time Provided',
              value: '${summary.realtimeStartTimeProvidedCount}',
            ),
            _AuditMetric(
              label: 'Realtime Start Date Provided',
              value: '${summary.realtimeStartDateProvidedCount}',
            ),
            _AuditMetric(
              label: 'Explicit Schedule Relationship Provided',
              value: '${summary.explicitScheduleRelationshipProvidedCount}',
            ),
            _AuditMetric(
              label: 'Frequency-Defined Trips',
              value: '${summary.frequencyDefinedTripCount}',
            ),
            _AuditMetric(
              label: 'Fixed-Schedule Trips',
              value: '${summary.fixedScheduleTripCount}',
            ),
            _AuditMetric(
              label: 'Frequency Trips With Instance Metadata',
              value: '${summary.frequencyTripWithInstanceMetadataCount}',
            ),
            _AuditMetric(
              label: 'Frequency Trips Missing Instance Metadata',
              value: '${summary.frequencyTripMissingInstanceMetadataCount}',
            ),
            _AuditMetric(
              label: 'Calendar Service Metadata Available',
              value: '${summary.calendarServiceMetadataAvailableCount}',
            ),
            _AuditMetric(
              label: 'Calendar Service Metadata Missing',
              value: '${summary.calendarServiceMetadataMissingCount}',
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
                'No exact trip matches with static stop times are eligible '
                'for this audit.',
              ),
            ),
          )
        else
          for (final result in summary.results.take(5))
            _TripInstanceResultCard(result: result),
      ],
    );
  }

  static String _detectedLabel(bool detected) {
    return detected ? 'Detected' : 'Absent';
  }
}

class _AuditMetric extends StatelessWidget {
  const _AuditMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
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

class _TripInstanceResultCard extends StatelessWidget {
  const _TripInstanceResultCard({required this.result});

  final RealtimeTripInstanceAuditResult result;

  @override
  Widget build(BuildContext context) {
    final vehicle = result.tripMatch.vehicle;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vehicle ID: ${vehicle.vehicleId ?? 'Not provided'}\n'
              'Realtime Trip ID: ${vehicle.tripId ?? 'Not provided'}\n'
              'Route ID: ${vehicle.routeId ?? 'Not provided'}\n'
              'Realtime Start Time: '
              '${vehicle.tripStartTime ?? 'Not provided'}\n'
              'Realtime Start Date: '
              '${vehicle.tripStartDate ?? 'Not provided'}\n'
              'Schedule Relationship: '
              '${_relationshipLabel(vehicle.scheduleRelationship)}\n'
              'Static Service ID: '
              '${result.tripMatch.staticTrip?.serviceId ?? 'Not provided'}\n'
              'Frequency Defined: '
              '${result.isFrequencyDefinedTrip ? 'Yes' : 'No'}\n'
              'Frequency Entry Count: ${result.frequencyEntries.length}\n'
              'Agency Timezone: ${result.agencyTimezone ?? 'Not provided'}\n'
              'Calendar Metadata Available: '
              '${result.hasCalendarService ? 'Yes' : 'No'}\n'
              'Calendar-Date Exception Metadata Available: '
              '${result.hasCalendarDateMetadata ? 'Yes' : 'No'}\n'
              'Audit Status: ${_statusLabel(result.status)}',
            ),
            if (result.frequencyEntries.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Static Frequency Periods',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final frequency in result.frequencyEntries.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Start: ${frequency.startTime}\n'
                    'End: ${frequency.endTime}\n'
                    'Headway Seconds: ${frequency.headwaySecs}\n'
                    'Exact Times: ${_exactTimesLabel(frequency)}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _relationshipLabel(
    RealtimeTripScheduleRelationship? relationship,
  ) {
    return switch (relationship) {
      RealtimeTripScheduleRelationship.scheduled => 'SCHEDULED',
      RealtimeTripScheduleRelationship.added => 'ADDED',
      RealtimeTripScheduleRelationship.unscheduled => 'UNSCHEDULED',
      RealtimeTripScheduleRelationship.canceled => 'CANCELED',
      RealtimeTripScheduleRelationship.replacement => 'REPLACEMENT',
      RealtimeTripScheduleRelationship.duplicated => 'DUPLICATED',
      RealtimeTripScheduleRelationship.deleted => 'DELETED',
      null => 'Not explicitly provided',
    };
  }

  static String _exactTimesLabel(GtfsFrequency frequency) {
    return frequency.exactTimes == 1
        ? '1 (schedule-based frequency metadata)'
        : '0 (frequency-based service)';
  }

  static String _statusLabel(RealtimeTripInstanceAuditStatus status) {
    return switch (status) {
      RealtimeTripInstanceAuditStatus.fixedScheduleTrip =>
        'Fixed-schedule trip',
      RealtimeTripInstanceAuditStatus.frequencyTripWithInstanceMetadata =>
        'Frequency trip with instance metadata',
      RealtimeTripInstanceAuditStatus.frequencyTripMissingInstanceMetadata =>
        'Frequency trip missing instance metadata',
    };
  }
}

class _TripInstanceError extends StatelessWidget {
  const _TripInstanceError({required this.error, required this.onRetry});

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
              'Unable to complete the trip instance metadata audit',
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
