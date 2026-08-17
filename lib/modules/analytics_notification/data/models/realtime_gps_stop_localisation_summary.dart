import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_gps_stop_localisation_result.dart';

class RealtimeGpsStopLocalisationSummary {
  RealtimeGpsStopLocalisationSummary({
    required Iterable<RealtimeGpsStopLocalisationResult> results,
  }) : results = List.unmodifiable(results);

  final List<RealtimeGpsStopLocalisationResult> results;

  int get eligibleMatchedVehicles => results.length;

  int get nearestScheduledStopFoundCount =>
      _countStatus(RealtimeGpsStopLocalisationStatus.nearestScheduledStopFound);

  int get noCandidateStopsCount =>
      _countStatus(RealtimeGpsStopLocalisationStatus.noCandidateStops);

  int get within100mCount => _countBand(RealtimeGpsStopDistanceBand.within100m);

  int get over100To250mCount =>
      _countBand(RealtimeGpsStopDistanceBand.over100To250m);

  int get over250To500mCount =>
      _countBand(RealtimeGpsStopDistanceBand.over250To500m);

  int get over500mCount => _countBand(RealtimeGpsStopDistanceBand.over500m);

  int get distanceBandTotal =>
      within100mCount + over100To250mCount + over250To500mCount + over500mCount;

  double get localisationCoveragePercentage {
    if (eligibleMatchedVehicles == 0) {
      return 0;
    }
    return nearestScheduledStopFoundCount / eligibleMatchedVehicles * 100;
  }

  int _countStatus(RealtimeGpsStopLocalisationStatus status) {
    return results.where((result) => result.status == status).length;
  }

  int _countBand(RealtimeGpsStopDistanceBand band) {
    return results.where((result) => result.distanceBand == band).length;
  }
}
