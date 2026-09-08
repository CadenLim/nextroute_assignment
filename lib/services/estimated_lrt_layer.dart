import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/lrt_estimator.dart';

class EstimatedLrtLayer extends StatefulWidget {
  final Map<String, dynamic>? route;
  final String query;
  const EstimatedLrtLayer({super.key, this.route, this.query = ''});
  @override
  State<EstimatedLrtLayer> createState() => _EstimatedLrtLayerState();
}

class _EstimatedLrtLayerState extends State<EstimatedLrtLayer> {
  static Future<LrtEstimator>? _sharedModel;
  LrtEstimator? _model;
  Timer? _timer;
  String? _error;

  static Future<LrtEstimator> _load() async {
    final files = <String, String>{};
    for (final name in ['routes', 'trips', 'stops', 'stop_times', 'shapes', 'frequencies', 'calendar']) {
      files[name] = await rootBundle.loadString('assets/gtfs/rail/$name.txt');
    }
    try {
      files['calendar_dates'] = await rootBundle.loadString('assets/gtfs/rail/calendar_dates.txt');
    } catch (_) {  }
    return LrtEstimator(files);
  }

  @override
  void initState() {
    super.initState();
    _initialize();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _model != null) setState(() {});
    });
  }

  Future<void> _initialize() async {
    try {
      final model = await (_sharedModel ??= _load());
      if (mounted) setState(() => _model = model);
    } catch (e) {
      _sharedModel = null;
      debugPrint('LRT timetable could not load: $e');
      if (mounted) setState(() => _error = 'LRT timetable unavailable');
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  bool _lineMatches(EstimatedLrt p, String text) {
    text = text.trim().toUpperCase();
    final aliases = switch (p.line) {
      'KJL' => ['KJL', 'KJ', 'LINE 5', 'KELANA JAYA'],
      'AGL' => ['AGL', 'AG', 'LINE 3', 'AMPANG'],
      'SPL' => ['SPL', 'SP', 'PH', 'LINE 4', 'SRI PETALING'],
      'SAL' => ['SAL', 'SA', 'LINE 11', 'SHAH ALAM'],
      _ => [p.line.toUpperCase()],
    };
    return aliases.any((a) => RegExp('(^|[^A-Z0-9])${RegExp.escape(a)}([^A-Z0-9]|\$)').hasMatch(text));
  }

  bool _matches(EstimatedLrt p) {
    final route = widget.route;
    if (route != null) {
      final legs = route['legs'];
      if (legs is! List || !legs.any((leg) => leg is Map &&
          leg['mode'].toString().toUpperCase() == 'RAIL' &&
          _lineMatches(p, leg['name'].toString()))) return false;
    }
    final query = widget.query.trim().toUpperCase();
    return query.isEmpty || query == 'LRT' || _lineMatches(p, query);
  }

  @override
  Widget build(BuildContext context) {
    final positions = (_model?.positions(DateTime.now()) ?? <EstimatedLrt>[]).where(_matches).toList();
    return Stack(children: [
      MarkerLayer(markers: positions.map((p) => Marker(
        point: LatLng(p.point.lat, p.point.lon), width: 80, height: 54,
        child: Tooltip(
          message: '${p.name}\n${p.destination}\nEstimated from timetable; not live GPS. Delays are not reflected.',
          child: Column(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: const Color(0xFF7C3AED),
                border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.train, color: Colors.white, size: 19),
            ),
            Container(color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text('${p.line} EST', style: const TextStyle(fontSize: 10,
                color: Color(0xFF6D28D9), fontWeight: FontWeight.bold))),
          ]),
        ),
      )).toList()),
      Positioned(left: 8, bottom: 8, child: IgnorePointer(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(5)),
        child: Text(_error ?? (_model == null ? 'Loading LRT timetable…' :
          '${positions.length} estimated LRT • timetable, not GPS'),
          style: const TextStyle(fontSize: 10, color: Color(0xFF6D28D9))),
      ))),
    ]);
  }
}
