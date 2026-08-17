import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_trip_instance_audit_result.dart';

class RealtimeTripInstanceAuditSummary {
  RealtimeTripInstanceAuditSummary({
    required Iterable<RealtimeTripInstanceAuditResult> results,
  }) : results = List.unmodifiable(results);

  final List<RealtimeTripInstanceAuditResult> results;

  int get eligibleMatchedVehicles => results.length;

  int get realtimeStartTimeProvidedCount =>
      results.where((result) => result.hasRealtimeStartTime).length;

  int get realtimeStartDateProvidedCount =>
      results.where((result) => result.hasRealtimeStartDate).length;

  int get explicitScheduleRelationshipProvidedCount =>
      results.where((result) => result.hasExplicitScheduleRelationship).length;

  int get frequencyDefinedTripCount =>
      results.where((result) => result.isFrequencyDefinedTrip).length;

  int get fixedScheduleTripCount =>
      _countStatus(RealtimeTripInstanceAuditStatus.fixedScheduleTrip);

  int get frequencyTripWithInstanceMetadataCount => _countStatus(
    RealtimeTripInstanceAuditStatus.frequencyTripWithInstanceMetadata,
  );

  int get frequencyTripMissingInstanceMetadataCount => _countStatus(
    RealtimeTripInstanceAuditStatus.frequencyTripMissingInstanceMetadata,
  );

  int get agencyTimezoneAvailableCount =>
      results.where((result) => result.hasAgencyTimezone).length;

  int get calendarServiceMetadataAvailableCount =>
      results.where((result) => result.hasCalendarService).length;

  int get calendarServiceMetadataMissingCount =>
      eligibleMatchedVehicles - calendarServiceMetadataAvailableCount;

  int get calendarDateMetadataAvailableCount =>
      results.where((result) => result.hasCalendarDateMetadata).length;

  int _countStatus(RealtimeTripInstanceAuditStatus status) {
    return results.where((result) => result.status == status).length;
  }
}
