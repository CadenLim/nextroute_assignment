import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_agency.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_calendar_date.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_calendar_service.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_frequency.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_route.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';

class GtfsStaticFeed {
  GtfsStaticFeed({
    required this.routes,
    required this.trips,
    required this.stopTimes,
    required this.stops,
    this.agencies = const [],
    this.calendarServices = const [],
    this.calendarDates = const [],
    this.frequencies = const [],
    this.hasAgencyFile = false,
    this.hasCalendarFile = false,
    this.hasCalendarDatesFile = false,
    this.hasFrequenciesFile = false,
  }) : stopsById = Map.unmodifiable(_buildStopsById(stops)),
       calendarServiceByServiceId = Map.unmodifiable(
         _buildCalendarServiceIndex(calendarServices),
       ),
       calendarDatesByServiceId = Map.unmodifiable(
         _buildCalendarDatesIndex(calendarDates),
       ),
       frequenciesByTripId = Map.unmodifiable(
         _buildFrequencyIndex(frequencies),
       );

  final List<GtfsRoute> routes;
  final List<GtfsTrip> trips;
  final List<GtfsStopTime> stopTimes;
  final List<GtfsStop> stops;
  final List<GtfsAgency> agencies;
  final List<GtfsCalendarService> calendarServices;
  final List<GtfsCalendarDate> calendarDates;
  final List<GtfsFrequency> frequencies;
  final bool hasAgencyFile;
  final bool hasCalendarFile;
  final bool hasCalendarDatesFile;
  final bool hasFrequenciesFile;
  final Map<String, GtfsStop> stopsById;
  final Map<String, GtfsCalendarService> calendarServiceByServiceId;
  final Map<String, List<GtfsCalendarDate>> calendarDatesByServiceId;
  final Map<String, List<GtfsFrequency>> frequenciesByTripId;

  String? get agencyTimezone =>
      agencies.isEmpty ? null : agencies.first.agencyTimezone;

  GtfsTrip? findTripById(String tripId) {
    for (final trip in trips) {
      if (trip.tripId == tripId) {
        return trip;
      }
    }
    return null;
  }

  List<GtfsStopTime> stopTimesForTrip(String tripId) {
    return List.unmodifiable(
      stopTimes.where((stopTime) => stopTime.tripId == tripId),
    );
  }

  static Map<String, GtfsStop> _buildStopsById(List<GtfsStop> stops) {
    final index = <String, GtfsStop>{};
    for (final stop in stops) {
      index.putIfAbsent(stop.stopId, () => stop);
    }
    return index;
  }

  static Map<String, GtfsCalendarService> _buildCalendarServiceIndex(
    List<GtfsCalendarService> calendarServices,
  ) {
    final index = <String, GtfsCalendarService>{};
    for (final service in calendarServices) {
      index.putIfAbsent(service.serviceId, () => service);
    }
    return index;
  }

  static Map<String, List<GtfsCalendarDate>> _buildCalendarDatesIndex(
    List<GtfsCalendarDate> calendarDates,
  ) {
    final mutableIndex = <String, List<GtfsCalendarDate>>{};
    for (final calendarDate in calendarDates) {
      mutableIndex
          .putIfAbsent(calendarDate.serviceId, () => [])
          .add(calendarDate);
    }
    return {
      for (final entry in mutableIndex.entries)
        entry.key: List<GtfsCalendarDate>.unmodifiable(entry.value),
    };
  }

  static Map<String, List<GtfsFrequency>> _buildFrequencyIndex(
    List<GtfsFrequency> frequencies,
  ) {
    final mutableIndex = <String, List<GtfsFrequency>>{};
    for (final frequency in frequencies) {
      mutableIndex.putIfAbsent(frequency.tripId, () => []).add(frequency);
    }
    return {
      for (final entry in mutableIndex.entries)
        entry.key: List<GtfsFrequency>.unmodifiable(entry.value),
    };
  }
}
