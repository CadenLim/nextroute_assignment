import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


import 'screens/ai_crowd.dart';
import 'screens/journey_planning.dart'; // Added the missing semicolon here!

Future<void> main() async {
  // Ensure Flutter bindings are ready before initializing Supabase
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://kcsizfxjgbdrnkfcukun.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtjc2l6ZnhqZ2Jkcm5rZmN1a3VuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyOTMwMjMsImV4cCI6MjEwMjg2OTAyM30.GzTxmlIjKYvXHNV_c4oJ7mlVyczNhRk99WOZy9m1IjU',
  );

  runApp(const NextRouteApp());
}



class NextRouteApp extends StatelessWidget {
  const NextRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NextRoute 2026',
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
      debugShowCheckedModeBanner: false,
    );
  }
}

// Simple placeholder for modules that haven't been built yet by teammates.
// Swap each of these out for the real screen as your team finishes them.
class PlaceholderModuleScreen extends StatelessWidget {
  final String moduleName;
  const PlaceholderModuleScreen({super.key, required this.moduleName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(moduleName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  // Order MUST match the NavigationDestinations below:
  // 0 Journey, 1 Stations, 2 AI Crowd, 3 Profile, 4 Analytics

  // NOTE: If your JourneyPlanningScreen does not use a 'const' constructor,
  // you may need to remove the word 'const' right below here.
  final List<Widget> _modules = const [
    JourneyPlanningScreen(),                                   // Module 1 — you
    PlaceholderModuleScreen(moduleName: 'Transport Data'),     // Module 2 — teammate
    AiCrowdScreen(),                                           // Module 3 — friend
    PlaceholderModuleScreen(moduleName: 'Personal Assistant'), // Module 4 — teammate
    PlaceholderModuleScreen(moduleName: 'Analytics Centre'),   // Module 5 — teammate
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _modules[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route), label: 'Journey'),
          NavigationDestination(icon: Icon(Icons.directions_transit), label: 'Stations'),
          NavigationDestination(icon: Icon(Icons.people_alt), label: 'AI Crowd'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'Analytics'),
        ],
      ),
    );
  }
}