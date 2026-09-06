import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/screens/transport_data.dart';

void main() {
  group('Station model', () {
    test('withDistance keeps station details and updates only distance', () {
      const station = Station(
        'KL Sentral',
        double.infinity,
        ['KJ', 'MR'],
        latitude: 3.1342,
        longitude: 101.6861,
        type: 'Rail',
        accessible: true,
        stopIds: ['KJ15'],
        sources: ['rail'],
        landmark: 'KL Sentral transportation hub',
      );

      final nearbyStation = station.withDistance(1.25);

      expect(station.hasDistance, isFalse);
      expect(nearbyStation.hasDistance, isTrue);
      expect(nearbyStation.distance, 1.25);
      expect(nearbyStation.name, station.name);
      expect(nearbyStation.lines, station.lines);
      expect(nearbyStation.latitude, station.latitude);
      expect(nearbyStation.longitude, station.longitude);
      expect(nearbyStation.accessible, isTrue);
      expect(nearbyStation.stopIds, station.stopIds);
      expect(nearbyStation.sources, station.sources);
      expect(nearbyStation.landmark, station.landmark);
    });
  });

  group('Location calculations', () {
    test('distance between the same coordinates is zero', () {
      expect(distanceKm(3.1390, 101.6869, 3.1390, 101.6869), closeTo(0, 0.001));
    });

    test('one longitude degree at the equator is about 111.2 km', () {
      expect(distanceKm(0, 100, 0, 101), closeTo(111.2, 0.2));
    });

    test('recognises Malaysia and rejects emulator default location', () {
      expect(isInsideMalaysia(3.1390, 101.6869), isTrue);
      expect(isInsideMalaysia(37.4220, -122.0840), isFalse);
    });

    test('outside-coverage message explains emulator location problem', () {
      final message = locationOutsideCoverageMessage(37.4220, -122.0840);

      expect(message, contains('outside Malaysia'));
      expect(message, contains('Android Emulator'));
      expect(message, contains('37.4220'));
    });
  });

  group('Transit route presentation', () {
    test('uses the route short name and keeps destination as description', () {
      const route = TransitRoute(
        id: 'route_250',
        shortName: '250',
        longName: 'Wangsa Maju - Lebuh Ampang',
        stopIds: {'stop_1', 'stop_2'},
        shapePoints: [],
      );

      expect(route.displayName, '250');
      expect(route.description, 'Wangsa Maju - Lebuh Ampang');
    });

    test('falls back to route id when no useful short name exists', () {
      const route = TransitRoute(
        id: 'rapid_kl_route',
        shortName: '',
        longName: 'Wangsa Maju to city centre',
        stopIds: {},
        shapePoints: [],
      );

      expect(route.displayName, 'rapid_kl_route');
    });
  });

  group('Rail line appearance', () {
    test('uses official colours for major Klang Valley rail lines', () {
      expect(lineColor('KJ'), const Color(0xFFD50032));
      expect(lineColor('AG'), const Color(0xFFE57200));
      expect(lineColor('KGL'), const Color(0xFF047940));
      expect(lineColor('PYL'), const Color(0xFFFFCD00));
      expect(lineColor('SA'), const Color(0xFF00A9E0));
    });

    test('supports route aliases and readable rail line names', () {
      expect(lineColor('KG'), lineColor('KGL'));
      expect(lineColor('PY'), lineColor('PYL'));
      expect(railLineName('KJ'), 'Kelana Jaya Line');
      expect(railLineName('PH'), 'Sri Petaling Line');
      expect(railLineName('MR'), 'KL Monorail Line');
    });

    test('uses dark foreground for bright yellow and green markers', () {
      expect(lineForegroundColor('PYL'), const Color(0xFF1E293B));
      expect(lineForegroundColor('MR'), const Color(0xFF1E293B));
      expect(lineForegroundColor('KJ'), Colors.white);
    });
  });
}
