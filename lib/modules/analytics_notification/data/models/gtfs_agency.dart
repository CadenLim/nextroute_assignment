class GtfsAgency {
  const GtfsAgency({
    required this.agencyId,
    required this.agencyName,
    required this.agencyTimezone,
  });

  final String? agencyId;
  final String agencyName;
  final String agencyTimezone;
}
