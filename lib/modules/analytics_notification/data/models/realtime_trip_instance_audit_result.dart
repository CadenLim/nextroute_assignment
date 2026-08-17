import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_frequency.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';

enum RealtimeTripInstanceAuditStatus {
  fixedScheduleTrip,
  frequencyTripWithInstanceMetadata,
  frequencyTripMissingInstanceMetadata,
}

class RealtimeTripInstanceAuditResult {
  RealtimeTripInstanceAuditResult({
    required this.tripMatch,
    required Iterable<GtfsFrequency> frequencyEntries,
    required this.agencyTimezone,
    required this.hasCalendarService,
    required this.hasCalendarDateMetadata,
    required this.status,
  }) : frequencyEntries = List.unmodifiable(frequencyEntries);

  final RealtimeStaticTripMatch tripMatch;
  final List<GtfsFrequency> frequencyEntries;
  final String? agencyTimezone;
  final bool hasCalendarService;
  final bool hasCalendarDateMetadata;
  final RealtimeTripInstanceAuditStatus status;

  bool get hasRealtimeStartTime => _hasValue(tripMatch.vehicle.tripStartTime);

  bool get hasRealtimeStartDate => _hasValue(tripMatch.vehicle.tripStartDate);

  bool get hasExplicitScheduleRelationship =>
      tripMatch.vehicle.scheduleRelationship != null;

  bool get isFrequencyDefinedTrip => frequencyEntries.isNotEmpty;

  bool get hasAgencyTimezone => _hasValue(agencyTimezone);

  static bool _hasValue(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}
