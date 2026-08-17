import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_agency.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_calendar_date.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_calendar_service.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_frequency.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_route.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';

class GtfsStaticService {
  GtfsStaticService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static final Uri endpoint = Uri.parse(
    'https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kl',
  );

  static final Csv _csv = Csv(autoDetect: false);

  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;

  Future<GtfsStaticFeed> fetchStaticFeed() async {
    try {
      final response = await _client.get(endpoint).timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GtfsStaticException(
          'Government GTFS Static feed returned HTTP '
          '${response.statusCode}.',
        );
      }
      if (response.bodyBytes.isEmpty) {
        throw const GtfsStaticException(
          'Government GTFS Static feed returned an empty response.',
        );
      }
      return parseArchiveBytes(response.bodyBytes);
    } on TimeoutException {
      throw GtfsStaticException(
        'Government GTFS Static feed did not respond within '
        '${requestTimeout.inSeconds} seconds.',
      );
    } on http.ClientException catch (error) {
      throw GtfsStaticException(
        'Could not connect to the government GTFS Static feed.',
        cause: error,
      );
    } on GtfsStaticException {
      rethrow;
    } catch (error) {
      throw GtfsStaticException(
        'Could not process the GTFS Static response.',
        cause: error,
      );
    }
  }

  static GtfsStaticFeed parseArchiveBytes(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (error) {
      throw GtfsStaticException(
        'Government GTFS Static response was not a valid ZIP archive.',
        cause: error,
      );
    }

    final routesText = _readRequiredTextFile(archive, 'routes.txt');
    final tripsText = _readRequiredTextFile(archive, 'trips.txt');
    final stopTimesText = _readRequiredTextFile(archive, 'stop_times.txt');
    final stopsText = _readRequiredTextFile(archive, 'stops.txt');
    final agencyText = _readOptionalTextFile(archive, 'agency.txt');
    final calendarText = _readOptionalTextFile(archive, 'calendar.txt');
    final calendarDatesText = _readOptionalTextFile(
      archive,
      'calendar_dates.txt',
    );
    final frequenciesText = _readOptionalTextFile(archive, 'frequencies.txt');

    return GtfsStaticFeed(
      routes: List.unmodifiable(parseRoutesCsv(routesText)),
      trips: List.unmodifiable(parseTripsCsv(tripsText)),
      stopTimes: List.unmodifiable(parseStopTimesCsv(stopTimesText)),
      stops: List.unmodifiable(parseStopsCsv(stopsText)),
      agencies: agencyText == null
          ? const []
          : List.unmodifiable(parseAgencyCsv(agencyText)),
      calendarServices: calendarText == null
          ? const []
          : List.unmodifiable(parseCalendarCsv(calendarText)),
      calendarDates: calendarDatesText == null
          ? const []
          : List.unmodifiable(parseCalendarDatesCsv(calendarDatesText)),
      frequencies: frequenciesText == null
          ? const []
          : List.unmodifiable(parseFrequenciesCsv(frequenciesText)),
      hasAgencyFile: agencyText != null,
      hasCalendarFile: calendarText != null,
      hasCalendarDatesFile: calendarDatesText != null,
      hasFrequenciesFile: frequenciesText != null,
    );
  }

  static List<GtfsRoute> parseRoutesCsv(String contents) {
    final rows = _parseCsvRows(
      contents,
      fileName: 'routes.txt',
      requiredHeaders: const {'route_id', 'route_type'},
    );
    final routes = <GtfsRoute>[];
    for (final row in rows) {
      try {
        routes.add(
          GtfsRoute(
            routeId: _requiredValue(row, 'route_id'),
            routeShortName: _optionalValue(row, 'route_short_name'),
            routeLongName: _optionalValue(row, 'route_long_name'),
            routeType: _requiredInt(row, 'route_type'),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return _requireValidRecords(routes, 'routes.txt');
  }

  static List<GtfsTrip> parseTripsCsv(String contents) {
    final rows = _parseCsvRows(
      contents,
      fileName: 'trips.txt',
      requiredHeaders: const {'route_id', 'service_id', 'trip_id'},
    );
    final trips = <GtfsTrip>[];
    for (final row in rows) {
      try {
        trips.add(
          GtfsTrip(
            routeId: _requiredValue(row, 'route_id'),
            serviceId: _requiredValue(row, 'service_id'),
            tripId: _requiredValue(row, 'trip_id'),
            tripHeadsign: _optionalValue(row, 'trip_headsign'),
            directionId: _optionalInt(row, 'direction_id'),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return _requireValidRecords(trips, 'trips.txt');
  }

  static List<GtfsStopTime> parseStopTimesCsv(String contents) {
    final rows = _parseCsvRows(
      contents,
      fileName: 'stop_times.txt',
      requiredHeaders: const {
        'trip_id',
        'arrival_time',
        'departure_time',
        'stop_id',
        'stop_sequence',
      },
    );
    final stopTimes = <GtfsStopTime>[];
    for (final row in rows) {
      try {
        stopTimes.add(
          GtfsStopTime(
            tripId: _requiredValue(row, 'trip_id'),
            arrivalTime: _requiredValue(row, 'arrival_time'),
            departureTime: _requiredValue(row, 'departure_time'),
            stopId: _requiredValue(row, 'stop_id'),
            stopSequence: _requiredInt(row, 'stop_sequence'),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return _requireValidRecords(stopTimes, 'stop_times.txt');
  }

  static List<GtfsStop> parseStopsCsv(String contents) {
    final rows = _parseCsvRows(
      contents,
      fileName: 'stops.txt',
      requiredHeaders: const {'stop_id', 'stop_lat', 'stop_lon'},
    );
    final stops = <GtfsStop>[];
    for (final row in rows) {
      try {
        stops.add(
          GtfsStop(
            stopId: _requiredValue(row, 'stop_id'),
            stopName: _optionalValue(row, 'stop_name'),
            stopLatitude: _requiredCoordinate(
              row,
              'stop_lat',
              minimum: -90,
              maximum: 90,
            ),
            stopLongitude: _requiredCoordinate(
              row,
              'stop_lon',
              minimum: -180,
              maximum: 180,
            ),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return _requireValidRecords(stops, 'stops.txt');
  }

  static List<GtfsAgency> parseAgencyCsv(String contents) {
    final rows = _parseCsvRows(
      contents,
      fileName: 'agency.txt',
      requiredHeaders: const {'agency_name', 'agency_timezone'},
    );
    final agencies = <GtfsAgency>[];
    for (final row in rows) {
      try {
        agencies.add(
          GtfsAgency(
            agencyId: _optionalValue(row, 'agency_id'),
            agencyName: _requiredValue(row, 'agency_name'),
            agencyTimezone: _requiredValue(row, 'agency_timezone'),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return _requireValidRecords(agencies, 'agency.txt');
  }

  static List<GtfsCalendarService> parseCalendarCsv(String contents) {
    final rows = _parseCsvRows(
      contents,
      fileName: 'calendar.txt',
      requiredHeaders: const {
        'service_id',
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
        'start_date',
        'end_date',
      },
    );
    final services = <GtfsCalendarService>[];
    for (final row in rows) {
      try {
        services.add(
          GtfsCalendarService(
            serviceId: _requiredValue(row, 'service_id'),
            monday: _requiredBinaryFlag(row, 'monday'),
            tuesday: _requiredBinaryFlag(row, 'tuesday'),
            wednesday: _requiredBinaryFlag(row, 'wednesday'),
            thursday: _requiredBinaryFlag(row, 'thursday'),
            friday: _requiredBinaryFlag(row, 'friday'),
            saturday: _requiredBinaryFlag(row, 'saturday'),
            sunday: _requiredBinaryFlag(row, 'sunday'),
            startDate: _requiredGtfsDate(row, 'start_date'),
            endDate: _requiredGtfsDate(row, 'end_date'),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return _requireValidRecords(services, 'calendar.txt');
  }

  static List<GtfsCalendarDate> parseCalendarDatesCsv(String contents) {
    final rows = _parseCsvRows(
      contents,
      fileName: 'calendar_dates.txt',
      requiredHeaders: const {'service_id', 'date', 'exception_type'},
    );
    final calendarDates = <GtfsCalendarDate>[];
    for (final row in rows) {
      try {
        final exceptionValue = _requiredInt(row, 'exception_type');
        final exceptionType = switch (exceptionValue) {
          1 => GtfsCalendarDateExceptionType.serviceAdded,
          2 => GtfsCalendarDateExceptionType.serviceRemoved,
          _ => throw const FormatException('Invalid exception_type.'),
        };
        calendarDates.add(
          GtfsCalendarDate(
            serviceId: _requiredValue(row, 'service_id'),
            date: _requiredGtfsDate(row, 'date'),
            exceptionType: exceptionType,
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return _requireValidRecords(calendarDates, 'calendar_dates.txt');
  }

  static List<GtfsFrequency> parseFrequenciesCsv(String contents) {
    final rows = _parseCsvRows(
      contents,
      fileName: 'frequencies.txt',
      requiredHeaders: const {
        'trip_id',
        'start_time',
        'end_time',
        'headway_secs',
      },
    );
    final frequencies = <GtfsFrequency>[];
    for (final row in rows) {
      try {
        final headwaySecs = _requiredInt(row, 'headway_secs');
        if (headwaySecs <= 0) {
          throw const FormatException('Invalid headway_secs.');
        }
        frequencies.add(
          GtfsFrequency(
            tripId: _requiredValue(row, 'trip_id'),
            startTime: _requiredValue(row, 'start_time'),
            endTime: _requiredValue(row, 'end_time'),
            headwaySecs: headwaySecs,
            exactTimes: _optionalExactTimes(row),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return _requireValidRecords(frequencies, 'frequencies.txt');
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  static String _readRequiredTextFile(Archive archive, String fileName) {
    ArchiveFile? matchingFile;
    for (final file in archive) {
      final normalizedName = file.name.replaceAll('\\', '/');
      final baseName = normalizedName.split('/').last.toLowerCase();
      if (file.isFile && baseName == fileName.toLowerCase()) {
        matchingFile = file;
        break;
      }
    }

    if (matchingFile == null) {
      throw GtfsStaticException(
        'GTFS Static archive is missing required file $fileName.',
      );
    }

    try {
      return utf8.decode(matchingFile.content);
    } on FormatException catch (error) {
      throw GtfsStaticException(
        'Required GTFS file $fileName is not valid UTF-8 text.',
        cause: error,
      );
    }
  }

  static String? _readOptionalTextFile(Archive archive, String fileName) {
    for (final file in archive) {
      final normalizedName = file.name.replaceAll('\\', '/');
      final baseName = normalizedName.split('/').last.toLowerCase();
      if (!file.isFile || baseName != fileName.toLowerCase()) {
        continue;
      }
      try {
        return utf8.decode(file.content);
      } on FormatException catch (error) {
        throw GtfsStaticException(
          'GTFS metadata file $fileName is not valid UTF-8 text.',
          cause: error,
        );
      }
    }
    return null;
  }

  static List<Map<String, String>> _parseCsvRows(
    String contents, {
    required String fileName,
    required Set<String> requiredHeaders,
  }) {
    final List<List<dynamic>> decodedRows;
    try {
      decodedRows = _csv.decode(contents);
    } catch (error) {
      throw GtfsStaticException(
        'Required GTFS file $fileName contains invalid CSV.',
        cause: error,
      );
    }

    if (decodedRows.isEmpty) {
      throw GtfsStaticException('Required GTFS file $fileName is empty.');
    }

    final headers = decodedRows.first
        .map((value) => value.toString().trim())
        .toList(growable: false);
    if (headers.isNotEmpty) {
      headers[0] = headers[0].replaceFirst('\uFEFF', '');
    }
    if (headers.toSet().length != headers.length) {
      throw GtfsStaticException(
        'Required GTFS file $fileName contains duplicate headers.',
      );
    }

    final missingHeaders = requiredHeaders.difference(headers.toSet());
    if (missingHeaders.isNotEmpty) {
      throw GtfsStaticException(
        'Required GTFS file $fileName is missing header(s): '
        '${missingHeaders.join(', ')}.',
      );
    }

    return decodedRows
        .skip(1)
        .map((values) {
          final row = <String, String>{};
          for (var index = 0; index < headers.length; index += 1) {
            row[headers[index]] = index < values.length
                ? values[index].toString()
                : '';
          }
          return row;
        })
        .toList(growable: false);
  }

  static String _requiredValue(Map<String, String> row, String header) {
    final value = row[header]?.trim();
    if (value == null || value.isEmpty) {
      throw FormatException('Missing required value for $header.');
    }
    return value;
  }

  static String? _optionalValue(Map<String, String> row, String header) {
    final value = row[header]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static int _requiredInt(Map<String, String> row, String header) {
    final value = _requiredValue(row, header);
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw FormatException('Invalid integer for $header.');
    }
    return parsed;
  }

  static int? _optionalInt(Map<String, String> row, String header) {
    final value = _optionalValue(row, header);
    if (value == null) {
      return null;
    }
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw FormatException('Invalid integer for $header.');
    }
    return parsed;
  }

  static bool _requiredBinaryFlag(Map<String, String> row, String header) {
    return switch (_requiredInt(row, header)) {
      0 => false,
      1 => true,
      _ => throw FormatException('Invalid binary flag for $header.'),
    };
  }

  static String _requiredGtfsDate(Map<String, String> row, String header) {
    final value = _requiredValue(row, header);
    if (!RegExp(r'^\d{8}$').hasMatch(value)) {
      throw FormatException('Invalid GTFS date for $header.');
    }
    return value;
  }

  static int _optionalExactTimes(Map<String, String> row) {
    final value = _optionalInt(row, 'exact_times') ?? 0;
    if (value != 0 && value != 1) {
      throw const FormatException('Invalid exact_times.');
    }
    return value;
  }

  static double _requiredCoordinate(
    Map<String, String> row,
    String header, {
    required double minimum,
    required double maximum,
  }) {
    final value = _requiredValue(row, header);
    final parsed = double.tryParse(value);
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < minimum ||
        parsed > maximum) {
      throw FormatException('Invalid coordinate for $header.');
    }
    return parsed;
  }

  static List<T> _requireValidRecords<T>(List<T> records, String fileName) {
    if (records.isEmpty) {
      throw GtfsStaticException(
        'Required GTFS file $fileName contains no valid records.',
      );
    }
    return records;
  }
}

class GtfsStaticException implements Exception {
  const GtfsStaticException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
