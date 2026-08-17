import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/presentation/screens/gtfs_static_debug_screen.dart';
import 'package:nextroute_assignment/modules/analytics_notification/presentation/screens/notification_centre_screen.dart';
import 'package:nextroute_assignment/modules/analytics_notification/presentation/screens/realtime_gps_stop_localisation_debug_screen.dart';
import 'package:nextroute_assignment/modules/analytics_notification/presentation/screens/realtime_static_match_debug_screen.dart';
import 'package:nextroute_assignment/modules/analytics_notification/presentation/screens/realtime_stop_context_debug_screen.dart';
import 'package:nextroute_assignment/modules/analytics_notification/presentation/screens/service_analytics_screen.dart';

void main() {
  runApp(const Module5DebugApp());
}

class Module5DebugApp extends StatelessWidget {
  const Module5DebugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Module 5 Debug',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const Module5DebugHome(),
    );
  }
}

class Module5DebugHome extends StatelessWidget {
  const Module5DebugHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Module 5 Debug')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Service Analytics'),
              subtitle: const Text('View the Phase 2 realtime analytics.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const ServiceAnalyticsScreen(),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notification Centre'),
              subtitle: const Text(
                'View local notifications and app-generated alerts.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const NotificationCentreScreen(),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('GTFS Static Schedule'),
              subtitle: const Text(
                'Download and inspect the Rapid Bus KL schedule archive.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const GtfsStaticDebugScreen(),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.compare_arrows),
              title: const Text('Realtime ↔ Static Match Audit'),
              subtitle: const Text(
                'Audit exact trip matches without calculating delay.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        const RealtimeStaticMatchDebugScreen(),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.pin_drop_outlined),
              title: const Text('Realtime Stop Context Audit'),
              subtitle: const Text(
                'Audit current stop-sequence context without calculating delay.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        const RealtimeStopContextDebugScreen(),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.gps_fixed),
              title: const Text('GPS Stop Localisation Audit'),
              subtitle: const Text(
                'Estimate the nearest scheduled stop without calculating delay.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        const RealtimeGpsStopLocalisationDebugScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
