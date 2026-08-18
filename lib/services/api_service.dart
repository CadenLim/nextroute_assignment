import 'package:http/http.dart' as http;

class ApiService {
    try {
      final response = await http.get(Uri.parse(
          'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl'));
      if (response.statusCode == 200) {
      }
    } catch (e) {
    }
  }
}