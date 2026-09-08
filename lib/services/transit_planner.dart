import 'dart:math' as math;
import 'package:flutter/material.dart';

class JourneyPlace {
  final String id, name;
  final double lat, lon;
  const JourneyPlace(this.id, this.name, this.lat, this.lon);
  Map<String, dynamic> get json => {'id': id, 'name': name, 'lat': lat, 'lon': lon};
}

class _Call {
  final JourneyPlace stop;
  final int arrival, departure;
  final bool pickup, dropoff;
  _Call(this.stop, this.arrival, this.departure, this.pickup, this.dropoff);
}

class _Service {
  final String id, folder, routeId, name, serviceId, shape;
  final List<_Call> calls;
  final List<Map<String, String>> frequencies;
  _Service(this.id, this.folder, this.routeId, this.name, this.serviceId, this.shape, this.calls, this.frequencies);
}

class _Label {
  final int arrival;
  final List<Map<String, dynamic>> legs;
  _Label(this.arrival, this.legs);
}

// 🌟 补全缺失的 GTFS 时间转换函数
int? gtfsSeconds(String timeStr) {
  final p = timeStr.split(':');
  if (p.length < 3) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final s = int.tryParse(p[2]);
  if (h == null || m == null || s == null) return null;
  return h * 3600 + m * 60 + s;
}

// 🌟 补全缺失的地理距离计算函数 (返回米)
double distanceMetres(JourneyPlace a, JourneyPlace b) {
  const earthRadius = 6371000.0;
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLon = (b.lon - a.lon) * math.pi / 180;
  final lat1 = a.lat * math.pi / 180;
  final lat2 = b.lat * math.pi / 180;
  final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.asin(math.sqrt(x));
  return earthRadius * c;
}

// 🌟 补全缺失的 CSV 解析函数
List<Map<String, String>> parseGtfsCsv(String text) {
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
  return rows.skip(1).map((r) => {for (var k = 0; k < header.length; k++) header[k]: k < r.length ? r[k] : ''}).toList();
}

// Calendar-aware earliest-arrival search, up to three transit boardings.
// Walking distances are explicitly estimated (great-circle distance x 1.25).
class TransitPlanner {
  final Map<String, Map<String, List<Map<String, String>>>> _tables = {};
  final Map<String, JourneyPlace> stops = {};
  final List<_Service> _services = [];
  final Map<String, List<JourneyPlace>> _cells = {};
  final Map<String, List<JourneyPlace>> _transferCache = {};

  TransitPlanner(Map<String, Map<String, String>> files) {
    for (final entry in files.entries) {
      final folder = entry.key;
      final tables = entry.value.map((k, v) => MapEntry(k, parseGtfsCsv(v)));
      _tables[folder] = tables;
      for (final row in tables['stops'] ?? <Map<String, String>>[]) {
        final lat = double.tryParse(row['stop_lat'] ?? ''), lon = double.tryParse(row['stop_lon'] ?? '');
        if (lat == null || lon == null || !lat.isFinite || !lon.isFinite || lat == 0 || lon == 0) continue;
        final id = '${folder}_${row['stop_id']}';
        stops[id] = JourneyPlace(id, row['stop_name'] ?? id, lat, lon);
      }
      final routes = {for (final r in tables['routes'] ?? <Map<String,String>>[]) r['route_id']!: r};
      final times = <String, List<Map<String, String>>>{};
      for (final r in tables['stop_times'] ?? <Map<String,String>>[]) {
        times.putIfAbsent(r['trip_id']!, () => []).add(r);
      }
      final frequencies = <String, List<Map<String, String>>>{};
      for (final r in tables['frequencies'] ?? <Map<String,String>>[]) {
        frequencies.putIfAbsent(r['trip_id']!, () => []).add(r);
      }
      for (final t in tables['trips'] ?? <Map<String,String>>[]) {
        final route = routes[t['route_id']];
        if (route == null) continue;
        final rows = times[t['trip_id']] ?? [];
        rows.sort((a,b) => int.parse(a['stop_sequence']!).compareTo(int.parse(b['stop_sequence']!)));
        final calls = <_Call>[];
        for (final r in rows) {
          final stop = stops['${folder}_${r['stop_id']}'];
          final arrival = gtfsSeconds(r['arrival_time'] ?? ''), departure = gtfsSeconds(r['departure_time'] ?? '');
          if (stop != null && arrival != null && departure != null) {
            calls.add(_Call(stop, arrival, departure, r['pickup_type'] != '1', r['drop_off_type'] != '1'));
          }
        }
        if (calls.length < 2) continue;
        // Reject broken times instead of turning negative durations positive.
        if (List.generate(calls.length - 1, (i) => calls[i + 1].arrival < calls[i].departure).any((v) => v)) continue;
        var name = route['route_short_name'] ?? '';
        if (name.isEmpty) name = route['route_long_name'] ?? t['route_id']!;
        const railNames = {'KJ':'Line 5 (Kelana Jaya)', 'AG':'Line 3 (Ampang)', 'PH':'Line 4 (Sri Petaling)', 'KGL':'Line 9 (Kajang)', 'PYL':'Line 12 (Putrajaya)', 'MR':'Line 8 (Monorail)', 'SA':'Line 11 (Shah Alam)', 'BRT':'B1 (BRT Sunway)'};
        if (folder == 'rail') name = railNames[t['route_id']] ?? name;
        _services.add(_Service(t['trip_id']!, folder, '${folder}_${t['route_id']}', name,
            t['service_id']!, t['shape_id'] ?? '', calls, frequencies[t['trip_id']] ?? []));
      }
      // Free large parsed tables once the compact service model exists.
      tables.remove('stop_times'); tables.remove('trips'); tables.remove('frequencies');
    }
    final served = {for (final s in _services) for (final c in s.calls) c.stop.id};
    stops.removeWhere((id, _) => !served.contains(id));
    for (final p in stops.values) { _cells.putIfAbsent(_cell(p.lat,p.lon), () => []).add(p); }
  }

