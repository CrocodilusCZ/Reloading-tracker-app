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
      await prefs.setString(
          'user_nickname', responseData['name']); // Ukládáme nick
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

  // Vytvoření nového továrního náboje
  static Future<Map<String, dynamic>> createFactoryCartridge(
      Map<String, dynamic> cartridgeData) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/cartridges/factory'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Přidání tokenu do hlavičky
      },
      body: jsonEncode(cartridgeData),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('Error: ${response.body}');
      throw Exception(
          'Failed to create factory cartridge: ${response.statusCode}');
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

  // Načtení přebíjených nábojů uživatele
  static Future<List<dynamic>> getReloadCartridges() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/cartridges/reload'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Token přidaný do hlavičky
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to load reload cartridges');
    }
  }

  // Získání seznamu všech nábojů a následné rozdělení na tovární a přebíjené
  static Future<Map<String, List<Map<String, dynamic>>>>
      getAllCartridges() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/cartridges'), // Načtení všech nábojů
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> cartridges = jsonDecode(response.body) as List<dynamic>;

      // Přetypování seznamu dynamických prvků na seznam map
      List<Map<String, dynamic>> factoryCartridges = cartridges
          .where((cartridge) => cartridge['type'] == 'factory')
          .map((cartridge) => Map<String, dynamic>.from(cartridge))
          .toList();

      List<Map<String, dynamic>> reloadCartridges = cartridges
          .where((cartridge) => cartridge['type'] == 'reload')
          .map((cartridge) => Map<String, dynamic>.from(cartridge))
          .toList();

      // Vrácení jako mapy se dvěma seznamy
      return {
        'factory': factoryCartridges,
        'reload': reloadCartridges,
      };
    } else {
      throw Exception('Failed to load cartridges');
    }
  }

  // Metoda pro získání skladových zásob komponent
  static Future<Map<String, List<Map<String, dynamic>>>>
      getInventoryComponents() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/inventory-components'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Použití tokenu
      },
    );

    // Logování celého těla odpovědi
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      // Zpracování odpovědi z JSON formátu
      Map<String, dynamic> responseData = jsonDecode(response.body);

      // Specifické logování pro sekci brasses (nábojnice)
      List<Map<String, dynamic>> brasses =
          List<Map<String, dynamic>>.from(responseData['brasses']);
      print('Brasses count: ${brasses.length}');

      brasses.forEach((brass) {
        print(
            'Brass name: ${brass['name']}, Stock: ${brass['stock_quantity']}');

        if (brass['caliber'] != null) {
          print(
              'Caliber for brass ${brass['name']}: ${brass['caliber']['name']}');
        } else {
          print('Caliber is missing for brass ${brass['name']}');
        }
      });

      // Přetypování každé části (bullets, powders, primers, brasses) na List<Map<String, dynamic>>
      return {
        'bullets': List<Map<String, dynamic>>.from(responseData['bullets']),
        'powders': List<Map<String, dynamic>>.from(responseData['powders']),
        'primers': List<Map<String, dynamic>>.from(responseData['primers']),
        'brasses': brasses,
      };
    } else {
      throw Exception('Failed to load inventory components');
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
          'Accept': 'application/json', // Přidání hlavičky Accept
          'Authorization': 'Bearer $token', // Přidání tokenu pro ověření
        },
        body: jsonEncode(shootingLogData),
      );

      // Logování odpovědi z API
      print('HTTP Response Code: ${response.statusCode}');
      print('HTTP Response Body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);

        if (jsonResponse.containsKey('success') &&
            jsonResponse['success'] == true) {
          return jsonResponse;
        } else {
          throw Exception(
              'Failed to create shooting log: ${jsonResponse['error']}');
        }
      } else {
        throw Exception('Failed to create shooting log: ${response.body}');
      }
    } catch (e) {
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

  // Načtení aktivit uživatele
  static Future<List<dynamic>> getUserActivities() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token'); // Získání tokenu

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/activities'),
      headers: {
        'Authorization': 'Bearer $token', // Přidání tokenu do hlavičky
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)
          as List<dynamic>; // Očekáváme seznam aktivit
    } else {
      throw Exception('Chyba při načítání aktivit: ${response.statusCode}');
    }
  }
}
