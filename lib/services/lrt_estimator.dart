import 'dart:math' as math;

class RailPoint {
  final double lat, lon;
  const RailPoint(this.lat, this.lon);
}

class EstimatedLrt {
  final String id, line, name, destination;
  final RailPoint point;
  const EstimatedLrt(this.id, this.line, this.name, this.destination, this.point);
}


class LrtEstimator {
  final Map<String, List<Map<String, String>>> tables;
  final List<_Trip> _trips = [];
  LrtEstimator(Map<String, String> files)
      : tables = files.map((key, value) => MapEntry(key, _csv(value))) {
    final routes = {for (final r in tables['routes']!) r['route_id']!: r};
    final stops = {for (final s in tables['stops']!) s['stop_id']!: s};
    final shapes = <String, List<Map<String, String>>>{};
    for (final s in tables['shapes']!) {
      shapes.putIfAbsent(s['shape_id']!, () => []).add(s);
    }
    for (final rows in shapes.values) {
      rows.sort((a, b) => int.parse(a['shape_pt_sequence']!).compareTo(int.parse(b['shape_pt_sequence']!)));
    }
    for (final t in tables['trips']!) {
      final r = routes[t['route_id']];

      if (r == null || !['AG', 'KJ', 'PH', 'SA'].contains(r['route_id']) || r['category'] != 'LRT') continue;
      final times = tables['stop_times']!.where((s) => s['trip_id'] == t['trip_id']).toList()
        ..sort((a, b) => int.parse(a['stop_sequence']!).compareTo(int.parse(b['stop_sequence']!)));
      final path = (shapes[t['shape_id']] ?? []).map((s) => RailPoint(double.parse(s['shape_pt_lat']!), double.parse(s['shape_pt_lon']!))).toList();
      if (times.length < 2 || path.length < 2) continue;
      final distances = <double>[0];
      for (var i = 1; i < path.length; i++) {
        distances.add(distances.last + _distance(path[i - 1], path[i]));
      }
      final visits = <_Visit>[];
      var previousIndex = 0;
      for (final time in times) {
        final s = stops[time['stop_id']];
        if (s == null) { visits.clear(); break; }
        final p = RailPoint(double.parse(s['stop_lat']!), double.parse(s['stop_lon']!));
        var best = previousIndex;
        var bestDistance = double.infinity;
        for (var i = previousIndex; i < path.length; i++) {
          final distance = _distance(p, path[i]);
          if (distance < bestDistance) { bestDistance = distance; best = i; }
        }
        previousIndex = best;
        visits.add(_Visit(_seconds(time['arrival_time']!), _seconds(time['departure_time']!), distances[best]));
      }
      if (visits.length != times.length) continue;
      _trips.add(_Trip(t['trip_id']!, t['service_id']!, r['route_short_name']!, r['route_long_name']!, t['trip_headsign'] ?? '', path, distances, visits));
    }
  }

  List<EstimatedLrt> positions(DateTime now) {

    final local = now.toUtc().add(const Duration(hours: 8));
    final midnight = DateTime.utc(local.year, local.month, local.day);
    final result = <EstimatedLrt>[];
    for (var dayOffset = 0; dayOffset <= 1; dayOffset++) {
      final day = midnight.subtract(Duration(days: dayOffset));
      final clock = local.difference(day).inMilliseconds / 1000;
      for (final trip in _trips) {
        if (!_active(trip.service, day)) continue;
        final duration = trip.visits.last.departure - trip.visits.first.departure;
        final frequencies = tables['frequencies']!.where((r) => r['trip_id'] == trip.id).toList();
        if (frequencies.isEmpty) {
          _add(result, trip, day, clock, trip.visits.first.departure);
        } else {
          for (final f in frequencies) {
            final start = _seconds(f['start_time']!);
            final end = _seconds(f['end_time']!);
            final headway = int.tryParse(f['headway_secs'] ?? '') ?? 0;
            if (headway <= 0 || end <= start) continue;
            final first = math.max(0, ((clock - duration - start) / headway).ceil());
            for (var n = first; start + n * headway < end && start + n * headway <= clock; n++) {
              _add(result, trip, day, clock, start + n * headway);
            }
          }
        }
      }
    }
    return {for (final p in result) p.id: p}.values.toList();
  }

