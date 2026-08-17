import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_trip_instance_audit_result.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_trip_instance_audit_summary.dart';

class RealtimeTripInstanceAuditor {
  const RealtimeTripInstanceAuditor();

  RealtimeTripInstanceAuditSummary audit({
    required RealtimeStaticTripMatchSummary tripMatchSummary,
    required GtfsStaticFeed staticFeed,
  }) {
    final results = <RealtimeTripInstanceAuditResult>[];

    for (final tripMatch in tripMatchSummary.matches) {
      if (tripMatch.status !=
          RealtimeStaticTripMatchStatus.matchedWithStopTimes) {
        continue;
      }

      final staticTrip = tripMatch.staticTrip;
      final serviceId = staticTrip?.serviceId;
      final frequencyEntries = staticTrip == null
          ? const <Never>[]
          : staticFeed.frequenciesByTripId[staticTrip.tripId] ?? const [];
      final hasInstanceMetadata =
          _hasValue(tripMatch.vehicle.tripStartTime) &&
          _hasValue(tripMatch.vehicle.tripStartDate);
      final status = frequencyEntries.isEmpty
          ? RealtimeTripInstanceAuditStatus.fixedScheduleTrip
          : hasInstanceMetadata
          ? RealtimeTripInstanceAuditStatus.frequencyTripWithInstanceMetadata
          : RealtimeTripInstanceAuditStatus
                .frequencyTripMissingInstanceMetadata;

      results.add(
        RealtimeTripInstanceAuditResult(
          tripMatch: tripMatch,
          frequencyEntries: frequencyEntries,
          agencyTimezone: staticFeed.agencyTimezone,
          hasCalendarService:
              serviceId != null &&
              staticFeed.calendarServiceByServiceId.containsKey(serviceId),
          hasCalendarDateMetadata:
              serviceId != null &&
              (staticFeed.calendarDatesByServiceId[serviceId]?.isNotEmpty ??
                  false),
          status: status,
        ),
      );
    }

    return RealtimeTripInstanceAuditSummary(results: results);
  }

  static bool _hasValue(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}
