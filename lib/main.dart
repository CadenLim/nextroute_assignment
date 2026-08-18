import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/ai_crowd.dart';

void main() {
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
  final List<Widget> _modules = const [
    PlaceholderModuleScreen(moduleName: 'Journey Planning'),   // Module 1 — teammate
    PlaceholderModuleScreen(moduleName: 'Transport Data'),     // Module 2 — teammate
    AiCrowdScreen(),                                           // Module 3 — you
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
