import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

class ApiService {
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
}
