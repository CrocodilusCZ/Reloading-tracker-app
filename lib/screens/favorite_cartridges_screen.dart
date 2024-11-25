import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart'; // Import API služby
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/screens/cartridge_detail_screen.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Map<String, dynamic>> originalFactoryCartridges = [];
List<Map<String, dynamic>> originalReloadCartridges = [];

class FavoriteCartridgesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> factoryCartridges;
  final List<Map<String, dynamic>> reloadCartridges;

  const FavoriteCartridgesScreen({
    Key? key,
    required this.factoryCartridges,
    required this.reloadCartridges,
  }) : super(key: key);

  @override
  _FavoriteCartridgesScreenState createState() =>
      _FavoriteCartridgesScreenState();
}

class _FavoriteCartridgesScreenState extends State<FavoriteCartridgesScreen> {
  final PageStorageBucket _bucket = PageStorageBucket();

  bool _showFactoryCartridges = true;
  bool _showZeroStock = false;
  String? selectedCaliber;
  List<String> calibers = [];
  bool _isLoading = false;
  bool _factoryLeft = true; // Pořadí tlačítek

  @override
  void initState() {
    super.initState();
    _loadZeroStockPreference();
    // Inicializace původních dat z widgetu
    originalFactoryCartridges = List.from(widget.factoryCartridges);
    originalReloadCartridges = List.from(widget.reloadCartridges);

    // Načtení kalibrů
    calibers = _getUniqueCalibers(
        [...originalFactoryCartridges, ...originalReloadCartridges]);
    calibers.insert(0, "Vše"); // Přidání možnosti "Vše" na začátek seznamu
    selectedCaliber = "Vše"; // Nastavení výchozího kalibru

    // Načtení uživatelských preferencí
    _loadPreferences();

    // Nastavení výchozí záložky na základě preferencí
    _showFactoryCartridges = _factoryLeft;

    // Přidání logování inicializačních dat
    print("Inicializační tovární náboje: $originalFactoryCartridges");
    print("Inicializační přebíjené náboje: $originalReloadCartridges");

    // Načtení a aktualizace dat z API nebo SQLite
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshCartridges();
    });
  }

  Future<void> _loadZeroStockPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showZeroStock = prefs.getBool('favorite_show_zero_stock') ?? false;
    });
  }

  Future<void> _saveZeroStockPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('favorite_show_zero_stock', value);
  }

  Future<void> _initializeCartridges() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = connectivityResult != ConnectivityResult.none;

      final fetchedCartridges = await fetchCartridges(isOnline);

      setState(() {
        originalFactoryCartridges = fetchedCartridges
            .where((cartridge) => cartridge['type'] == 'factory')
            .toList();
        originalReloadCartridges = fetchedCartridges
            .where((cartridge) => cartridge['type'] == 'reload')
            .toList();
        _updateCartridges(_showFactoryCartridges
            ? originalFactoryCartridges
            : originalReloadCartridges);
      });
    } catch (e) {
      print("Chyba při inicializaci dat: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Načítání preference z úložiště
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final factoryLeft =
        prefs.getBool('factoryLeft') ?? true; // Načtení preferencí

    setState(() {
      _factoryLeft = factoryLeft;
      _showFactoryCartridges =
          _factoryLeft; // Nastavení záložky na základě preferencí
    });

    // Aktualizace obsahu po načtení preferencí
    _updateCartridges(_showFactoryCartridges
        ? originalFactoryCartridges
        : originalReloadCartridges);
  }

// Uložení preference do úložiště
  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
        'factoryLeft', _factoryLeft); // Uložení aktuální hodnoty _factoryLeft
  }

  void _updateCartridges(List<Map<String, dynamic>> cartridges) {
    print("Aktualizuji náboje...");
    print("Před filtrem: ${cartridges.length} nábojů");
    print("_showFactoryCartridges: $_showFactoryCartridges");

    final sourceCartridges = _showFactoryCartridges
        ? originalFactoryCartridges
        : originalReloadCartridges;

    final filteredCartridges = _filterByCaliber(sourceCartridges);

    print("Po filtru: ${filteredCartridges.length} nábojů");

    setState(() {
      if (_showFactoryCartridges) {
        print("Aktualizuji tovární náboje...");
        widget.factoryCartridges.clear();
        widget.factoryCartridges.addAll(filteredCartridges);
      } else {
        print("Aktualizuji přebíjené náboje...");
        widget.reloadCartridges.clear();
        widget.reloadCartridges.addAll(filteredCartridges);
      }
    });
  }

  List<String> _getUniqueCalibers(List<Map<String, dynamic>> cartridges) {
    return cartridges
        .map((cartridge) {
          String? caliberName;

          // Kontrola přítomnosti 'caliber_name' (SQLite data)
          if (cartridge.containsKey('caliber_name') &&
              cartridge['caliber_name'] != null) {
            caliberName = cartridge['caliber_name'] as String;
          }
          // Kontrola přítomnosti 'caliber' a 'caliber.name' (API data)
          else if (cartridge['caliber'] != null &&
              cartridge['caliber']['name'] != null) {
            caliberName = cartridge['caliber']['name'] as String;
          }
          // Výchozí hodnota, pokud kalibr není dostupný
          else {
            caliberName = 'Neznámý kalibr';
          }

          return caliberName;
        })
        .toSet()
        .toList();
  }

  void _updateCalibers() {
    // Dynamické načítání kalibrů na základě aktuální záložky
    calibers = _getUniqueCalibers(_showFactoryCartridges
        ? originalFactoryCartridges
        : originalReloadCartridges);
    calibers.insert(0, "Vše"); // Přidání možnosti "Vše" na začátek seznamu
    selectedCaliber = "Vše"; // Výchozí hodnota
  }

  List<Map<String, dynamic>> _filterByCaliber(
      List<Map<String, dynamic>> cartridges) {
    print("=== Začínám filtrování nábojů ===");
    print("Počet nábojů před filtrem: ${cartridges.length}");

    // Log každého náboje před filtrem
    cartridges.forEach((cartridge) {
      final caliberName = cartridge['caliber_name'] ??
          (cartridge['caliber']?['name'] ?? 'Neznámý kalibr');
      final stockQuantity = cartridge['stock_quantity'] ?? 0;
      print(
          "Náboj: ${cartridge['name']} | Kalibr: $caliberName | Skladové množství: $stockQuantity");
    });

    print(
        "Parametry filtru: selectedCaliber = $selectedCaliber, _showZeroStock = $_showZeroStock");

    var filtered = cartridges;

    // Filtrování podle kalibru
    if (selectedCaliber != null && selectedCaliber != "Vše") {
      print("Filtruji podle kalibru: $selectedCaliber");
      filtered = filtered.where((cartridge) {
        String? caliberName;

        if (cartridge.containsKey('caliber_name') &&
            cartridge['caliber_name'] != null) {
          caliberName = cartridge['caliber_name'] as String;
        } else if (cartridge['caliber'] != null &&
            cartridge['caliber']['name'] != null) {
          caliberName = cartridge['caliber']['name'] as String;
        }

        final matches = caliberName == selectedCaliber;
        print(
            "Kontrola kalibru: ${cartridge['name']} | Kalibr: $caliberName | Shoda: $matches");
        return matches;
      }).toList();
      print("Počet nábojů po filtru kalibru: ${filtered.length}");
    }

    // Filtrování podle dostupnosti skladu
    if (!_showZeroStock) {
      print("Filtruji podle skladové dostupnosti (bez nulových hodnot).");
      filtered = filtered.where((cartridge) {
        final stockQuantity = cartridge['stock_quantity'] ?? 0;
        final isAvailable = stockQuantity > 0;
        print(
            "Kontrola skladu: ${cartridge['name']} | Sklad: $stockQuantity | Dostupný: $isAvailable");
        return isAvailable;
      }).toList();
      print("Počet nábojů po filtru skladu: ${filtered.length}");
    }

    if (filtered.isEmpty) {
      print("!!! Žádné náboje neprošly filtrem.");
    } else {
      print("Finální výstup filtru: ${filtered.length} nábojů");
      filtered.forEach((cartridge) {
        print(
            "Výstup: Náboj: ${cartridge['name']} | Kalibr: ${cartridge['caliber_name']} | Sklad: ${cartridge['stock_quantity']}");
      });
    }

    print("=== Filtrování dokončeno ===");
    return filtered;
  }

  Future<List<Map<String, dynamic>>> fetchCartridges(bool isOnline) async {
    try {
      // Pokus o načtení dat z API
      if (isOnline) {
        final apiCartridges = await ApiService.getAllCartridges();

        if (apiCartridges == null) {
          print('API vrátilo null, přepínám na SQLite.');
          return await fetchCartridgesFromSQLite();
        }

        // Extrakce továrních a přebíjených nábojů
        final factory = apiCartridges['factory'] ?? [];
        final reload = apiCartridges['reload'] ?? [];

        print(
            "Načteno z API: Factory=${factory.length}, Reload=${reload.length}");

        return [...factory, ...reload];
      }

      // Offline režim: načtení dat ze SQLite
      return await fetchCartridgesFromSQLite();
    } catch (e) {
      // Log chyby a pokus o načtení dat ze SQLite
      print("Chyba při načítání dat z API nebo SQLite: $e");
      try {
        final sqliteCartridges = await fetchCartridgesFromSQLite();
        print("Načteno ze SQLite: ${sqliteCartridges.length} nábojů.");
        return sqliteCartridges;
      } catch (sqliteError) {
        print("Chyba při načítání dat ze SQLite: $sqliteError");
        return []; // Vrácení prázdného seznamu jako výchozí stav
      }
    }
  }

  Future<void> _refreshCartridges() async {
    setState(() {
      _isLoading = true; // Nastavení indikátoru načítání
    });

    try {
      // Kontrola připojení k internetu
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = connectivityResult != ConnectivityResult.none;

      // Načtení dat (online nebo offline)
      final fetchedCartridges = await fetchCartridges(isOnline);

      setState(() {
        // Aktualizace původních seznamů nábojů
        originalFactoryCartridges = fetchedCartridges
            .where((cartridge) => cartridge['type'] == 'factory')
            .toList();
        originalReloadCartridges = fetchedCartridges
            .where((cartridge) => cartridge['type'] == 'reload')
            .toList();

        // Aktualizace viditelných nábojů
        _updateCartridges(_showFactoryCartridges
            ? originalFactoryCartridges
            : originalReloadCartridges);

        // Aktualizace seznamu kalibrů
        _updateCalibers();
      });
    } catch (error) {
      print("Chyba při obnově dat: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Obnova dat se nezdařila. Zkontrolujte připojení k internetu nebo zkuste znovu později.',
          ),
          action: SnackBarAction(
            label: 'Zkusit znovu',
            onPressed: () {
              _refreshCartridges(); // Opakovaný pokus o obnovu dat
            },
          ),
          duration: Duration(seconds: 5), // Doba zobrazení zprávy
        ),
      );
    } finally {
      setState(() {
        _isLoading = false; // Vypnutí indikátoru načítání
      });
    }
  }

  Future<void> _fetchUserWeapons(int caliberId) async {
    try {
      final weapons = await DatabaseHelper.getWeapons(caliberId: caliberId);
      if (weapons.isNotEmpty) {
        _showWeaponsDialog(weapons);
      } else {
        print("Pro tento kalibr nebyly nalezeny žádné zbraně.");
      }
    } catch (e) {
      print('Chyba při načítání zbraní: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchCartridgesFromSQLite() async {
    final db = await DatabaseHelper().database;

    print("Začínám načítání nábojů z SQLite...");

    final cartridges = await db.rawQuery('''
  SELECT
    cartridges.id,
    cartridges.load_step_id,
    cartridges.user_id,
    cartridges.name,
    cartridges.description,
    cartridges.is_public,
    cartridges.bullet_id,
    cartridges.primer_id,
    cartridges.powder_weight,
    cartridges.stock_quantity,
    cartridges.brass_id,
    cartridges.velocity_ms,
    cartridges.oal,
    cartridges.standard_deviation,
    cartridges.is_favorite,
    cartridges.price,
    cartridges.caliber_id,
    cartridges.powder_id,
    cartridges.created_at,
    cartridges.updated_at,
    cartridges.type AS cartridge_type,
    cartridges.manufacturer,
    cartridges.bullet_specification,
    cartridges.total_upvotes,
    cartridges.total_downvotes,
    cartridges.barcode,
    cartridges.package_size,
    calibers.name AS caliber_name
  FROM cartridges
  LEFT JOIN calibers ON cartridges.caliber_id = calibers.id
  ''');

    print("Načteno ${cartridges.length} záznamů z SQLite:");

    List<Map<String, dynamic>> validatedCartridges = [];
    for (var cartridge in cartridges) {
      try {
        // Logování každého načteného záznamu
        print("Zpracovávám náboj: ${cartridge.toString()}");

        // Validace zásob
        final stockRaw = cartridge['stock_quantity'];
        final stock =
            stockRaw != null ? int.tryParse(stockRaw.toString()) ?? 0 : 0;

        // Získání dalších hodnot
        final type = cartridge['cartridge_type'] ?? 'Unknown';
        final caliberName = cartridge['caliber_name'] ?? 'Unknown';

        // Logování zpracovaných hodnot
        print(
            "Náboj: ${cartridge['name'] ?? 'Neznámý'} | Sklad: $stock | Typ: $type | Kalibr: $caliberName");

        // Přidání validního záznamu
        validatedCartridges.add({
          'id': cartridge['id'],
          'caliber_id': cartridge['caliber_id'],
          'name': cartridge['name'] ?? 'Neznámý název',
          'stock_quantity': stock,
          'type': type,
          'caliber_name': caliberName,
          'description': cartridge['description'],
          'price': cartridge['price'] ?? 0.0,
          'barcode': cartridge['barcode'],
          'manufacturer': cartridge['manufacturer'],
          // Další sloupce dle potřeby
        });
        // Logování validace
        print(
            "Validní: ID=${cartridge['id']}, Název=${cartridge['name']}, Kalibr ID=${cartridge['caliber_id']}, Kalibr=${cartridge['caliber_name']}");
      } catch (e) {
        // Logování chyby při zpracování
        print(
            "Chyba při zpracování náboje ID ${cartridge['id']}: ${e.toString()}");
      }
    }

    print("Validní náboje (${validatedCartridges.length}):");
    for (var validCartridge in validatedCartridges) {
      print(
          "Validní: ID=${validCartridge['id']} | Název=${validCartridge['name']} | Kalibr=${validCartridge['caliber_name']} | Sklad=${validCartridge['stock_quantity']}");
    }

    return validatedCartridges;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshCartridges, // Přidání callbacku pro obnovu dat
        child: PageStorage(
          bucket: _bucket,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildToggleButtons(),
                    _buildZeroStockSwitch(),
                    _buildCaliberDropdown(),
                    Expanded(child: _buildCartridgeList()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildToggleButtons() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tlačítka
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    onLongPress: _swapToggleButtons, // Funkce přehodí tlačítka
                    child: _buildStyledButton(
                      icon: _factoryLeft
                          ? Icons.factory_outlined
                          : Icons.build_circle_outlined,
                      label: _factoryLeft ? 'Tovární' : 'Přebíjené',
                      isActive: _factoryLeft == _showFactoryCartridges,
                      onPressed: () {
                        setState(() {
                          _showFactoryCartridges = _factoryLeft;
                          _updateCartridges(_showFactoryCartridges
                              ? originalFactoryCartridges
                              : originalReloadCartridges);
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16), // Mezera mezi tlačítky
                Expanded(
                  child: GestureDetector(
                    onLongPress: _swapToggleButtons, // Funkce přehodí tlačítka
                    child: _buildStyledButton(
                      icon: _factoryLeft
                          ? Icons.build_circle_outlined
                          : Icons.factory_outlined,
                      label: _factoryLeft ? 'Přebíjené' : 'Tovární',
                      isActive: _factoryLeft != _showFactoryCartridges,
                      onPressed: () {
                        setState(() {
                          _showFactoryCartridges = !_factoryLeft;
                          _updateCartridges(_showFactoryCartridges
                              ? originalFactoryCartridges
                              : originalReloadCartridges);
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyledButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(
        icon,
        color: isActive ? Colors.white : Colors.blueGrey,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.blueGrey,
          fontSize: 14,
        ),
      ),
      style: ElevatedButton.styleFrom(
        elevation: isActive ? 4 : 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        backgroundColor: isActive ? Colors.blueGrey : Colors.grey[200],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
    );
  }

  List<Widget> _buildToggleChildren() {
    final leftButton = GestureDetector(
      onLongPress: _swapToggleButtons,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          _factoryLeft ? 'Tovární' : 'Přebíjené',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );

    final rightButton = GestureDetector(
      onLongPress: _swapToggleButtons,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          _factoryLeft ? 'Přebíjené' : 'Tovární',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );

    return [leftButton, rightButton];
  }

  void _showWeaponsDialog(List<Map<String, dynamic>> weapons) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Zbraně pro kalibr"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: weapons.length,
              itemBuilder: (context, index) {
                final weapon = weapons[index];
                return ListTile(
                  title: Text(weapon['name'] ?? 'Neznámá zbraň'),
                  subtitle: Text('ID: ${weapon['id']}'),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("Zavřít"),
            ),
          ],
        );
      },
    );
  }

  void _swapToggleButtons() {
    setState(() {
      // Přehodí pořadí tlačítek
      _factoryLeft = !_factoryLeft;

      // Zachování aktuálního výběru při prohození
      _showFactoryCartridges = !_showFactoryCartridges;

      // Aktualizace obsahu
      _updateCartridges(_showFactoryCartridges
          ? originalFactoryCartridges
          : originalReloadCartridges);

      // Uložení preference po změně
      _savePreferences();

      // Zpětná vazba pro uživatele
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _factoryLeft
                ? 'Tlačítka přehodnocena: Tovární vlevo, Přebíjené vpravo'
                : 'Tlačítka přehodnocena: Přebíjené vlevo, Tovární vpravo',
          ),
          duration: const Duration(milliseconds: 800),
        ),
      );
    });
  }

  Widget _buildZeroStockSwitch() {
    return Card(
      elevation: 3,
      color: Colors.grey.shade200,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Zobrazit s nulovou dostupností',
              style: TextStyle(fontSize: 16),
            ),
            Switch(
              value: _showZeroStock,
              activeColor: Colors.blueGrey,
              onChanged: (value) async {
                setState(() {
                  _showZeroStock = value;
                });
                await _saveZeroStockPreference(value);
                _updateCartridges(_showFactoryCartridges
                    ? originalFactoryCartridges
                    : originalReloadCartridges);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaliberDropdown() {
    return Card(
      elevation: 3,
      color: Colors.grey.shade200,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButton<String>(
          value: calibers.contains(selectedCaliber) ? selectedCaliber : null,
          icon: const Icon(Icons.arrow_drop_down),
          onChanged: (String? newValue) {
            setState(() {
              selectedCaliber = newValue;
            });
            _updateCartridges(_showFactoryCartridges
                ? widget.factoryCartridges
                : widget.reloadCartridges);
          },
          isExpanded: true,
          items: calibers
              .map((caliber) => DropdownMenuItem<String>(
                    value: caliber,
                    child: Text(
                      caliber,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildCartridgeList() {
    final filteredCartridges = _filterByCaliber(
      _showFactoryCartridges
          ? widget.factoryCartridges
          : widget.reloadCartridges,
    );

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filteredCartridges.length,
      itemBuilder: (context, index) {
        final cartridge = filteredCartridges[index];
        final name = cartridge['name'] ?? 'Neznámý náboj';

        // Fix caliber name extraction
        final caliberName = cartridge['caliber_name'] ??
            (cartridge['caliber']?['name'] ?? 'Neznámý kalibr');

        final stock = cartridge['stock_quantity'] ?? 0;
        final hasBarcode =
            cartridge['barcode'] != null && cartridge['barcode'] != '';

        print('Debug: Cartridge data: ${cartridge.toString()}'); // Debug print
        print('Debug: Caliber name: $caliberName'); // Debug print

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: () => _navigateToDetail(cartridge),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C3E50).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.adjust,
                                    size: 14,
                                    color: Color(0xFF2C3E50),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _truncateCaliberName(caliberName),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF2C3E50),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: stock > 0
                                    ? const Color(0xFF27AE60).withOpacity(0.1)
                                    : Colors.red[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inventory_2,
                                    size: 14,
                                    color: stock > 0
                                        ? const Color(0xFF27AE60)
                                        : Colors.red,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$stock ks',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: stock > 0
                                          ? const Color(0xFF27AE60)
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (hasBarcode)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.qr_code,
                        size: 16,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _navigateToDetail(Map<String, dynamic> cartridge) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          // Přidání logů pro analýzu problému
          print("Debug: Kliknuto na náboj: $cartridge");

          // Zobrazení hodnot caliber_id a caliber před zpracováním
          print(
              "Debug: Hodnota 'caliber_id' před zpracováním: ${cartridge['caliber_id']}");
          print(
              "Debug: Hodnota 'caliber' před zpracováním: ${cartridge['caliber']}");

          // Ověření, že caliber_id je platné číslo
          final caliberId = cartridge['caliber_id'];
          if (caliberId is! int) {
            print(
                "Debug: Chyba - caliber_id není typu int. Hodnota: $caliberId");
          } else if (caliberId != 49) {
            print(
                "Debug: Caliber ID není správné. Očekáváme '49', ale máme: $caliberId");
          }

          // Získání správného cartridge ID (ID náboje)
          final cartridgeId = cartridge['id']; // Předání správného ID náboje

          // Předání správného cartridge_id a dalších dat do detailní obrazovky
          final cartridgeWithId = {
            ...cartridge,
            'cartridge_id': cartridgeId, // Předání cartridge_id
          };

          // Logování předávaných dat
          print(
              "Debug: Data předávaná do CartridgeDetailScreen: $cartridgeWithId");

          // Návrat na detailní obrazovku s předanými daty
          return CartridgeDetailScreen(
            cartridge: cartridgeWithId,
          );
        },
      ),
    );
  }

  String _truncateCaliberName(String name) {
    return name.length > 15 ? '${name.substring(0, 15)}...' : name;
  }
}
