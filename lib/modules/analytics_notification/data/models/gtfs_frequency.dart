class GtfsFrequency {
  const GtfsFrequency({
    required this.tripId,
    required this.startTime,
    required this.endTime,
    required this.headwaySecs,
    required this.exactTimes,
  });

  final String tripId;
  final String startTime;
  final String endTime;
  final int headwaySecs;
  final int exactTimes;

  bool get isFrequencyBased => exactTimes == 0;
  bool get isScheduleBased => exactTimes == 1;
}
