import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nextroute_assignment/screens/transport_data.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/ai_crowd.dart';
import 'screens/analytics_centre.dart';
import 'screens/auth_screen.dart';
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

  late final List<Widget> _modules;

  @override
  void initState() {
    super.initState();
    _modules = [
      const JourneyPlanningScreen(),
      const TransportDataScreen(),
      const AiCrowdScreen(),
      const AnalyticsCentreScreen(),
      AuthGate(
        signedInScreen: PersonalTravelScreen(
          onOpenJourneyPlanning: () => _selectModule(0),
        ),
      ),
    ];
  }

  void _selectModule(int index) {
    if (!mounted || _currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _modules[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectModule,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.route),
            label: 'Journey',
          ),
          NavigationDestination(
            icon: const Icon(Icons.directions_transit),
            label: 'Stations',
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_alt),
            label: 'AI Crowd',
          ),
          NavigationDestination(
            icon: const Icon(Icons.analytics),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
