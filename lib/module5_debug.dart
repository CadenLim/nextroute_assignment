import 'package:flutter/material.dart';
import 'package:nextroute_assignment/modules/analytics_notification/presentation/screens/vehicle_position_debug_screen.dart';

void main() {
  runApp(const Module5DebugApp());
}

class Module5DebugApp extends StatelessWidget {
  const Module5DebugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Module 5 Realtime Debug',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const VehiclePositionDebugScreen(),
    );
  }
}
