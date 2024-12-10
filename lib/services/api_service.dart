import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:dio/dio.dart';

class ApiService {
  //static const String baseUrl = 'http://10.0.2.2:8000/api';
  //static const String baseUrl = 'http://10.20.0.89:8000/api';
  //static const String baseUrl = 'http://127.0.0.1:8000/api';
  //static const String baseUrl = 'http://10.20.0.69:8000/api';
  static final String baseUrl = 'https://www.reloading-tracker.cz/api';

  static Future<bool> isOnline() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  static final CookieJar _cookieJar = CookieJar();

  // Přihlášení uživatele
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      final token = responseData['token'];
      final username = responseData['name']; // Extrahuj uživatelské jméno

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_token', token);
      await prefs.setString(
          'username', username); // Uložení uživatelského jména

      return responseData; // Vrať celou odpověď pro další zpracování
    } else {
      print('Login failed: ${response.body}');
      return {
        'status': 'error',
        'message': 'Login failed. Please check your credentials.',
      };
    }
  }

  // Obecná metoda GET pro API
  static Future<dynamic> _get(String endpoint) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    // Provádíme požadavek na API
    final response = await http.get(
      Uri.parse('$baseUrl/$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    // Logování odpovědi
    print('GET $endpoint: Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    // Zpracování odpovědi
    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);

        // Kontrola struktury dat
        if (data is Map<String, dynamic> || data is List<dynamic>) {
          return data; // Návrat validních dat
        } else {
          throw Exception('Unexpected response format: ${response.body}');
        }
      } catch (e) {
        print('Chyba při parsování JSON: $e');
        throw Exception('Failed to parse API response');
      }
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized: Invalid token or session expired');
    } else if (response.statusCode == 404) {
      throw Exception('Not Found: The endpoint $endpoint does not exist');
    } else {
      throw Exception('Failed to GET $endpoint: ${response.statusCode}');
    }
  }

  static Future<dynamic> get(String endpoint) async {
    return await _get(endpoint); // Zavolá privátní metodu _get
  }

  static Future<void> syncRequest(
      String endpoint, Map<String, dynamic> data) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('Token nebyl nalezen. Přihlas se.');
    }

    try {
      final dio = await _getDioInstance();

      // Remove any /api/ prefix and add it back once
      final cleanEndpoint =
          endpoint.replaceAll('/api/', '/').replaceAll('//', '/');
      final apiEndpoint =
          cleanEndpoint.startsWith('/') ? cleanEndpoint : '/$cleanEndpoint';

      print("DEBUG: Base URL: $baseUrl");
      print("DEBUG: Clean endpoint: $apiEndpoint");
      print("DEBUG: Full URL: $baseUrl$apiEndpoint");
      print("DEBUG: Headers: ${dio.options.headers}");

      if (endpoint.contains('/cartridges/') && endpoint.endsWith('/targets')) {
        final formData = FormData.fromMap({
          'image': await MultipartFile.fromFile(
            // Changed from 'photo' to 'image'
            data['photo_path'],
            filename: data['photo_path'].split('/').last,
          ),
          'note': data['notes'] ?? '',
          'weapon_id': data['weapon_id'].toString(),
          'distance': (data['distance'] ?? '').toString(),
          'created_at': DateTime.now().toIso8601String(),
        });

        print("DEBUG: FormData fields: ${formData.fields}");

        final response = await dio.post(
          '$baseUrl$apiEndpoint',
          data: formData,
          options: Options(
            validateStatus: (status) => status! < 500,
            contentType: 'multipart/form-data',
          ),
        );

        print("DEBUG: Raw response: ${response.data}");
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception(
              "Upload failed: ${response.statusCode}\nBody: ${response.data}");
        }
        return;
      }

      // Standardní požadavky
      if (data.containsKey('quantity')) {
        data['amount'] = data.remove('quantity');
      }

      print("Odesílám standardní požadavek s daty: $data");

      final response = await dio.post(
        '$baseUrl$apiEndpoint',
        data: data,
      );

      print("Response status: ${response.statusCode}");
      print("Response data: ${response.data}");

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
            "Chyba při volání $apiEndpoint: ${response.statusCode}");
      }

      if (response.data['success'] == false) {
        throw Exception("API chyba: ${response.data['message']}");
      }

      print("Požadavek úspěšně zpracován");
    } catch (e) {
      print("Chyba při volání API: $e");
      rethrow;
    }
  }

  static Future<List<dynamic>> getUserWeapons() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      print('Chyba: API token nebyl nalezen.');
      throw Exception('No token found. Please login.');
    }

    print('Používám API token: $token');
    print('Načítám všechny zbraně uživatele.');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/weapons'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('GET /weapons - Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final List<dynamic> weapons = jsonDecode(response.body);
          print('Počet načtených zbraní: ${weapons.length}');
          return weapons;
        } catch (e) {
          print('Chyba při zpracování JSON odpovědi: $e');
          throw Exception('Failed to parse weapons JSON.');
        }
      } else {
        print('Chyba při volání API: ${response.body}');
        throw Exception('Failed to load weapons: ${response.statusCode}');
      }
    } catch (e) {
      print('Chyba při komunikaci s API: $e');
      rethrow;
    }
  }

  static Future<Map<String, List<Map<String, dynamic>>>>
      getAllCartridges() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/cartridges'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    // Přidej logování odpovědi z API
    print('API Response (cartridges): ${response.body}');

    if (response.statusCode == 200) {
      List<dynamic> cartridges = jsonDecode(response.body) as List<dynamic>;

      // Přidej logování každého náboje
      cartridges.forEach((cartridge) {
        String name = cartridge['name'] ?? 'N/A';
        String type = cartridge['type'] ?? 'N/A';
        String caliberName = cartridge['caliber']?['name'] ?? 'N/A';

        print('Náboj: $name, Typ: $type, Kalibr: $caliberName');
      });

      // Rozdělení nábojů na tovární a přebíjené
      List<Map<String, dynamic>> factoryCartridges = cartridges
          .where((cartridge) => cartridge['type'] == 'factory')
          .map((cartridge) => Map<String, dynamic>.from(cartridge))
          .toList();

      List<Map<String, dynamic>> reloadCartridges = cartridges
          .where((cartridge) => cartridge['type'] == 'reload')
          .map((cartridge) => Map<String, dynamic>.from(cartridge))
          .toList();

      // Přidej logování počtu nábojů podle typů
      print('Factory cartridges: ${factoryCartridges.length}');
      print('Reload cartridges: ${reloadCartridges.length}');

      return {
        'factory': factoryCartridges,
        'reload': reloadCartridges,
      };
    } else {
      throw Exception('Failed to load cartridges: ${response.statusCode}');
    }
  }

  // Metoda pro odeslání požadavku (např. pro synchronizaci)
  static Future<bool> sendRequest(Map<String, dynamic> requestData) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData), // Odeslání dat ve formátu JSON
      );

      if (response.statusCode == 200) {
        // Pokud je odpověď úspěšná (status kód 200)
        return true;
      } else {
        // Pokud je odpověď neúspěšná
        return false;
      }
    } catch (e) {
      print('Chyba při odesílání požadavku: $e');
      return false;
    }
  }

  // Načtení kalibrů uživatele
  static Future<List<dynamic>> getCalibers() async {
    try {
      final calibers = await _get('user-calibers'); // Použití metody _get
      print('Loaded calibers: ${calibers.length}');
      return calibers as List<dynamic>;
    } catch (e) {
      print('Chyba při načítání kalibrů: $e');
      rethrow;
    }
  }

  // Načtení seznamu střelnic uživatele
  static Future<List<Map<String, dynamic>>> getUserRanges() async {
    try {
      // Kontrola připojení
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult == ConnectivityResult.none) {
        print('Offline mode - načítám střelnice z SQLite');
        return DatabaseHelper().getRanges();
      }

      // Získat token
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('api_token');

      if (token == null) {
        throw Exception('No token found. Please login.');
      }

      // Online - zkusit API s JSON header a auth token
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/ranges'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
      );

      if (response.statusCode == 200) {
        final List<Map<String, dynamic>> ranges =
            List<Map<String, dynamic>>.from(json.decode(response.body));

        // Uložit do SQLite pro offline použití
        await DatabaseHelper().saveRanges(ranges);

        return ranges;
      } else {
        throw Exception('Failed to load ranges');
      }
    } catch (e) {
      print('API Error: $e');
      // Fallback na SQLite při chybě
      return DatabaseHelper().getRanges();
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
    // Get token from SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/cartridges/$id'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token', // Add authentication token
      },
    );

    print('GET cartridge by ID ($id): Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

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
      body: jsonEncode(
          {'id': id, 'amount': quantityChange}), // Změněno na 'amount'
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

  static Future<Map<String, dynamic>> getCartridgeDetails(
      int cartridgeId) async {
    // Změněno: parametru 'id' na 'cartridgeId'
    try {
      final online = await isOnline(); // Kontrola připojení k internetu

      // Načítání dat podle dostupnosti internetu
      Map<String, dynamic>? cartridge;
      if (online) {
        // Online režim: Načti data z API
        cartridge = await _get('cartridges/$cartridgeId')
            as Map<String, dynamic>; // Změněno: z 'id' na 'cartridgeId'
        print('Načtená data z API: $cartridge');
      } else {
        // Offline režim: Načti data z SQLite
        print(
            'Načítám data z SQLite pro cartridge ID: $cartridgeId'); // Změněno: z 'id' na 'cartridgeId'
        cartridge = await DatabaseHelper().getDataById(
                'cartridges', cartridgeId) // Změněno: z 'id' na 'cartridgeId'
            as Map<String, dynamic>?;
        if (cartridge == null) {
          throw Exception('Cartridge not found in offline database');
        }
        print('Načtená data z SQLite: $cartridge');
      }

      // Validace dat
      if (!cartridge.containsKey('type') || cartridge['type'] == null) {
        print('Upozornění: Chybějící typ u cartridge: $cartridge');
        cartridge['type'] = 'unknown'; // Volitelná výchozí hodnota
      }

      return cartridge;
    } catch (e) {
      print('Chyba při načítání cartridge: $e');
      rethrow; // Opětovné vyhození výjimky
    }
  }

  // Navýšení skladové zásoby náboje
  static Future<Map<String, dynamic>> increaseCartridge(
      int id, int quantity) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      throw Exception('No token found. Please login.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/cartridges/$id/update-stock'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'amount': quantity}), // Změněno na 'amount'
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to increase stock by ID: ${response.statusCode}');
    }
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

  //vytvoření továrního náboje
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
        'Accept':
            'application/json', // Doplněná hlavička pro očekávání JSON odpovědi
        'Authorization': 'Bearer $token',
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
      Uri.parse('$baseUrl/cartridges/barcode/$barcode/update-stock'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Přidání tokenu do hlavičky
      },
      body: jsonEncode({'amount': quantity}), // Změněno na 'amount'
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
          'Failed to increase stock by barcode: ${response.statusCode}');
    }
  }

  static Future<void> increaseStock({
    int? cartridgeId,
    String? barcode,
    required int quantity,
  }) async {
    if (barcode != null && barcode.isNotEmpty) {
      // Pokud existuje barcode, použij jej pro navýšení zásob
      await increaseStockByBarcode(barcode, quantity);
    } else if (cartridgeId != null) {
      // Pokud barcode není, použij cartridgeId
      await increaseCartridge(cartridgeId, quantity);
    } else {
      // Pokud není ani barcode, ani cartridgeId, vyhoď výjimku
      throw Exception('Neither barcode nor cartridge ID provided');
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
  static Future<List<Map<String, dynamic>>> getUserWeaponsByCaliber(
      int caliberId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('api_token');

    if (token == null) {
      print('Chyba: API token nebyl nalezen.');
      throw Exception('No token found. Please login.');
    }

    print('Používám API token: $token');
    print('Načítám zbraně pro kalibr ID: $caliberId');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/weapons/by-caliber/$caliberId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print(
          'GET /weapons/by-caliber/$caliberId - Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final List<dynamic> weapons = jsonDecode(response.body);
          print('Počet načtených zbraní: ${weapons.length}');
          return weapons.cast<Map<String, dynamic>>();
        } catch (e) {
          print('Chyba při zpracování JSON odpovědi: $e');
          throw Exception('Failed to parse weapons JSON.');
        }
      } else {
        print('Chyba při volání API: ${response.body}');
        throw Exception(
            'Failed to load weapons by caliber: ${response.statusCode}');
      }
    } catch (e) {
      print('Chyba při komunikaci s API: $e');
      rethrow;
    }
  }

  static Future<Dio> _getDioInstance() async {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'multipart/form-data',
      },
    ));

    // Přidání auth tokenu pokud existuje
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }

    return dio;
  }

  static Future<void> uploadTargetPhoto(Map<String, dynamic> data) async {
    try {
      final dio = await _getDioInstance();

      // Vytvoření FormData pro upload souboru
      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(
          data['photo_path'],
          filename: data['photo_path'].split('/').last,
        ),
        'note': data['note'],
        'created_at': data['created_at'],
      });

      await dio.post(
        '$baseUrl/target-photos',
        data: formData,
      );
    } catch (e) {
      print('Chyba při nahrávání fotky terče: $e');
      throw e;
    }
  }

  // Načtení aktivit uživatele
  static Future<List<dynamic>> getUserActivities() async {
    try {
      final activities = await _get('activities'); // Použití metody _get
      print('Loaded activities: ${activities.length}');
      return activities as List<dynamic>;
    } catch (e) {
      print('Chyba při načítání aktivit: $e');
      rethrow;
    }
  }
}
