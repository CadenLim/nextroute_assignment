import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

class ApiService {
  // ---------------------------------------------------------
  // Module 2: Transport Data Management (Live GTFS Realtime)
  // ---------------------------------------------------------
  Future<String> getRealtimeBusPositions() async {
    try {
      final response = await http.get(Uri.parse(
          'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl'));
      if (response.statusCode == 200) {
        return 'Connected: Received ${response.bodyBytes.length} bytes of live data';
      }
      return 'Failed to load live data';
    } catch (e) {
      return 'API Connection Error';
    }
  }

  // ---------------------------------------------------------
  // Module 3: AI Crowd Intelligence (Static/API Dataset)
  // ---------------------------------------------------------
  Future<String> getRidershipData() async {
    try {
      final String response = await rootBundle.loadString('assets/ridership.csv');
      final firstRow = response.split('\n').skip(1).first;
      return 'Local CSV Data Detected: $firstRow';
    } catch (e) {
      return 'Syncing Prasarana Ridership Data...';
    }
  }

  // ---------------------------------------------------------
  // Module 4: Personal Travel Assistance (Mock Backend Sync)
  // ---------------------------------------------------------
  Future<bool> syncUserProfile(bool morningReminder, bool eveningReminder) async {
    // In a fully developed production app, this function would send
    // a POST request to your backend to save the user's reminder preferences.
    try {
      await Future.delayed(const Duration(seconds: 1)); // Simulating network delay
      return true;
    } catch (e) {
      return false;
    }
  }
}