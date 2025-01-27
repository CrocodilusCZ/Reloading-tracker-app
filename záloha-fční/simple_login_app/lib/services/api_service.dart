import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cookie_jar/cookie_jar.dart';

class ApiService {
  static const String baseUrl = 'http://192.168.0.21/api.php';
  static final CookieJar _cookieJar = CookieJar();

  // Přihlášení uživatele
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final cookiesHeader = response.headers['set-cookie'];
      if (cookiesHeader != null) {
        final cookies = cookiesHeader.split(',').map((cookie) {
          final parts = cookie.split(';');
          final keyValue = parts[0].split('=');
          return Cookie(keyValue[0], keyValue[1]);
        }).toList();
        _cookieJar.saveFromResponse(Uri.parse(baseUrl), cookies);
      }
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to login: ${response.body}');
    }
  }

  // Získání informací o náboji podle ID
  static Future<Map<String, dynamic>> getCartridgeById(int id) async {
    final cookies = await _cookieJar.loadForRequest(Uri.parse(baseUrl));
    final response = await http.get(
      Uri.parse('$baseUrl/cartridges/$id'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': cookies.map((c) => '${c.name}=${c.value}').join('; ')
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data;
    } else {
      throw Exception('Failed to get cartridge by ID: ${response.statusCode}');
    }
  }

  // Aktualizace skladové zásoby náboje (zvýšení nebo snížení)
  static Future<Map<String, dynamic>> updateCartridgeQuantity(int id, int quantityChange) async {
    final cookies = await _cookieJar.loadForRequest(Uri.parse(baseUrl));
    final response = await http.post(
      Uri.parse('$baseUrl/cartridges/update'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': cookies.map((c) => '${c.name}=${c.value}').join('; ')
      },
      body: jsonEncode({'id': id, 'quantity': quantityChange}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update cartridge quantity: ${response.statusCode}');
    }
  }

  // Získání seznamu oblíbených nábojů
  static Future<List<dynamic>> getFavoriteCartridges() async {
    final cookies = await _cookieJar.loadForRequest(Uri.parse(baseUrl));
    final response = await http.get(
      Uri.parse('$baseUrl/favorite_cartridges'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': cookies.map((c) => '${c.name}=${c.value}').join('; ')
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('API Response: $data');

      if (data['status'] == 'success' && data.containsKey('cartridges')) {
        return data['cartridges'] as List<dynamic>;
      } else {
        throw Exception('Invalid data format: Expected a map with a `cartridges` key');
      }
    } else {
      throw Exception('Failed to load favorite cartridges: ${response.statusCode}');
    }
  }

  // Navýšení skladové zásoby náboje
  static Future<Map<String, dynamic>> increaseCartridge(int id, int quantity) async {
    return await updateCartridgeQuantity(id, quantity);
  }

  // Snížení skladové zásoby náboje
  static Future<Map<String, dynamic>> decreaseCartridge(int id, int quantity) async {
    return await updateCartridgeQuantity(id, -quantity);
  }
}
