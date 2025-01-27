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
  List<dynamic> userRanges = [];

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

  Future<Map<String, dynamic>?> _fetchMonitoringStatus(int caliberId) async {
    try {
      // Quick return if we have fresh data
      if (cartridgeDetails?['caliber'] != null) {
        final caliber = cartridgeDetails!['caliber'];
        return {
          'is_monitored': caliber['is_monitored'] ?? false,
          'monitoring_threshold': caliber['monitoring_threshold'] ?? 0
        };
      }

      // Fallback - fetch fresh data
      if (await isOnline()) {
        final response = await ApiService.get('calibers/$caliberId');
        if (response != null && response['success']) {
          return {
            'is_monitored': response['data']['is_monitored'] ?? false,
            'monitoring_threshold':
                response['data']['monitoring_threshold'] ?? 0
          };
        }
      }
      return null;
    } catch (e) {
      print('Error fetching monitoring status: $e');
      return null;
    }
  }

  Future<bool> _toggleMonitoring(
      int caliberId, bool isMonitored, int threshold) async {
    try {
      if (await isOnline()) {
        final response = await ApiService.toggleCaliberMonitoring(
            caliberId, isMonitored, threshold);
        return response['success'] == true;
      }
      return false;
    } catch (e) {
      print('Error toggling monitoring: $e');
      return false;
    }
  }

  Future<void> _fetchUserRanges() async {
    try {
      final rangesResponse = await ApiService.getUserRanges();
      setState(() {
        userRanges = rangesResponse ?? [];
      });
    } catch (e) {
      print('Chyba při načítání střelnic: $e');
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

  Future<int> _getCaliberTotalStock(int caliberId) async {
    print('Debug: Getting total stock for caliber ID: $caliberId');

    try {
      // Local DB query with better structure and debug
      final db = await DatabaseHelper().database;

      // First check if data exists
      final checkData = await db.query(
        'cartridges',
        where: 'caliber_id = ?',
        whereArgs: [caliberId],
      );
      print(
          'Debug: Found ${checkData.length} cartridges for caliber $caliberId');

      // Improved sum query
      final result = await db.rawQuery('''
      SELECT COALESCE(SUM(CAST(stock_quantity AS INTEGER)), 0) as total 
      FROM cartridges 
      WHERE caliber_id = ?
    ''', [caliberId]);

      final localTotal = result.first['total'];
      print('Debug: SQL Result: $result');
      print('Debug: Local total from DB: $localTotal');

      // Convert to int safely
      final parsedTotal =
          localTotal == null ? 0 : int.tryParse(localTotal.toString()) ?? 0;
      print('Debug: Parsed total: $parsedTotal');

      // Try API only if online
      if (await isOnline()) {
        try {
          final response =
              await ApiService.get('/api/calibers/$caliberId/stock');
          print('Debug: API Response for stock: $response');
          if (response != null && response['total_stock'] != null) {
            final apiTotal = response['total_stock'];
            print('Debug: API total: $apiTotal');
            return apiTotal;
          }
        } catch (apiError) {
          print('Debug: API Error: $apiError');
        }
      }

      return parsedTotal;
    } catch (e) {
      print('Error in _getCaliberTotalStock: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _getCaliberCartridges(
      int caliberId) async {
    try {
      final db = await DatabaseHelper().database;

      final cartridges = await db.rawQuery('''
      SELECT 
        id,
        name, 
        stock_quantity,
        cartridge_type
      FROM cartridges 
      WHERE caliber_id = ? 
      ORDER BY name
    ''', [caliberId]);

      print(
          'Debug: Found ${cartridges.length} cartridges for caliber $caliberId');
      print('Debug: Cartridge data: $cartridges');

      return cartridges;
    } catch (e) {
      print('Error fetching caliber cartridges: $e');
      return [];
    }
  }

  Future<void> _showMonitoringDialog(
      int caliberId, bool currentlyMonitored, int currentThreshold) async {
    final thresholdController =
        TextEditingController(text: currentThreshold.toString());
    bool isMonitored = currentlyMonitored;

    final totalStock = await _getCaliberTotalStock(caliberId);
    final caliberName =
        cartridgeDetails?['caliber']?['name'] ?? 'Neznámý kalibr';

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Monitorování kalibru $caliberName',
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nastavte minimální množství pro všechny náboje tohoto kalibru',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.all(24),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Stock info section
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Celková zásoba:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '$totalStock ks',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            const Text(
                              'Rozpis nábojů:',
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _getCaliberCartridges(caliberId),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return Column(
                                  children: snapshot.data!.map((cartridge) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              cartridge['name'],
                                              style:
                                                  const TextStyle(fontSize: 13),
                                            ),
                                          ),
                                          Text(
                                            '${cartridge['stock_quantity']} ks',
                                            style:
                                                const TextStyle(fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Monitoring controls
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Zapnout monitorování'),
                            subtitle: const Text('Upozornění při nízkém stavu'),
                            value: isMonitored,
                            activeColor: Colors.blueGrey,
                            onChanged: (value) =>
                                setState(() => isMonitored = value),
                          ),
                          if (isMonitored) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: TextFormField(
                                controller: thresholdController,
                                decoration: InputDecoration(
                                  labelText: 'Minimální množství',
                                  suffix: const Text('ks'),
                                  helperText:
                                      'Zobrazit varování při poklesu pod tuto hodnotu',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Colors.blueGrey),
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Zrušit'),
                ),
                FilledButton(
                  onPressed: () async {
                    final threshold =
                        int.tryParse(thresholdController.text) ?? 100;
                    final success = await _toggleMonitoring(
                      caliberId,
                      isMonitored,
                      threshold,
                    );
                    if (success && context.mounted) {
                      Navigator.pop(context,
                          {'isMonitored': isMonitored, 'threshold': threshold});
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                  ),
                  child: const Text('Uložit'),
                ),
              ],
            );
          },
        );
      },
    );
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
                      FutureBuilder<Map<String, dynamic>?>(
                        future:
                            _fetchMonitoringStatus(cartridge['caliber']?['id']),
                        builder: (context, snapshot) {
                          final isMonitored =
                              snapshot.data?['is_monitored'] ?? false;
                          final threshold =
                              snapshot.data?['monitoring_threshold'] ?? 100;

                          return _buildStripedInfoRow(
                            'Kalibr',
                            cartridge['caliber']?['name'] ?? 'Neznámý',
                            0,
                            icon: GestureDetector(
                              onTap: () => _showMonitoringDialog(
                                cartridge['caliber']?['id'],
                                isMonitored,
                                threshold,
                              ),
                              child: Icon(
                                isMonitored
                                    ? Icons.notifications_active
                                    : Icons.notifications_off,
                                color: isMonitored ? Colors.green : Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
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
                  icon: const Icon(Icons.inventory,
                      size: 20), // Changed from add_shopping_cart
                  label: const Text(
                      'Upravit zásobu'), // Changed from 'Navýšit zásobu'
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
    bool isIncrease = true;

    showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Upravit zásobu pro ${widget.cartridge['name']}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Přidat')),
                      ButtonSegment(value: false, label: Text('Odebrat')),
                    ],
                    selected: {isIncrease},
                    onSelectionChanged: (Set<bool> newValue) {
                      setDialogState(() => isIncrease = newValue.first);
                    },
                  ),
                  const SizedBox(height: 16),
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
                      for (final amount in [1, 10, 100])
                        ElevatedButton(
                          onPressed: () {
                            final currentValue =
                                int.tryParse(quantityController.text) ?? 0;
                            quantityController.text =
                                (currentValue + amount).toString();
                          },
                          child: Text('+$amount'),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Zrušit'),
                ),
                TextButton(
                  onPressed: () {
                    final quantity = int.tryParse(quantityController.text) ?? 0;
                    if (quantity <= 0) return;

                    Navigator.pop(dialogContext, {
                      'quantity': quantity,
                      'isIncrease': isIncrease,
                    });
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    ).then((result) async {
      if (result == null) return;

      final quantity = result['quantity'] as int;
      final isIncrease = result['isIncrease'] as bool;
      final adjustedQuantity = isIncrease ? quantity : -quantity;
      final cartridgeId = widget.cartridge['id'];

      if (!mounted) return;

      if (await isOnline()) {
        try {
          final response =
              await ApiService.increaseCartridge(cartridgeId, adjustedQuantity);

          if (!mounted) return;

          if (response != null && response.containsKey('newStock')) {
            setState(() {
              cartridgeDetails?['stock_quantity'] = response['newStock'];
              widget.cartridge['stock_quantity'] = response['newStock'];
            });

            scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text(
                    'Skladová zásoba aktualizována na ${response['newStock']} ks.'),
                duration: const Duration(seconds: 3),
              ),
            );

            if (response['warning'] != null) {
              final warning = response['warning'];
              if (warning['type'] == 'low_stock') {
                await Future.delayed(const Duration(seconds: 1));

                final cartridgesList = (warning['cartridges'] as List)
                    .map((c) => '${c['name']}: ${c['stock']} ks')
                    .join('\n');

                scaffoldMessengerKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(warning['message']),
                              const SizedBox(height: 4),
                              Text(
                                'Celkem nábojů: ${warning['current_total']} ks (limit: ${warning['threshold']} ks)',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cartridgesList,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 5),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(8),
                  ),
                );
              }
            }
            return; // Success - exit early
          }

          throw Exception('API nevrátilo platnou odpověď');
        } catch (e) {
          print('Chyba při úpravě zásob: $e');
          if (!mounted) return;

          scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Chyba při komunikaci se serverem')),
          );
          return; // Error - don't create offline request
        }
      }

      // Handle truly offline mode
      final currentStock = cartridgeDetails?['stock_quantity'] ??
          widget.cartridge['stock_quantity'] ??
          0;
      final newStock = currentStock + adjustedQuantity;

      setState(() {
        cartridgeDetails?['stock_quantity'] = newStock;
        widget.cartridge['stock_quantity'] = newStock;
      });

      try {
        await DatabaseHelper().addOfflineRequest(
          'update_stock',
          {'id': cartridgeId, 'quantity': adjustedQuantity},
        );

        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
              content: Text('Změna skladu uložena pro pozdější synchronizaci')),
        );
      } catch (error) {
        print('Chyba při ukládání offline požadavku: $error');
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
              content: Text('Chyba při ukládání změny skladu offline')),
        );
      }
    });
  }

  Future<void> _showShootingLogForm(BuildContext context) async {
    print('Načtené zbraně: $userWeapons');
    if (userWeapons.isEmpty) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Žádné zbraně nebyly nalezeny pro tento kalibr.'),
        ),
      );
      return;
    }

    await _fetchUserRanges();

    TextEditingController ammoCountController = TextEditingController();
    TextEditingController noteController = TextEditingController();
    TextEditingController dateController = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    String? selectedWeapon;
    String? selectedRange;

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
                        return const DropdownMenuItem<String>(
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
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Střelnice'),
                      value: selectedRange,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Bez střelnice'),
                        ),
                        ...userRanges.map<DropdownMenuItem<String>>((range) {
                          return DropdownMenuItem<String>(
                            value: range['name'],
                            child: Text(range['name']),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedRange = value;
                        });
                      },
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Zrušit'),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedWeapon == null ||
                        ammoCountController.text.isEmpty ||
                        dateController.text.isEmpty) {
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        const SnackBar(
                            content: Text('Vyplňte všechna povinná pole!')),
                      );
                      return;
                    }

                    final shootingLogData = {
                      'weapon_id': int.parse(selectedWeapon!),
                      'activity_type': 'Střelba',
                      'date': dateController.text,
                      'range': selectedRange,
                      'shots_fired':
                          int.tryParse(ammoCountController.text) ?? 0,
                      'cartridge_id': widget.cartridge['id'],
                      'note': noteController.text,
                    };

                    Navigator.pop(context);

                    bool online = await isOnline();
                    if (online) {
                      try {
                        final response =
                            await ApiService.createShootingLog(shootingLogData);

                        if (response != null && response['success'] == true) {
                          print('Záznam úspěšně vytvořen: $response');

                          // Success message
                          scaffoldMessengerKey.currentState?.showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Záznam byl úspěšně uložen do střeleckého deníku.'),
                              duration: Duration(seconds: 3),
                            ),
                          );

                          // Show warning only if it exists and is not null
                          if (response['warning'] != null) {
                            final warning = response['warning'];
                            if (warning['type'] == 'low_stock') {
                              await Future.delayed(const Duration(seconds: 1));

                              final cartridgesList = (warning['cartridges']
                                      as List)
                                  .map((c) => '${c['name']}: ${c['stock']} ks')
                                  .join('\n');

                              scaffoldMessengerKey.currentState?.showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.warning_amber,
                                          color: Colors.white),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(warning['message']),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Celkem nábojů: ${warning['current_total']} ks (limit: ${warning['threshold']} ks)',
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              cartridgesList,
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: Colors.orange,
                                  duration: const Duration(seconds: 5),
                                  behavior: SnackBarBehavior.floating,
                                  margin: const EdgeInsets.all(8),
                                ),
                              );
                            }
                          }
                          return; // Success - exit early
                        } else {
                          throw Exception('API nevrátilo úspěšnou odpověď.');
                        }
                      } catch (e) {
                        print('Chyba při odesílání záznamu: $e');
                        // Fall through to offline handling
                      }
                    }

// Handle offline mode or API errors
                    print('Offline režim: Ukládám požadavek lokálně.');
                    try {
                      await DatabaseHelper().addOfflineRequest(
                        'create_shooting_log',
                        shootingLogData,
                      );
                      print(
                          'Požadavek byl úspěšně uložen do offline_requests.');
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Záznam byl uložen pro pozdější synchronizaci.'),
                        ),
                      );
                    } catch (error) {
                      print('Chyba při ukládání požadavku offline: $error');
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        const SnackBar(
                          content: Text('Chyba při ukládání záznamu offline.'),
                        ),
                      );
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
