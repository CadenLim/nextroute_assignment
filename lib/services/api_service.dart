import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

class ApiService {
  // Module 1: Local GTFS Static Data
  Future<List<String>> getLocalStops() async {
    try {
      final String response = await rootBundle.loadString('assets/stops.txt');
      return response.split('\n').skip(1).take(5).toList();
    } catch (e) {
      return ['Error loading local stops.txt: Ensure assets are configured.'];
    }
  }

  // Module 2: Live GTFS Realtime
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

  // Module 3: Crowd Intelligence
  Future<String> getRidershipData() async {
    try {
      final String response = await rootBundle.loadString('assets/ridership.csv');
      final firstRow = response.split('\n').skip(1).first;
      return 'Local CSV Data Detected: $firstRow';
    } catch (e) {
      final response = await http.get(Uri.parse('https://data.gov.my/data-catalogue/ridership_od_rapidrail_daily'));
      return 'Live API Status: ${response.statusCode}';
    }
  }

  // Module 4 & 5: Analytics Dashboards
  Future<String> getAnalyticsMetadata() async {
    try {
      final response = await http.get(Uri.parse('https://data.gov.my/dashboard/public-transportation'));
      return response.statusCode == 200 ? 'Analytics Synced with data.gov.my' : 'Sync Failed';
    } catch (e) {
      return 'Connection Error';
    }
  }
}