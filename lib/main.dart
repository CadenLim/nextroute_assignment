import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/ai_crowd.dart';
import 'screens/journey_planning.dart';
import 'screens/personal_travel.dart';
import 'screens/supabase_connection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SupabaseConfig.validate();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const NextRouteApp());
}

class NextRouteApp extends StatelessWidget {
  const NextRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NextRoute 2026',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          primary: const Color(0xFF2563EB),
          secondary: const Color(0xFF9333EA),
        ),
        textTheme: GoogleFonts.poppinsTextTheme(),
        useMaterial3: true,
      ),
      home: const MainScaffold(),
      routes: {
        '/supabase-check': (context) => const SupabaseConnectionScreen(),
      },
    );
  }
}

class PlaceholderModuleScreen extends StatelessWidget {
  const PlaceholderModuleScreen({super.key, required this.moduleName});

  final String moduleName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          moduleName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF1E3A8A),
      ),
      body: Center(
        child: Text(
          '$moduleName — coming soon',
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _modules = const [
    JourneyPlanningScreen(),
    PlaceholderModuleScreen(moduleName: 'Transport Data'),
    AiCrowdScreen(),
    PersonalTravelScreen(),
    PlaceholderModuleScreen(moduleName: 'Analytics Centre'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _modules[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route), label: 'Journey'),
          NavigationDestination(
            icon: Icon(Icons.directions_transit),
            label: 'Stations',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt),
            label: 'AI Crowd',
          ),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
          NavigationDestination(
            icon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }
}
