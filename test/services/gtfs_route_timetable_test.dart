import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/services/gtfs_route_timetable.dart';

GtfsServiceCalendar calendar(
  Set<int> weekdays, {
  Map<int, bool> exceptions = const {},
}) => GtfsServiceCalendar(
  weekdays: weekdays,
  startDate: DateTime(2026, 1, 1),
  endDate: DateTime(2026, 12, 31),
  exceptions: exceptions,
);

GtfsTimetableTrip trip({
  required String id,
  required String route,
  required String service,
  required List<(String, int, int)> calls,
  List<GtfsFrequencyWindow> frequencies = const [],
}) => GtfsTimetableTrip(
  id: id,
  folder: 'bus',
  routeName: route,
  serviceId: service,
  calls: [
    for (final call in calls)
      GtfsTimetableCall(
        stopId: call.$1,
        arrivalSeconds: call.$2 * 60,
        departureSeconds: call.$3 * 60,
      ),
  ],
  frequencies: frequencies,
);

RouteServiceAvailability validate({
  required List<GtfsTimetableTrip> trips,
  required Map<String, GtfsServiceCalendar> calendars,
  required List<String> services,
  Set<int> weekdays = const {DateTime.monday},
  int departureMinutes = 4 * 60,
  Map<String, String> stopGroups = const {},
}) => const GtfsRouteTimetableValidator().validate(
  trips: trips,
  calendars: calendars,
  stopGroups: stopGroups,
  originStopIds: const {'origin'},
  destinationStopIds: const {'destination'},
  serviceSequence: services,
  weekdays: weekdays,
  departureTimeMinutes: departureMinutes,
  referenceDate: DateTime(2026, 9, 7), // Monday.
);

void main() {
  test('uses a previous service day for a GTFS departure after 24:00', () {
    final result = validate(
      trips: [
        trip(
          id: 'monday-late',
          route: '250',
          service: 'monday',
          calls: const [
            ('origin', 25 * 60 + 15, 25 * 60 + 15),
            ('destination', 25 * 60 + 45, 25 * 60 + 45),
          ],
        ),
      ],
      calendars: {
        'monday': calendar({DateTime.monday}),
      },
      services: const ['250'],
      weekdays: const {DateTime.tuesday},
      departureMinutes: 60,
    );

    expect(result.isAvailable, isTrue);
    expect(result.days.single.departure, DateTime(2026, 9, 8, 1, 15));
    expect(result.estimatedDurationMinutes, 45);
  });

  test('finds the next service from a GTFS frequency window', () {
    final result = validate(
      trips: [
        trip(
          id: 'frequency-250',
          route: '250',
          service: 'weekday',
          calls: const [
            ('origin', 5 * 60 + 20, 5 * 60 + 20),
            ('destination', 5 * 60 + 50, 5 * 60 + 50),
          ],
          frequencies: const [
            GtfsFrequencyWindow(
              startSeconds: (5 * 60 + 20) * 60,
              endSeconds: 8 * 60 * 60,
              headwaySeconds: 20 * 60,
            ),
          ],
        ),
      ],
      calendars: {
        'weekday': calendar({DateTime.monday}),
      },
      services: const ['250'],
    );

    expect(result.isAvailable, isFalse);
    expect(result.nextDeparture, DateTime(2026, 9, 7, 5, 20));
  });

  test('requires the saved transfer sequence to make a valid connection', () {
    final first = trip(
      id: '251-trip',
      route: '251',
      service: 'weekday',
      calls: const [
        ('origin', 4 * 60 + 5, 4 * 60 + 5),
        ('251-platform', 4 * 60 + 30, 4 * 60 + 30),
      ],
    );
    final missedConnection = trip(
      id: '250-too-early',
      route: '250',
      service: 'weekday',
      calls: const [
        ('250-platform', 4 * 60 + 20, 4 * 60 + 20),
        ('destination', 4 * 60 + 50, 4 * 60 + 50),
      ],
    );
    final shared = const {
      '251-platform': 'transfer',
      '250-platform': 'transfer',
    };
    final calendars = {
      'weekday': calendar({DateTime.monday}),
    };

    final invalid = validate(
      trips: [first, missedConnection],
      calendars: calendars,
      services: const ['251', '250'],
      stopGroups: shared,
    );
    expect(invalid.isAvailable, isFalse);

    final connection = trip(
      id: '250-connection',
      route: '250',
      service: 'weekday',
      calls: const [
        ('250-platform', 4 * 60 + 40, 4 * 60 + 40),
        ('destination', 5 * 60 + 10, 5 * 60 + 10),
      ],
    );
    final valid = validate(
      trips: [first, missedConnection, connection],
      calendars: calendars,
      services: const ['251', '250'],
      stopGroups: shared,
    );
    expect(valid.isAvailable, isTrue);
    expect(valid.estimatedDurationMinutes, 70);
  });

  test('reports only selected weekdays without an active service calendar', () {
    final result = validate(
      trips: [
        trip(
          id: 'monday-250',
          route: '250',
          service: 'monday',
          calls: const [
            ('origin', 4 * 60 + 10, 4 * 60 + 10),
            ('destination', 4 * 60 + 40, 4 * 60 + 40),
          ],
        ),
      ],
      calendars: {
        'monday': calendar({DateTime.monday}),
      },
      services: const ['250'],
      weekdays: const {DateTime.monday, DateTime.tuesday},
    );

    expect(result.isAvailable, isFalse);
    expect(result.unavailableWeekdays, {DateTime.tuesday});
    expect(
      result.days
          .firstWhere((day) => day.weekday == DateTime.monday)
          .isAvailable,
      isTrue,
    );
  });
}
