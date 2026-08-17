enum GtfsCalendarDateExceptionType { serviceAdded, serviceRemoved }

class GtfsCalendarDate {
  const GtfsCalendarDate({
    required this.serviceId,
    required this.date,
    required this.exceptionType,
  });

  final String serviceId;
  final String date;
  final GtfsCalendarDateExceptionType exceptionType;
}
