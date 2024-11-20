import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shooting_companion/screens/barcode_scanner_screen.dart';
import 'package:shooting_companion/helpers/database_helper.dart';

Future<bool> isOnline() async {
  var connectivityResult = await (Connectivity().checkConnectivity());
  return connectivityResult != ConnectivityResult.none;
}

class SQLiteService {
  static Future<List<Map<String, dynamic>>> getWeaponsByCaliber(
      int caliberId) async {
    final db = await openDatabase('app_database.db');
    return await db
        .query('weapons', where: 'caliber_id = ?', whereArgs: [caliberId]);
  }

  static Future<List<Map<String, dynamic>>> getUserActivities() async {
    final db = await openDatabase('app_database.db');
    return await db.query('activities');
  }

  // Přidání metody pro načtení cartridge podle ID
  static Future<Map<String, dynamic>?> getCartridgeById(int id) async {
    final db = await openDatabase('app_database.db'); // Otevře SQLite databázi
    final result = await db.query(
      'cartridges', // Název tabulky
      where: 'id = ?', // Filtr na základě ID
      whereArgs: [id], // Hodnota pro nahrazení otazníku
    );

    if (result.isNotEmpty) {
      return result.first; // Vrátí první nalezený záznam
    } else {
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

  Future<Map<String, dynamic>> getCartridgeDetails(int id) async {
    try {
      bool online = await isOnline();
      print('Kontrola připojení k internetu: $online');

      if (online) {
        print('Načítám data z API pro cartridge ID: $id');
        final apiResponse = await ApiService.getCartridgeById(id);
        print('Načtená data z API: $apiResponse');
        return apiResponse;
      } else {
        print('Načítám data z SQLite pro cartridge ID: $id');
        final localCartridge = await SQLiteService.getCartridgeById(id);
        print('Načtená data z SQLite: $localCartridge');
        if (localCartridge != null) {
          return localCartridge;
        } else {
          throw Exception('Cartridge not found in offline database');
        }
      }
    } catch (e) {
      print('Chyba při načítání detailů cartridge: $e');
      rethrow;
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      isLoading = true;
    });

    try {
      print('Začátek načítání dat...');
      final cartridgeId = widget.cartridge['id'];
      print('Načítám detaily náboje pro ID: $cartridgeId');

      // Načtení detailů náboje
      final details = await getCartridgeDetails(cartridgeId);
      print('Načtené detaily náboje: $details');

      bool online = await isOnline();
      print('Online režim: $online');

      if (online) {
        // Online načtení
        print('Načítám zbraně a aktivity online...');
        final weaponsResponse =
            await ApiService.getUserWeaponsByCaliber(details['caliber']['id']);
        final activitiesResponse = await ApiService.getUserActivities();
        print('Načtené zbraně: $weaponsResponse');
        print('Načtené aktivity: $activitiesResponse');

        setState(() {
          cartridgeDetails = details;
          userWeapons = weaponsResponse;
          userActivities = activitiesResponse;
        });
      } else {
        // Offline načtení
        print('Načítám zbraně a aktivity offline...');
        final localWeapons =
            await SQLiteService.getWeaponsByCaliber(details['caliber']['id']);
        final localActivities = await SQLiteService.getUserActivities();
        print('Načtené zbraně (offline): $localWeapons');
        print('Načtené aktivity (offline): $localActivities');

        setState(() {
          cartridgeDetails = details;
          userWeapons = localWeapons;
          userActivities = localActivities;
        });
      }
    } catch (e) {
      // Log chyby
      print('Chyba při načítání dat: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
      print('Načítání dat dokončeno.');
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
                    _buildStripedInfoRow(
                        'Výrobce', cartridge['manufacturer'] ?? 'Neznámý', 1),

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
                                builder: (context) =>
                                    const BarcodeScannerScreen()),
                          );
                        }
                      },
                      child: _buildStripedInfoRow(
                        'Čárový kód',
                        cartridge['barcode'] != null &&
                                cartridge['barcode'].isNotEmpty
                            ? 'Přidělen'
                            : 'Nepřidělen - klikněte pro přidělení',
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
                icon: const Icon(Icons.add),
                label: const Text('Přidat záznam'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : _showIncreaseStockDialog,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Navýšit zásobu'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
                Navigator.pop(dialogContext); // Zavření dialogu
                if (quantity > 0) {
                  try {
                    final cartridgeId = widget.cartridge['id'];
                    print(
                        'Navýšení zásob: ID: $cartridgeId, Množství: $quantity');

                    // Aktualizace zásob na serveru (API volání)
                    final response = await ApiService.increaseCartridge(
                      cartridgeId,
                      quantity,
                    );

                    if (response.containsKey('newStock')) {
                      setState(() {
                        // Použij nové množství z odpovědi API
                        cartridgeDetails?['stock_quantity'] =
                            response['newStock'];
                        widget.cartridge['stock_quantity'] =
                            response['newStock'];
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Skladová zásoba byla úspěšně aktualizována na ${response['newStock']} ks.'),
                        ),
                      );

                      // Znovu načti data, abys měl aktuální informace
                      await _fetchData();
                    } else {
                      print('Odpověď API neobsahuje newStock.');
                    }
                  } catch (e) {
                    print('Chyba při navýšení zásob: $e');

                    // Pokud dojde k chybě při pokusu o navýšení online, uložit požadavek do offline_requests
                    await DatabaseHelper().addOfflineRequest(
                      'update_stock',
                      {
                        'id': widget.cartridge['id'],
                        'quantity': quantity,
                      },
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Navýšení zásob bylo uloženo pro synchronizaci později.')),
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
    if (userWeapons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
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
                        return DropdownMenuItem<String>(
                          value: weapon['id'].toString(),
                          child: Text(weapon['name']),
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
                  onPressed: () {
                    if (selectedWeapon == null ||
                        ammoCountController.text.isEmpty ||
                        dateController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Vyplňte všechna povinná pole!'),
                        ),
                      );
                      return;
                    }

                    // Logika pro zpracování záznamu
                    print(
                      'Záznam vytvořen: Zbraň: $selectedWeapon, '
                      'Počet: ${ammoCountController.text}, '
                      'Datum: ${dateController.text}, '
                      'Poznámka: ${noteController.text}',
                    );
                    Navigator.pop(context);
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
