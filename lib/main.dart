import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/transport_data.dart';


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

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _modules = [
    const TransportDataScreen(),

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