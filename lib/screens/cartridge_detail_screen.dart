import 'package:flutter/material.dart';
import 'package:shooting_companion/main.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shooting_companion/screens/barcode_scanner_screen.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/services/weapon_service.dart';

Future<bool> isOnline() async {
  var connectivityResult = await (Connectivity().checkConnectivity());
  return connectivityResult != ConnectivityResult.none;
}

class SQLiteService {
  static Future<List<Map<String, dynamic>>> getWeaponsByCaliber(
      int caliberId) async {
    final db = await DatabaseHelper().database;

    print('Debug: Připojeno k SQLite databázi');

    // Kontrola platnosti caliberId
    if (caliberId <= 0) {
      print('Chyba: Neplatný caliberId: $caliberId');
      return [];
    }

    try {
      print('Debug: Provádím dotaz pro caliberId=$caliberId');
      final result = await db.rawQuery('''
    SELECT 
      weapons.id AS weapon_id,
      weapons.name AS weapon_name,
      calibers.id AS caliber_id,
      calibers.name AS caliber_name
    FROM weapons
    JOIN weapon_calibers ON weapons.id = weapon_calibers.weapon_id
    JOIN calibers ON weapon_calibers.caliber_id = calibers.id
    WHERE calibers.id = ?
  ''', [caliberId]);

      print('Debug: Výsledky dotazu na zbraně: $result');

      if (result.isEmpty) {
        print('Debug: Výsledek dotazu je prázdný pro caliberId=$caliberId');

        // Diagnostika tabulek
        print('Debug: Kontroluji obsah relevantních tabulek...');
        final weaponsTable = await db.rawQuery('SELECT * FROM weapons');
        print('Debug: Obsah tabulky weapons: $weaponsTable');

        final calibersTable = await db.rawQuery('SELECT * FROM calibers');
        print('Debug: Obsah tabulky calibers: $calibersTable');

        final weaponCalibersTable =
            await db.rawQuery('SELECT * FROM weapon_calibers');
        print('Debug: Obsah tabulky weapon_calibers: $weaponCalibersTable');

        print('Debug: Ověř, zda data odpovídají caliberId=$caliberId');
      }

      return result;
    } catch (e, stackTrace) {
      print('Error: Chyba při provádění dotazu: $e');
      print('Debug: StackTrace: $stackTrace');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getUserActivities() async {
    final db = await DatabaseHelper().database;
    return await db.query('activities');
  }

  // Přidání metody pro načtení cartridge podle ID
  static Future<Map<String, dynamic>?> getCartridgeById(int id) async {
    final db = await DatabaseHelper().database; // Otevře SQLite databázi
    final result = await db.query(
      'cartridges', // Název tabulky
      where: 'id = ?', // Filtr na základě ID
      whereArgs: [id], // Hodnota pro nahrazení otazníku
    );

    if (result.isNotEmpty) {
      print('Debug: Cartridge nalezeno: ${result.first}');
      return result.first; // Vrátí první nalezený záznam
    } else {
      print('Debug: Cartridge s ID $id nenalezeno.');
      return null; // Vrátí null, pokud žádný záznam neexistuje
    }
  }
}

class CartridgeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> cartridge;

  const CartridgeDetailScreen({Key? key, required this.cartridge})
      : super(key: key);

  @override
  _CartridgeDetailScreenState createState() => _CartridgeDetailScreenState();
}

class _CartridgeDetailScreenState extends State<CartridgeDetailScreen> {
  Map<String, dynamic>? cartridgeDetails;
  List<dynamic> userWeapons = [];
  List<dynamic> userActivities = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    // Debug: Výpis dat náboje při inicializaci
    print('Cartridge Data při inicializaci: ${widget.cartridge}');

    _fetchData();
  }

