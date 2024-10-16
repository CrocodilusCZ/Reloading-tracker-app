import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://www.reloading-tracker.cz/api';

  static final CookieJar _cookieJar = CookieJar();

  // Přihlášení uživatele
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'email': email, 'password': password}), // Změněno na 'email'
    );

    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      final token = responseData['token'];
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_token', token);
      return responseData;
    } else {
      print('Login failed: ${response.body}');
      return {
        'status': 'error',
        'message': 'Login failed. Please check your credentials.',
      };
    }
  }

  //Funkce pro shooting log
  static Future<Map<String, dynamic>> addShootingLog(String code) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final url = Uri.parse('$baseUrl/shooting-log');
    final response = await http.post(
      url,
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer $token', // Přidání tokenu do hlavičky
      },
      body: jsonEncode(<String, String>{
        'code': code,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to add shooting log');
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
  static Future<Map<String, dynamic>> updateCartridgeQuantity(
      int id, int quantityChange) async {
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
      throw Exception(
          'Failed to update cartridge quantity: ${response.statusCode}');
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
        throw Exception(
            'Invalid data format: Expected a map with a `cartridges` key');
      }
    } else {
      throw Exception(
          'Failed to load favorite cartridges: ${response.statusCode}');
    }
  }

  // Navýšení skladové zásoby náboje
  static Future<Map<String, dynamic>> increaseCartridge(
      int id, int quantity) async {
    return await updateCartridgeQuantity(id, quantity);
  }

  // Snížení skladové zásoby náboje
  static Future<Map<String, dynamic>> decreaseCartridge(
      int id, int quantity) async {
    return await updateCartridgeQuantity(id, -quantity);
  }

  // Ověření existence čárového kódu
  static Future<Map<String, dynamic>> checkBarcode(String barcode) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/cartridges/check-barcode/$barcode'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Přidání tokenu do hlavičky
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to check barcode: ${response.statusCode}');
    }
  }

// Přiřazení čárového kódu ke konkrétnímu náboji
  static Future<Map<String, dynamic>> assignBarcode(
      int cartridgeId, String barcode) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/cartridges/$cartridgeId/assign-barcode'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Přidání tokenu do hlavičky
      },
      body: jsonEncode({'barcode': barcode}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to assign barcode: ${response.statusCode}');
    }
  }

  // Načtení továrních nábojů uživatele
  static Future<List<dynamic>> getFactoryCartridges() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/cartridges/factory'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Token přidaný do hlavičky
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to load factory cartridges');
    }
  }

// Navýšení skladové zásoby náboje pomocí čárového kódu
  static Future<Map<String, dynamic>> increaseStockByBarcode(
      String barcode, int quantity) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/cartridges/increase-stock'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Přidání tokenu do hlavičky
      },
      body: jsonEncode({'barcode': barcode, 'quantity': quantity}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
          'Failed to increase stock by barcode: ${response.statusCode}');
    }
  }

  // Nová metoda - vytvoření záznamu střeleckého deníku s logováním
  static Future<Map<String, dynamic>> createShootingLog(
      Map<String, dynamic> shootingLogData) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    // Logování dat, která se budou odesílat
    print('Odesílání dat na API (createShootingLog): $shootingLogData');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/shooting-logs'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token', // Přidání tokenu pro ověření
        },
        body: jsonEncode(shootingLogData),
      );

      // Logování odpovědi z API
      print('HTTP Response Code: ${response.statusCode}');
      print('HTTP Response Body: ${response.body}');

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to create shooting log: ${response.body}');
      }
    } catch (e) {
      // Logování chyby v případě neúspěšného pokusu
      print('Chyba při vytváření záznamu ve střeleckém deníku: $e');
      throw Exception('Chyba při vytváření záznamu ve střeleckém deníku: $e');
    }
  }

  // Volání API pro získání zbraní uživatele podle kalibru
  static Future<List<dynamic>> getUserWeaponsByCaliber(int caliberId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    // Debug výpis pro kontrolu tokenu
    print('Token: $token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    // Oprava URL, pokud používáš endpoint by-caliber
    final response = await http.get(
      Uri.parse('$baseUrl/weapons/by-caliber/$caliberId'), // Opravená URL
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Přidání tokenu pro ověření
      },
    );

    // Debug výpis pro kontrolu status kódu a odpovědi
    print('Status code: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception(
          'Failed to load user weapons. Status: ${response.statusCode}');
    }
  }
}
