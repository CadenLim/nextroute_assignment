import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'transit_planner.dart';

class LegGeometry {
  final String mode, source;
  final List<LatLng> points;
  const LegGeometry(this.mode,this.source,this.points);
}
class RouteGeometry {
  static final _shapes=<String,Future<Map<String,List<LatLng>>>>{};
  static final _roads=<String,List<LatLng>>{};
  static LatLng point(Map p)=>LatLng((p['lat'] as num).toDouble(),(p['lon'] as num).toDouble());
  static List<LatLng>? anchors(Map leg) {
    final stops=leg['stops'];
    if(stops is List && stops.length>=2) return stops.map((p)=>point(p as Map)).toList();
    final from=leg['from'], to=leg['to'];
    if(from is Map && to is Map) return [point(from),point(to)];

    return null;
  }
  static List<LegGeometry> fallback(List legs) {
    final result=<LegGeometry>[];
    for(final l in legs) {
      if(l['mode']=='Wait') continue;
      final points=anchors(l);
      if(points!=null) result.add(LegGeometry(l['mode'],'straight-line fallback',points));
    }
    return result;
  }

  static Future<Map<String,List<LatLng>>> _load(String folder) async {
    final rows=parseGtfsCsv(await rootBundle.loadString('assets/gtfs/$folder/shapes.txt'));
    final groups=<String,List<Map<String,String>>>{};
    for(final row in rows) { groups.putIfAbsent(row['shape_id']!,()=>[]).add(row); }
    return groups.map((id,rs) {
      rs.sort((a,b)=>int.parse(a['shape_pt_sequence']!).compareTo(int.parse(b['shape_pt_sequence']!)));
      return MapEntry(id,rs.map((r)=>LatLng(double.parse(r['shape_pt_lat']!),double.parse(r['shape_pt_lon']!))).toList());
    });
  }
  static double _distance(LatLng a,LatLng b)=>const Distance().as(LengthUnit.Meter,a,b);
  static List<LatLng>? slice(List<LatLng> path,List<LatLng> stops) {
    if(path.length<2 || stops.length<2) return null;
    var previous=0;
    final indices=<int>[];
    for(final stop in stops) {
      var best=previous, distance=double.infinity;
      for(var i=previous;i<path.length;i++) {
        final d=_distance(stop,path[i]);
        if(d<distance) { best=i; distance=d; }
      }
      if(distance>500) return null;
      indices.add(best); previous=best;
    }
    if(indices.last<=indices.first) return null;
    return [stops.first,...path.sublist(indices.first,indices.last+1),stops.last];
  }

  static Future<List<LegGeometry>> resolve(List legs) async {
    final result=<LegGeometry>[];
    for(final raw in legs) {
      final leg=raw as Map;
      if(leg['mode']=='Wait') continue;
      final points=anchors(leg);
      if(points==null) continue;
      List<LatLng>? shape;
      final folder=leg['folder']?.toString();
      final shapeId=leg['shapeId']?.toString();
      if(folder!=null && shapeId!=null && shapeId.isNotEmpty) {
        try {
          final all=await (_shapes[folder]??=_load(folder));
          shape=slice(all[shapeId]??[],points);
        } catch(_) { _shapes.remove(folder); }
      }
      if(shape!=null) { result.add(LegGeometry(leg['mode'],'GTFS shape',shape)); continue; }

      if(leg['mode']=='Bus') {
        try {
          final road=await _road(points);
          result.add(LegGeometry('Bus','estimated road path',road)); continue;
        } catch(_) {  }
      }
      result.add(LegGeometry(leg['mode'],'straight-line fallback',points));
    }
    return result;
  }
  static Future<List<LatLng>> _road(List<LatLng> stops) async {
    final result=<LatLng>[];

    for(var start=0;start<stops.length-1;start+=24) {
      final end=(start+25).clamp(0,stops.length);
      final chunk=stops.sublist(start,end);
      final coordinates=chunk.map((p)=>'${p.longitude},${p.latitude}').join(';');
      var points=_roads[coordinates];
      if(points==null) {
        final uri=Uri.parse('https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson&steps=false');
        final response=await http.get(uri).timeout(const Duration(seconds:8));
        if(response.statusCode!=200) throw StateError('Road geometry HTTP ${response.statusCode}');
        final json=jsonDecode(response.body) as Map;
        if(json['code']!='Ok') throw StateError('No road route');
        final routes=json['routes'] as List;
        if(routes.isEmpty) throw StateError('Empty road route');
        final coords=routes.first['geometry']['coordinates'] as List;
        points=coords.map((v)=>LatLng((v[1] as num).toDouble(),(v[0] as num).toDouble())).toList();
        if(points.length<2 || points.any((p)=>!p.latitude.isFinite || !p.longitude.isFinite || p.latitude.abs()>90 || p.longitude.abs()>180)) throw StateError('Invalid road geometry');
        if(_distance(points.first,chunk.first)>500 || _distance(points.last,chunk.last)>500) throw StateError('Road snap too far from stops');
        if(_roads.length>=100) _roads.remove(_roads.keys.first);
        _roads[coordinates]=points;
      }
      result.addAll(result.isEmpty?points:points.skip(1));
    }
    return result;
  }
}