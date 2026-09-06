import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart'
    hide Position;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart' as handler;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

part 'transport_map_screen.dart';
part 'station_detail_screen.dart';
part '../services/transport_data_service.dart';

const _blue = Color(0xFF2563EB);
const _navy = Color(0xFF27364C);
const _page = Color(0xFFF1F5F9);
const _ink = Color(0xFF1E293B);

class TransportDataScreen extends StatefulWidget {
  const TransportDataScreen({super.key});

  @override
  State<TransportDataScreen> createState() => _TransportDataScreenState();
}

class _TransportDataScreenState extends State<TransportDataScreen> {
  List<Station> nearbyPreview = [];
  List<Station> recentSearches = [];
  bool loadingPreview = true;
  bool loadingRecentSearches = true;
  String? previewMessage;

  @override
  void initState() {
    super.initState();
    _loadNearbyPreview();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    try {
      final loaded = await RecentStationService.load();
      if (!mounted) return;
      setState(() {
        recentSearches = loaded;
        loadingRecentSearches = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingRecentSearches = false);
    }
  }

  Future<void> _clearRecentSearches() async {
    await RecentStationService.clear();
    if (!mounted) return;
    setState(() => recentSearches = []);
  }

  Future<void> _loadNearbyPreview() async {
    if (mounted) {
      setState(() {
        loadingPreview = true;
        previewMessage = null;
      });
    }
    try {
      final position = await DeviceLocationService.currentLocation();
      final latitude = position.latitude;
      final longitude = position.longitude;
      if (!isInsideMalaysia(latitude, longitude)) {
        throw Exception(locationOutsideCoverageMessage(latitude, longitude));
      }
      final stations = await StationRepository.instance.loadAll();
      final sorted =
      stations
          .where(
            (station) => station.latitude != 0 && station.longitude != 0,
      )
          .map(
            (station) => station.withDistance(
          distanceKm(
            latitude,
            longitude,
            station.latitude,
            station.longitude,
          ),
        ),
      )
          .toList()
        ..sort((a, b) => a.distance.compareTo(b.distance));
      if (sorted.isEmpty || sorted.first.distance > 100) {
        throw Exception(locationOutsideCoverageMessage(latitude, longitude));
      }
      if (!mounted) return;
      setState(() {
        nearbyPreview = sorted.take(3).toList();
        loadingPreview = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loadingPreview = false;
        previewMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _loadRecentSearches();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: _blue,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 46),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transport Information',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Find Your Station',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  children: [
                    _SearchCard(onTap: () => open(const StationSearchScreen())),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.location_on_outlined,
                            label: 'Nearby Stations',
                            color: const Color(0xFF059669),
                            onTap: () => open(const NearbyStationsScreen()),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.map_outlined,
                            label: 'View Map',
                            color: const Color(0xFF7C3AED),
                            onTap: () => open(const TransitMapScreen()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'NEAREST STATIONS',
                          style: TextStyle(
                            color: Color(0xFF71839E),
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                          ),
                        ),
                        TextButton(
                          onPressed: loadingPreview ? null : _loadNearbyPreview,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                    if (loadingPreview)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (nearbyPreview.isNotEmpty)
                      StationListCard(items: nearbyPreview)
                    else if (previewMessage != null)
                        _MessageCard(
                          icon: Icons.location_off_outlined,
                          color: Colors.orange,
                          message: previewMessage!,
                          actionLabel: 'Try again',
                          onAction: _loadNearbyPreview,
                        ),
                    if (!loadingRecentSearches &&
                        recentSearches.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'RECENT SEARCHES',
                            style: TextStyle(
                              color: Color(0xFF71839E),
                              fontWeight: FontWeight.w700,
                              letterSpacing: .8,
                            ),
                          ),
                          TextButton(
                            onPressed: _clearRecentSearches,
                            child: const Text('Clear all'),
                          ),
                        ],
                      ),
                      StationListCard(
                        items: recentSearches,
                        onHistoryChanged: _loadRecentSearches,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchCard({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 2,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          children: [
            _SoftIcon(Icons.search, _blue),
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search Station',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Find any station by name or line',
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 1,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            _SoftIcon(icon, color),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SoftIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _SoftIcon(this.icon, this.color);
  @override
  Widget build(BuildContext context) => Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Icon(icon, color: color, size: 28),
  );
}

class StationListCard extends StatelessWidget {
  final List<Station> items;
  final Future<void> Function()? onHistoryChanged;

  const StationListCard({
    super.key,
    required this.items,
    this.onHistoryChanged,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 8),
      ],
    ),
    child: Column(
      children: List.generate(items.length, (index) {
        final station = items[index];
        return Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: _SoftIcon(
                Icons.my_location,
                lineColor(station.lines.first),
              ),
              title: Text(
                station.name,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 5,
                  children: station.lines.map((e) => LineBadge(e)).toList(),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (station.hasDistance) ...[
                    Text(
                      station.distance < 1
                          ? '${(station.distance * 1000).round()} m'
                          : '${station.distance.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                ],
              ),
              onTap: () async {
                await openStationDetails(context, station);
                await onHistoryChanged?.call();
              },
            ),
            if (index != items.length - 1)
              const Divider(height: 1, indent: 18, endIndent: 18),
          ],
        );
      }),
    ),
  );
}

class LineBadge extends StatelessWidget {
  final String code;
  const LineBadge(this.code, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: lineColor(code),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      code,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class StationSearchScreen extends StatefulWidget {
  const StationSearchScreen({super.key});
  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

class _StationSearchScreenState extends State<StationSearchScreen> {
  String query = '';
  List<Station> allStations = [];
  bool loading = true;
  String? locationMessage;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    final loaded = await StationRepository.instance.loadAll();
    List<Station> located = loaded;
    String? message;
    try {
      final position = await DeviceLocationService.currentLocation();
      final latitude = position.latitude;
      final longitude = position.longitude;
      if (!isInsideMalaysia(latitude, longitude)) {
        message = locationOutsideCoverageMessage(latitude, longitude);
      } else {
        located =
        loaded
            .where(
              (station) => station.latitude != 0 && station.longitude != 0,
        )
            .map(
              (station) => station.withDistance(
            distanceKm(
              latitude,
              longitude,
              station.latitude,
              station.longitude,
            ),
          ),
        )
            .toList()
          ..sort((a, b) => a.distance.compareTo(b.distance));
        if (located.isEmpty || located.first.distance > 100) {
          message = locationOutsideCoverageMessage(latitude, longitude);
          located = loaded;
        }
      }
    } catch (error) {
      message = error.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() {
      allStations = located;
      locationMessage = message;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final result =
    normalizedQuery.isEmpty
        ? allStations
        .where((station) => station.hasDistance)
        .take(12)
        .toList()
        : allStations.where((station) {
      return station.name.toLowerCase().contains(normalizedQuery) ||
          station.type.toLowerCase().contains(normalizedQuery) ||
          station.lines.any(
                (line) => line.toLowerCase().contains(normalizedQuery),
          );
    }).toList()
      ..sort((a, b) {
        final aExact = a.name.toLowerCase() == normalizedQuery ? 0 : 1;
        final bExact = b.name.toLowerCase() == normalizedQuery ? 0 : 1;
        if (aExact != bExact) return aExact.compareTo(bExact);
        if (a.hasDistance && b.hasDistance) {
          return a.distance.compareTo(b.distance);
        }
        return a.name.compareTo(b.name);
      });
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: _blue,
              padding: const EdgeInsets.fromLTRB(14, 12, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: Navigator.of(context).pop,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    label: const Text(
                      'Back',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Search Station',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    autofocus: false,
                    onChanged: (value) => setState(() => query = value),
                    decoration: InputDecoration(
                      hintText: 'Station name or line...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    normalizedQuery.isEmpty
                        ? 'NEAREST STATIONS'
                        : '${result.length} RESULT${result.length == 1 ? '' : 'S'}',
                    style: const TextStyle(
                      color: Color(0xFF71839E),
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (locationMessage != null && normalizedQuery.isEmpty) ...[
                    _MessageCard(
                      icon: Icons.location_off_outlined,
                      color: Colors.orange.shade800,
                      message: locationMessage!,
                      actionLabel: 'Try location again',
                      onAction: () {
                        setState(() {
                          loading = true;
                          locationMessage = null;
                        });
                        _loadStations();
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (result.isEmpty &&
                      normalizedQuery.isEmpty &&
                      locationMessage != null)
                    const SizedBox.shrink()
                  else if (result.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(
                          child: Text(
                            'No station found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      StationListCard(items: result),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NearbyStationsScreen extends StatefulWidget {
  const NearbyStationsScreen({super.key});
  @override
  State<NearbyStationsScreen> createState() => _NearbyStationsScreenState();
}

class _NearbyStationsScreenState extends State<NearbyStationsScreen> {
  bool detected = false;
  bool loading = false;
  bool tracking = false;
  List<Station> nearest = [];
  loc.LocationData? currentPosition;
  String? errorMessage;
  StreamSubscription<loc.LocationData>? locationSubscription;

  Future<void> _detectLocation() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final position = await DeviceLocationService.currentLocation();
      final valid = await _updateNearest(position);
      if (!valid) {
        if (!mounted) return;
        setState(() => loading = false);
        return;
      }
      await locationSubscription?.cancel();
      locationSubscription = DeviceLocationService.locationStream().listen(
        _updateNearest,
        onError: (Object error) {
          if (!mounted) return;
          setState(() => errorMessage = error.toString());
        },
      );
      if (!mounted) return;
      setState(() {
        loading = false;
        detected = true;
        tracking = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool> _updateNearest(loc.LocationData position) async {
    final latitude = position.latitude;
    final longitude = position.longitude;
    if (!isInsideMalaysia(latitude, longitude)) {
      if (mounted) {
        setState(() {
          errorMessage = locationOutsideCoverageMessage(latitude, longitude);
          detected = false;
          nearest = [];
        });
      }
      return false;
    }
    final loaded = await StationRepository.instance.loadAll();
    final sorted =
    loaded
        .where((station) => station.latitude != 0 && station.longitude != 0)
        .map(
          (station) => station.withDistance(
        distanceKm(
          latitude,
          longitude,
          station.latitude,
          station.longitude,
        ),
      ),
    )
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    if (sorted.isEmpty || sorted.first.distance > 100) {
      if (mounted) {
        setState(() {
          errorMessage = locationOutsideCoverageMessage(latitude, longitude);
          detected = false;
          nearest = [];
        });
      }
      return false;
    }
    if (!mounted) return false;
    setState(() {
      currentPosition = position;
      nearest = sorted
          .where((station) => station.distance <= 25)
          .take(15)
          .toList();
    });
    return true;
  }

  Future<void> _stopTracking() async {
    await locationSubscription?.cancel();
    locationSubscription = null;
    if (!mounted) return;
    setState(() => tracking = false);
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _page,
    body: SafeArea(
      child: Column(
        children: [
          _SimpleHeader(
            title: 'Nearby Stations',
            subtitle: 'Detect your current location to see nearby stations',
            color: const Color(0xFF07835F),
          ),
          Expanded(
            child: detected
                ? ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  currentPosition == null
                      ? 'NEAREST TO YOU'
                      : 'NEAREST TO YOUR LIVE LOCATION',
                  style: const TextStyle(
                    color: Color(0xFF71839E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (currentPosition?.accuracy != null) ...[
                  Text(
                    'GPS accuracy: ±${currentPosition!.accuracy!.round()} m',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: tracking ? _stopTracking : _detectLocation,
                  icon: Icon(
                    tracking
                        ? Icons.stop_circle_outlined
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    tracking
                        ? 'Stop Location Tracking'
                        : 'Start Tracking',
                  ),
                ),
                const SizedBox(height: 12),
                StationListCard(items: nearest),
              ],
            )
                : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _SoftIcon(
                      Icons.location_on_outlined,
                      Color(0xFF059669),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Enable Location',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'We need your location to find the nearest transport stations',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF7C8DA6),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (errorMessage != null) ...[
                      Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                    ],
                    ElevatedButton.icon(
                      onPressed: loading ? null : _detectLocation,
                      icon: loading
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(
                        Icons.my_location,
                        color: Colors.white,
                      ),
                      label: Text(
                        loading
                            ? 'Loading Stations...'
                            : 'Detect My Location',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SimpleHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  const _SimpleHeader({
    required this.title,
    required this.subtitle,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: color,
    padding: const EdgeInsets.fromLTRB(14, 10, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          label: const Text('Back', style: TextStyle(color: Colors.white)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
}