  bool _active(String service, DateTime day) {
    final date = '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}';
    final exceptions = (tables['calendar_dates'] ?? []).where((r) => r['service_id'] == service && r['date'] == date);
    if (exceptions.isNotEmpty) return exceptions.last['exception_type'] == '1';
    const weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    return tables['calendar']!.any((r) => r['service_id'] == service &&
        date.compareTo(r['start_date']!) >= 0 && date.compareTo(r['end_date']!) <= 0 && r[weekdays[day.weekday - 1]] == '1');
  }

  void _add(List<EstimatedLrt> out, _Trip trip, DateTime day, double clock, int start) {
    final time = clock - start + trip.visits.first.departure;
    if (time < trip.visits.first.departure || time >= trip.visits.last.departure) return;
    var distance = trip.visits.first.distance;
    for (var i = 0; i < trip.visits.length; i++) {
      final stop = trip.visits[i];
      if (time <= stop.departure) { distance = stop.distance; break; }
      if (i + 1 < trip.visits.length) {
        final next = trip.visits[i + 1];
        if (time < next.arrival) {
          final fraction = (time - stop.departure) / (next.arrival - stop.departure);
          distance = stop.distance + fraction * (next.distance - stop.distance);
          break;
        }
      }
    }
    var index = 1;
    while (index < trip.distances.length - 1 && trip.distances[index] < distance) { index++; }
    final length = trip.distances[index] - trip.distances[index - 1];
    final fraction = length == 0 ? 0.0 : ((distance - trip.distances[index - 1]) / length).clamp(0.0, 1.0);
    final a = trip.path[index - 1], b = trip.path[index];
    out.add(EstimatedLrt('${trip.id}_${day.toIso8601String()}_$start', trip.line, trip.name, trip.destination,
        RailPoint(a.lat + (b.lat - a.lat) * fraction, a.lon + (b.lon - a.lon) * fraction)));
  }
}

class _Visit {
  final int arrival, departure;
  final double distance;
  _Visit(this.arrival, this.departure, this.distance);
}
class _Trip {
  final String id, service, line, name, destination;
  final List<RailPoint> path;
  final List<double> distances;
  final List<_Visit> visits;
  _Trip(this.id, this.service, this.line, this.name, this.destination, this.path, this.distances, this.visits);
}
int _seconds(String value) {
  final p = value.split(':').map(int.parse).toList();
  return p[0] * 3600 + p[1] * 60 + p[2];
}
double _distance(RailPoint a, RailPoint b) {
  final x = (a.lon - b.lon) * math.cos((a.lat + b.lat) * math.pi / 360);
  final y = a.lat - b.lat;
  return math.sqrt(x * x + y * y);
}
List<Map<String, String>> _csv(String text) {
  final rows = <List<String>>[];
  var row = <String>[], field = StringBuffer(), quoted = false;
  text = text.replaceAll('\uFEFF', '').replaceAll('\r\n', '\n');
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') { field.write('"'); i++; }
      else { quoted = !quoted; }
    } else if (!quoted && (c == ',' || c == '\n')) {
      row.add(field.toString().trim()); field = StringBuffer();
      if (c == '\n') { if (row.any((v) => v.isNotEmpty)) rows.add(row); row = []; }
    } else { field.write(c); }
  }
  row.add(field.toString().trim());
  if (row.any((v) => v.isNotEmpty)) rows.add(row);
  if (rows.isEmpty) return [];
  final header = rows.first;
  return rows.skip(1).map((r) => {for (var i = 0; i < header.length; i++) header[i]: i < r.length ? r[i] : ''}).toList();
}