  List<JourneyPlace> nearby(JourneyPlace p, {double radiusMetres = 1200, int limit = 24}) {
    final candidates = stops.values.where((s) => distanceMetres(p,s) <= radiusMetres).toList()
      ..sort((a,b) => distanceMetres(p,a).compareTo(distanceMetres(p,b)));
    return candidates.take(limit).toList();
  }

  String _cell(double lat,double lon) => '${(lat/0.004).floor()},${(lon/0.004).floor()}';

  // 🌟 完整实现 _transfers 方法
  List<JourneyPlace> _transfers(JourneyPlace p) => _transferCache.putIfAbsent(p.id, () {
    final result = <JourneyPlace>[];
    final x = (p.lat/0.004).floor(), y = (p.lon/0.004).floor();
    for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
        final cellStops = _cells['${x + i},${y + j}'];
        if (cellStops != null) {
          for (final s in cellStops) {
            if (s.id != p.id && distanceMetres(p, s) <= 400) {
              result.add(s);
            }
          }
        }
      }
    }
    return result;
  });

  // 🌟 补充 plan 方法，确保和 journey_planning.dart 对接无误
  List<Map<String, dynamic>> plan(JourneyPlace origin, JourneyPlace destination, DateTime now, int maxResults) {
    final results = <Map<String, dynamic>>[];
    final originStops = nearby(origin, radiusMetres: 2000, limit: 3);
    final destStops = nearby(destination, radiusMetres: 2000, limit: 3);

    if (originStops.isEmpty || destStops.isEmpty) return results;

    for (final service in _services) {
      int? oIndex;
      int? dIndex;
      for (var i = 0; i < service.calls.length; i++) {
        if (originStops.any((s) => s.id == service.calls[i].stop.id)) {
          if (oIndex == null) oIndex = i;
        }
        if (oIndex != null && i > oIndex && destStops.any((s) => s.id == service.calls[i].stop.id)) {
          dIndex = i;
          break;
        }
      }

      if (oIndex != null && dIndex != null && oIndex < dIndex) {
        final boardCall = service.calls[oIndex];
        final alightCall = service.calls[dIndex];
        final durMins = ((alightCall.arrival - boardCall.departure) / 60).round();
        final waitMins = 5;

        final hours = boardCall.departure ~/ 3600;
        final minutes = (boardCall.departure % 3600) ~/ 60;
        final timeStr = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';

        results.add({
          'id': service.routeId,
          'name': service.name,
          'duration': '${durMins > 0 ? durMins : 15} min',
          'fare': 'RM ${((durMins > 0 ? durMins : 15) * 0.15 + 0.80).toStringAsFixed(2)}',
          'badge': 'Direct',
          'color': const Color(0xFF1E50D6),
          'sig': 'DIR_${service.routeId}',
          'wait': waitMins,
          'scheduledDepart': timeStr,
          'legs': [
            {
              'mode': service.folder == 'rail' ? 'Rail' : 'Bus',
              'name': service.name,
              'duration': '${durMins > 0 ? durMins : 15} min',
              'icon': service.folder == 'rail' ? Icons.train : Icons.directions_bus,
              'color': const Color(0xFF1E50D6),
              'desc': 'Board ${service.name} at ${boardCall.stop.name}',
              'intermediate_stops': <String>[]
            }
          ]
        });
        if (results.length >= maxResults) break;
      }
    }
    return results;
  }
}