  Future<void> _fetchData() async {
    final startTime = DateTime.now();
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();

    print('\n🔍 [Session: $sessionId] === ZAČÁTEK NAČÍTÁNÍ DAT ===');
    print('⏱️ Čas začátku: $startTime');

    setState(() {
      isLoading = true;
    });

    try {
      final cartridgeId = widget.cartridge['id'];
      print('📦 Input náboj ID: $cartridgeId');
      print('📄 Vstupní data:\n${_formatMap(widget.cartridge)}');

      final caliberId = widget.cartridge['caliber_id'];
      print('🎯 Caliber ID: $caliberId');

      bool online = await isOnline();
      print('🌐 Stav připojení: ${online ? "✅ ONLINE" : "❌ OFFLINE"}');

      if (online) {
        try {
          print('\n📡 === NAČÍTÁNÍ Z API ===');
          final details = await ApiService.getCartridgeDetails(cartridgeId);
          print('📥 API Response:\n${_formatMap(details)}');

          if (details != null && details.isNotEmpty) {
            final returnedCaliberId = details['caliber_id'];
            if (returnedCaliberId == null) {
              print('⚠️ CHYBA: Chybí caliber_id v API datech');
              return;
            }
            await _fetchOnlineData(returnedCaliberId, details);
            print('✅ === ONLINE DATA NAČTENA ===');
            return;
          }
          print('⚠️ VAROVÁNÍ: Prázdná API odpověď');
        } catch (apiError) {
          print('❌ === CHYBA API ===\n$apiError');
        }
      }

      print('\n💾 === PŘEPNUTÍ NA SQLITE ===');
      print('📄 Offline vstupní data:\n${_formatMap(widget.cartridge)}');
      await _fetchOfflineData(caliberId, widget.cartridge);
      print('✅ === OFFLINE DATA NAČTENA ===');
    } catch (e) {
      print('❌ === KRITICKÁ CHYBA ===\n$e');
    } finally {
      setState(() {
        isLoading = false;
      });
      final endTime = DateTime.now();
      print(
          '\n⏱️ Doba zpracování: ${endTime.difference(startTime).inMilliseconds}ms');
      print('✅ [Session: $sessionId] === NAČÍTÁNÍ DOKONČENO ===\n');
    }
  }

// Helper pro formátování Map
  String _formatMap(Map<String, dynamic>? map) {
    if (map == null) return 'null';
    return map.entries.map((e) => '  ${e.key}: ${e.value}').join('\n');
  }

  Future<void> _fetchOnlineData(
      int caliberId, Map<String, dynamic> details) async {
    try {
      print('Debug: Načítám zbraně a aktivity online...');
      print('Debug: Původní data náboje: $details');

      if (caliberId == 0 || caliberId == null) {
        caliberId = details['caliber_id'];
        print('Debug: Použitý caliber_id z details: $caliberId');
      }

      // Načtení detailů náboje z API
      final apiCartridgeDetails =
          await ApiService.getCartridgeDetails(details['id']);
      print('Debug: Data z API: $apiCartridgeDetails');

      // Sloučení dat z API s původními daty pro zachování vnořených objektů
      final standardizedDetails = {
        ...details,
        ...apiCartridgeDetails,
        'caliber': details['caliber'], // Zachovat původní caliber objekt
        'bullet': details['bullet'], // Zachovat původní bullet objekt
        'powder': details['powder'], // Zachovat původní powder objekt
        // Výrobce zobrazovat pouze pro tovární náboje
        'manufacturer':
            details['type'] == 'factory' ? details['manufacturer'] : null,
      };

      final weaponsResponse =
          await WeaponService.fetchWeaponsByCaliber(caliberId);
      final standardizedWeapons = weaponsResponse
              ?.map((weapon) =>
                  {'weapon_id': weapon['id'], 'weapon_name': weapon['name']})
              .toList() ??
          [];

      final activitiesResponse = await ApiService.getUserActivities();

      print('Debug: Finální standardizovaná data: $standardizedDetails');

      setState(() {
        cartridgeDetails = standardizedDetails;
        userWeapons = standardizedWeapons;
        userActivities = activitiesResponse;
      });
    } catch (e) {
      print('Error: Chyba při načítání online dat: $e');
      await _fetchOfflineData(caliberId, details);
    }
  }

