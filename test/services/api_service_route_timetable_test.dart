import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'validates route 250 against the bundled GTFS weekday timetable',
    () async {
      final api = ApiService();
      final origin = StationModel(
        ids: const ['bus_1000285'],
        name: 'PV128 SETAPAK',
        lines: {'250'},
        category: 'Bus',
        lat: 3.199125,
        lon: 101.716094,
      );
      final destination = StationModel(
        ids: const ['bus_1008325'],
        name: 'TAMAN BUNGA RAYA',
        lines: {'250'},
        category: 'Bus',
        lat: 3.213066,
        lon: 101.729618,
      );

      final available = await api.validateRouteTimetable(
        origin: origin,
        destination: destination,
        serviceSequence: const ['250'],
        weekdays: const {DateTime.monday},
        departureTimeMinutes: 8 * 60 + 30,
        referenceDate: DateTime(2026, 9, 7),
      );
      expect(available.isAvailable, isTrue);
      expect(available.days.single.departure, DateTime(2026, 9, 7, 8, 36, 46));
      expect(available.estimatedDurationMinutes, 12);

      final beforeService = await api.validateRouteTimetable(
        origin: origin,
        destination: destination,
        serviceSequence: const ['250'],
        weekdays: const {DateTime.monday},
        departureTimeMinutes: 4 * 60,
        referenceDate: DateTime(2026, 9, 7),
      );
      expect(beforeService.isAvailable, isFalse);
      expect(beforeService.nextDeparture, DateTime(2026, 9, 7, 6, 11, 46));
    },
  );
}
