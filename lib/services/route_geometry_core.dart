import 'transit_planner.dart';

// Coordinates are [latitude, longitude]. Anchors retain GTFS stop order.
List<List<double>>? cropGtfsShape(List<List<double>> path,List<List<double>> anchors) {
  if(path.length<2 || anchors.length<2) return null;
  var previous=0;
  final indices=<int>[];
  for(final stop in anchors) {
    var best=previous, distance=double.infinity;
    for(var i=previous;i<path.length;i++) {
      final x=stop[0]-path[i][0], y=stop[1]-path[i][1];
      final d=x*x+y*y;
      if(d<distance) { best=i; distance=d; }
    }
    if(distanceMetres(JourneyPlace('','',stop[0],stop[1]),JourneyPlace('','',path[best][0],path[best][1]))>500) return null;
    indices.add(best); previous=best;
  }
  if(indices.last<=indices.first) return null;
  return [anchors.first,...path.sublist(indices.first,indices.last+1),anchors.last];
}

List<List<double>> decodeRoadGeometry(Map response) {
  if(response['code']!='Ok') throw StateError('No road route');
  final routes=response['routes'];
  if(routes is! List || routes.isEmpty) throw StateError('Empty road route');
  final coords=routes.first['geometry']['coordinates'] as List;
  final points=coords.map((v)=>[(v[1] as num).toDouble(),(v[0] as num).toDouble()]).toList();
  if(points.length<2 || points.any((p)=>!p[0].isFinite || !p[1].isFinite || p[0].abs()>90 || p[1].abs()>180)) throw StateError('Invalid road geometry');
  return points;
}