  Future<void> _fetchOfflineData(
      int caliberId, Map<String, dynamic> details) async {
    try {
      print('Debug: Začátek _fetchOfflineData');
      print('Debug: Původní data: $details');

      final db = await DatabaseHelper().database;

      // Debug - vypsat všechny sloupce v tabulce
      final tableInfo = await db.rawQuery("PRAGMA table_info('cartridges')");
      print('Debug: Struktura tabulky cartridges:');
      for (var column in tableInfo) {
        print('Sloupec: ${column['name']}');
      }

      final cartridgeData = await db.rawQuery('''
      SELECT 
        c.*,
        cal.name AS caliber_name
      FROM cartridges c
      LEFT JOIN calibers cal ON c.caliber_id = cal.id
      WHERE c.id = ?
    ''', [details['id']]);

      print('Debug: Načtená data z DB: ${cartridgeData.first}');

      if (cartridgeData.isNotEmpty) {
        final data = cartridgeData.first;
        details = {
          ...details,
          'caliber': {
            'id': data['caliber_id'],
            'name': data['caliber_name'],
          },
          'bullet': {
            'name': data['bullet_name'] ?? 'Neznámý',
            'weight_grains': data['bullet_weight_grains'], // Přidáno
          },
          'powder': {
            'name': data['powder_name'] ?? 'Neznámý',
            'weight': data['powder_weight'],
          },
          'primer': {
            'name': data['primer_name'] ?? 'Neznámý',
          },
          'powder_weight': data['powder_weight'], // Přidáno na root úroveň
          'oal': data['oal'],
          'velocity_ms': data['velocity_ms'],
          'standard_deviation': data['standard_deviation'], // Přidáno
          'manufacturer': data['manufacturer'],
          'price': data['price'],
          'stock_quantity': data['stock_quantity'],
        };
      }

      final localWeapons = await SQLiteService.getWeaponsByCaliber(caliberId);
      final localActivities = await SQLiteService.getUserActivities();

      setState(() {
        cartridgeDetails = details;
        userWeapons = localWeapons;
        userActivities = localActivities;
      });

      print('Debug: Finální offline data: $details');
    } catch (e) {
      print('Error: Chyba při načítání offline dat: $e');
      print('Error stack trace: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartridge = cartridgeDetails ??
        widget.cartridge; // Použij cartridgeDetails, pokud jsou dostupné
    final isReloaded = cartridge['type'] == 'reload'; // Kontrola typu náboje

    return Scaffold(
        appBar: AppBar(
          title: Text(cartridge['name'] ?? 'Detail Náboje'),
          backgroundColor: Colors.blueGrey,
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _fetchData, // Zavolá _fetchData při tažení dolů
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Název náboje
                      Text(
                        cartridge['name'] ?? 'Neznámý náboj',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sekce: Kalibr a výrobce
                      _buildSectionTitle('Kalibr a Výrobce'),
                      _buildStripedInfoRow('Kalibr',
                          cartridge['caliber']?['name'] ?? 'Neznámý', 0),
                      if (cartridge['type'] == 'factory') // Přidaná podmínka
                        _buildStripedInfoRow('Výrobce',
                            cartridge['manufacturer'] ?? 'Neznámý', 1),

                      const SizedBox(height: 16),

                      // Sekce: Cena a dostupnost
                      _buildSectionTitle('Cena a Dostupnost'),
                      _buildStripedInfoRow(
                          'Cena', '${cartridge['price'] ?? 'Neznámá'} Kč', 2),
                      _buildStripedInfoRow('Sklad',
                          '${cartridge['stock_quantity'] ?? 'Neznámý'} ks', 3),

                      // Sekce: Barcode
                      _buildSectionTitle('Čárový kód'),
                      GestureDetector(
                        onTap: () {
                          if (cartridge['barcode'] == null ||
                              cartridge['barcode'].isEmpty) {
                            // Spuštění obrazovky pro skenování čárového kódu
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BarcodeScannerScreen(
                                  source: 'cartridge_detail',
                                  currentCartridge: widget
                                      .cartridge, // Use widget.cartridge instead
                                ),
                              ),
                            );
                          }
                        },
                        child: _buildStripedInfoRow(
                          'Čárový kód',
                          cartridge['barcode'] != null &&
                                  cartridge['barcode'].isNotEmpty
                              ? 'Přidělen'
                              : 'Nepřidělen - přidělit?',
                          4,
                          icon: cartridge['barcode'] != null &&
                                  cartridge['barcode'].isNotEmpty
                              ? const Icon(Icons.check, color: Colors.green)
                              : const Icon(Icons.qr_code, color: Colors.blue),
                        ),
                      ),

                      if (isReloaded) ...[
                        const SizedBox(height: 16),

                        // Sekce: Technické informace (pouze pro přebíjené náboje)
                        _buildSectionTitle('Technické Informace'),
                        _buildStripedInfoRow(
                          'Střela',
                          cartridge['bullet'] != null
                              ? '${cartridge['bullet']['name']} (${cartridge['bullet']['weight_grains']} gr)'
                              : 'Neznámá',
                          5,
                        ),
                        _buildStripedInfoRow(
                          'Prach',
                          cartridge['powder'] != null
                              ? cartridge['powder']['name']
                              : 'Neznámý',
                          6,
                        ),
                        _buildStripedInfoRow(
                          'Navážka prachu',
                          cartridge['powder_weight'] != null
                              ? '${cartridge['powder_weight']} gr'
                              : 'Neznámá',
                          7,
                        ),
                        _buildStripedInfoRow(
                          'OAL',
                          cartridge['oal'] != null
                              ? '${cartridge['oal']} mm'
                              : 'Neznámá',
                          8,
                        ),
                        _buildStripedInfoRow(
                          'Rychlost',
                          cartridge['velocity_ms'] != null
                              ? '${cartridge['velocity_ms']} m/s'
                              : 'Neznámá',
                          9,
                        ),
                        _buildStripedInfoRow(
                          'Standardní Deviace',
                          cartridge['standard_deviation'] != null
                              ? '${cartridge['standard_deviation']}'
                              : 'Neznámá',
                          10,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      isLoading ? null : () => _showShootingLogForm(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Přidat záznam'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[600],
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14.0, horizontal: 12.0),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : _showIncreaseStockDialog,
                  icon: const Icon(Icons.add_shopping_cart, size: 20),
                  label: const Text('Navýšit zásobu'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[700],
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14.0, horizontal: 12.0),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStripedInfoRow(String label, String value, int rowIndex,
      {Widget? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      color: rowIndex % 2 == 0 ? Colors.grey.shade200 : Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              Text(value),
              if (icon != null) ...[
                const SizedBox(width: 8),
                icon, // Zobrazí ikonu, pokud je k dispozici
              ]
            ],
          ),
        ],
      ),
    );
  }

  void _showIncreaseStockDialog() {
    TextEditingController quantityController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Navýšit zásobu pro ${widget.cartridge['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration:
                    const InputDecoration(labelText: 'Zadejte množství'),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      int currentValue =
                          int.tryParse(quantityController.text) ?? 0;
                      quantityController.text = (currentValue + 1).toString();
                    },
                    child: const Text('+1'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      int currentValue =
                          int.tryParse(quantityController.text) ?? 0;
                      quantityController.text = (currentValue + 10).toString();
                    },
                    child: const Text('+10'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      int currentValue =
                          int.tryParse(quantityController.text) ?? 0;
                      quantityController.text = (currentValue + 100).toString();
                    },
                    child: const Text('+100'),
                  ),
                ],
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                int quantity = int.tryParse(quantityController.text) ?? 0;
                Navigator.pop(dialogContext);
                if (quantity > 0) {
                  final cartridgeId = widget.cartridge['id'];
                  print(
                      'Navýšení zásob: ID: $cartridgeId, Množství: $quantity');

                  bool online = await isOnline();
                  if (online) {
                    try {
                      final response = await ApiService.increaseCartridge(
                          cartridgeId, quantity);
                      if (response.containsKey('newStock')) {
                        setState(() {
                          cartridgeDetails?['stock_quantity'] =
                              response['newStock'];
                          widget.cartridge['stock_quantity'] =
                              response['newStock'];
                        });
                        scaffoldMessengerKey.currentState?.showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Skladová zásoba aktualizována na ${response['newStock']} ks.')),
                        );
                        await _fetchData();
                      }
                    } catch (e) {
                      print('Chyba při navýšení zásob: $e');
                      await DatabaseHelper()
                          .updateStockOffline(cartridgeId, quantity);
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Změna skladu uložena pro pozdější synchronizaci')),
                      );
                    }
                  } else {
                    // Offline mode - use updateStockOffline directly
                    await DatabaseHelper()
                        .updateStockOffline(cartridgeId, quantity);
                    scaffoldMessengerKey.currentState?.showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Změna skladu uložena pro pozdější synchronizaci')),
                    );
                  }
                } else {
                  print('Neplatné množství pro navýšení zásob: $quantity');
                }
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Zavření dialogu
              },
              child: const Text('Zrušit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showShootingLogForm(BuildContext context) async {
    // Debug - zkontroluj obsah userWeapons
    print('Načtené zbraně: $userWeapons');
    if (userWeapons.isEmpty) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Žádné zbraně nebyly nalezeny pro tento kalibr.'),
        ),
      );
      return; // Ukončí funkci, pokud není žádná zbraň dostupná
    }

    TextEditingController ammoCountController = TextEditingController();
    TextEditingController noteController = TextEditingController();
    TextEditingController dateController = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    String? selectedWeapon;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Přidat záznam do střeleckého deníku'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      decoration:
                          const InputDecoration(labelText: 'Vyberte zbraň'),
                      value: selectedWeapon,
                      items:
                          userWeapons.map<DropdownMenuItem<String>>((weapon) {
                        if (weapon != null &&
                            weapon['weapon_id'] != null &&
                            weapon['weapon_name'] != null) {
                          return DropdownMenuItem<String>(
                            value: weapon['weapon_id'].toString(),
                            child: Text(weapon['weapon_name']),
                          );
                        }
                        return DropdownMenuItem<String>(
                          value: '',
                          child: Text('Není k dispozici'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedWeapon = value;
                        });
                      },
                    ),
                    TextField(
                      controller: ammoCountController,
                      decoration: const InputDecoration(
                        labelText: 'Počet vystřelených nábojů',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: dateController,
                      decoration: const InputDecoration(
                          labelText: 'Datum (YYYY-MM-DD)'),
                    ),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Poznámka'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Zrušit'),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedWeapon == null ||
                        ammoCountController.text.isEmpty ||
                        dateController.text.isEmpty) {
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        const SnackBar(
                          content: Text('Vyplňte všechna povinná pole!'),
                        ),
                      );
                      return;
                    }

                    final shootingLogData = {
                      'weapon_id': int.parse(selectedWeapon!),
                      'activity_type': 'Střelba',
                      'date': dateController.text,
                      'range': null,
                      'shots_fired':
                          int.tryParse(ammoCountController.text) ?? 0,
                      'cartridge_id': widget.cartridge[
                          'id'], // Change from caliber_id to cartridge_id
                      'note': noteController.text,
                    };

                    bool online = await isOnline();
                    if (online) {
                      try {
                        // Pokus o odeslání dat na API
                        final response =
                            await ApiService.createShootingLog(shootingLogData);

                        if (response != null && response['success'] == true) {
                          print('Záznam úspěšně vytvořen: $response');

                          scaffoldMessengerKey.currentState?.showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Záznam byl úspěšně uložen do střeleckého deníku.'),
                            ),
                          );
                          Navigator.pop(context); // Zavření dialogu
                        } else {
                          // Pokud API vrátí neúspěch
                          throw Exception('API nevrátilo úspěšnou odpověď.');
                        }
                      } catch (e) {
                        print('Chyba při odesílání záznamu: $e');

                        // Offline režim: Ulož požadavek lokálně
                        try {
                          await DatabaseHelper().addOfflineRequest(
                            context, // Kontext, pokud je třeba
                            'create_shooting_log', // Typ požadavku
                            shootingLogData, // Data požadavku
                          );
                          print(
                              'Požadavek byl úspěšně uložen do offline_requests.');

                          // Přidání Snackbaru pro uživatele
                          scaffoldMessengerKey.currentState?.showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Záznam byl uložen pro pozdější synchronizaci.'),
                            ),
                          );
                        } catch (error) {
                          print('Chyba při ukládání požadavku offline: $error');
                        }
                      }
                    } else {
                      // Offline režim: Ulož požadavek lokálně
                      print('Offline režim: Ukládám požadavek lokálně.');
                      try {
                        await DatabaseHelper().addOfflineRequest(
                          context, // Kontext, pokud je třeba
                          'create_shooting_log', // Typ požadavku
                          shootingLogData, // Data požadavku
                        );
                        print(
                            'Požadavek byl úspěšně uložen do offline_requests.');
                      } catch (error) {
                        print('Chyba při ukládání požadavku offline: $error');
                      }
                    }
                  },
                  child: const Text('Uložit'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
