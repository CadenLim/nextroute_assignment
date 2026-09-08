import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';


class Module5RoutePreferences extends ChangeNotifier {
  Module5RoutePreferences({SharedPreferencesAsync? preferences})
    : _providedPreferences = preferences;

  static const _storageKey = 'module5.followed_routes';

  final SharedPreferencesAsync? _providedPreferences;
  SharedPreferencesAsync? _fallbackPreferences;
  SharedPreferencesAsync get _store =>
      _providedPreferences ?? (_fallbackPreferences ??= SharedPreferencesAsync());
  Set<String> _followedRoutes = const {};
  bool _loaded = false;

  Set<String> get followedRoutes => Set.unmodifiable(_followedRoutes);
  bool get loaded => _loaded;

  Future<void> load() async {
    List<String> stored;
    try {
      stored = await _store.getStringList(_storageKey) ?? const [];
    } on StateError {

      stored = const [];
    }
    _followedRoutes = {
      for (final route in stored)
        if (_normalise(route).isNotEmpty) _normalise(route),
    };
    _loaded = true;
    notifyListeners();
  }

  Future<void> replace(Iterable<String> routes) async {
    final updated = {
      for (final route in routes)
        if (_normalise(route).isNotEmpty) _normalise(route),
    };
    final sorted = updated.toList()..sort();
    try {
      await _store.setStringList(_storageKey, sorted);
    } on StateError {

    }
    _followedRoutes = Set.unmodifiable(updated);
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggle(String routeCode) async {
    final route = _normalise(routeCode);
    if (route.isEmpty) return;
    final updated = Set<String>.from(_followedRoutes);
    updated.contains(route) ? updated.remove(route) : updated.add(route);
    await replace(updated);
  }

  static String _normalise(String value) => value.trim().toUpperCase();
}
