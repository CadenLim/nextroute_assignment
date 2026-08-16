import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';

class RealtimeStaticTripMatchSummary {
  RealtimeStaticTripMatchSummary({
    required Iterable<RealtimeStaticTripMatch> matches,
  }) : matches = List.unmodifiable(matches);

  final List<RealtimeStaticTripMatch> matches;

  int get totalRealtimeVehicles => matches.length;

  int get noTripIdCount => _count(RealtimeStaticTripMatchStatus.noTripId);

  int get noStaticTripCount =>
      _count(RealtimeStaticTripMatchStatus.noStaticTrip);

  int get routeMismatchCount =>
      _count(RealtimeStaticTripMatchStatus.routeMismatch);

  int get matchedWithoutStopTimesCount =>
      _count(RealtimeStaticTripMatchStatus.matchedWithoutStopTimes);

  int get matchedWithStopTimesCount =>
      _count(RealtimeStaticTripMatchStatus.matchedWithStopTimes);

  int get exactMatchedCount =>
      routeMismatchCount +
      matchedWithoutStopTimesCount +
      matchedWithStopTimesCount;

  int get vehiclesWithTripIdCount => totalRealtimeVehicles - noTripIdCount;

  double get exactMatchPercentage {
    final vehiclesWithTripId = vehiclesWithTripIdCount;
    if (vehiclesWithTripId == 0) {
      return 0;
    }
    return exactMatchedCount / vehiclesWithTripId * 100;
  }

  int _count(RealtimeStaticTripMatchStatus status) {
    return matches.where((match) => match.status == status).length;
  }
}
