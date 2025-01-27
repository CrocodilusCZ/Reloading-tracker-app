import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart'; // Import API služby
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/screens/cartridge_detail_screen.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shooting_companion/helpers/connectivity_helper.dart';
import 'package:sqflite/sqflite.dart';

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

class _FavoriteCartridgesScreenState extends State<FavoriteCartridgesScreen>
    with SingleTickerProviderStateMixin {
  final PageStorageBucket _bucket = PageStorageBucket();
  final ConnectivityHelper _connectivityHelper = ConnectivityHelper();
  bool _previousOnlineState = false;
  int _pendingRequestsCount = 0;
  bool _showFactoryCartridges = true;
  bool _showZeroStock = false;
  String? selectedCaliber;
  List<String> calibers = [];
  bool _isLoading = false;
  bool _factoryLeft = true;
  late TabController _tabController;
  late List<Map<String, dynamic>> originalFactoryCartridges;
  late List<Map<String, dynamic>> originalReloadCartridges;
  bool _isManualToggle = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    print("=== Initializing Favorite Cartridges Screen ===");
    _updatePendingRequestsCount();

    // Initialize data
    originalFactoryCartridges =
        List<Map<String, dynamic>>.from(widget.factoryCartridges);
    originalReloadCartridges =
        List<Map<String, dynamic>>.from(widget.reloadCartridges);
    print("Factory cartridges count: ${originalFactoryCartridges.length}");
    print("Reload cartridges count: ${originalReloadCartridges.length}");

    // Load preferences first
    _loadPreferences();
    _loadZeroStockPreference();

    // Sync cartridge visibility with button position
    _showFactoryCartridges = _factoryLeft;

    // Setup calibers
    calibers = _getUniqueCalibers(
        [...originalFactoryCartridges, ...originalReloadCartridges]);
    calibers.insert(0, "Vše");
    selectedCaliber = "Vše";

    // Setup TabController
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _factoryLeft ? 0 : 1,
    );

    // Add tab change listener
    _tabController.addListener(_handleTabChange);

    // Initial data load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshCartridges();
    });
  }

  void _handleTabChange() {
    if (!mounted) return;

    setState(() {
      _showFactoryCartridges = _tabController.index == 0;
      _updateCartridges(_showFactoryCartridges
          ? originalFactoryCartridges
          : originalReloadCartridges);
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _swapToggleButtons() {
    _isManualToggle = true;
    setState(() {
      _factoryLeft = !_factoryLeft;
      _showFactoryCartridges = !_showFactoryCartridges;

      // Update content and tab position
      _updateCartridges(_showFactoryCartridges
          ? originalFactoryCartridges
          : originalReloadCartridges);
      _tabController.animateTo(_factoryLeft
          ? (_showFactoryCartridges ? 0 : 1)
          : (_showFactoryCartridges ? 1 : 0));

      _savePreferences();

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
    _isManualToggle = false;
  }

  void _handleTogglePressed(bool isFactorySelected) {
    print(
        "DEBUG: Toggle pressed - isFactorySelected: $isFactorySelected, _factoryLeft: $_factoryLeft, current tab: ${_tabController.index}");

    _isManualToggle = true;
    setState(() {
      // First update content visibility
      _showFactoryCartridges = isFactorySelected;

      // Calculate and verify target index
      final targetIndex = _factoryLeft
          ? (isFactorySelected ? 0 : 1)
          : (isFactorySelected ? 1 : 0);
      print("DEBUG: Calculated target index: $targetIndex");

      // Update content before tab animation
      _updateCartridges(_showFactoryCartridges
          ? originalFactoryCartridges
          : originalReloadCartridges);

      // Force tab position update
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _tabController.animateTo(targetIndex, duration: Duration.zero);
        }
      });
    });
    _isManualToggle = false;
  }

  Future<void> _updatePendingRequestsCount() async {
    final db = await DatabaseHelper().database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM offline_requests WHERE status = ?',
      ['pending'],
    ));
    if (mounted) {
      setState(() {
        _pendingRequestsCount = count ?? 0;
      });
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

    final sourceCartridges = List<Map<String, dynamic>>.from(
        _showFactoryCartridges
            ? originalFactoryCartridges
            : originalReloadCartridges);

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

    // Nejdřív namapujeme data do konzistentního formátu
    var mapped = cartridges.map((cartridge) {
      String? caliberName = cartridge['caliber_name'];
      if (caliberName == null && cartridge['caliber'] != null) {
        caliberName = cartridge['caliber']['name'];
      }
      return {
        ...cartridge,
        'caliber_name': caliberName,
      };
    }).toList();

    // Pak filtrujeme
    var filtered = mapped;

    if (selectedCaliber != null && selectedCaliber != "Vše") {
      filtered = filtered.where((cartridge) {
        final matches = cartridge['caliber_name'] == selectedCaliber;
        print(
            "Kontrola kalibru: ${cartridge['name']} | Kalibr: ${cartridge['caliber_name']} | Shoda: $matches");
        return matches;
      }).toList();
    }

    if (!_showZeroStock) {
      filtered = filtered
          .where((cartridge) => (cartridge['stock_quantity'] ?? 0) > 0)
          .toList();
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
      _isLoading = true;
    });

    try {
      final isOnline =
          await Connectivity().checkConnectivity() != ConnectivityResult.none;
      final fetchedCartridges = await fetchCartridges(isOnline);

      if (!mounted) return;

      setState(() {
        // Rozdělení nábojů podle typu
        originalFactoryCartridges =
            fetchedCartridges.where((c) => c['type'] == 'factory').toList();

        originalReloadCartridges =
            fetchedCartridges.where((c) => c['type'] == 'reload').toList();

        // Aktualizace aktuálně zobrazených nábojů
        final currentCartridges = _showFactoryCartridges
            ? originalFactoryCartridges
            : originalReloadCartridges;

        _updateCartridges(List<Map<String, dynamic>>.from(currentCartridges));
        _updateCalibers();
      });
    } on Exception catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chyba při načítání: ${e.toString()}'),
          action: SnackBarAction(
            label: 'Opakovat',
            onPressed: _refreshCartridges,
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
    cartridges.name,
    cartridges.powder_weight,
    cartridges.stock_quantity,
    cartridges.velocity_ms,
    cartridges.oal,    
    cartridges.price,
    cartridges.caliber_id,
    cartridges.created_at,
    cartridges.updated_at,
    cartridges.manufacturer,
    cartridges.bullet_specification,
    cartridges.barcode,
    calibers.name AS caliber_name,
    cartridges.cartridge_type
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

  Future<void> _saveFactoryCartridge(
    String name,
    String barcode,
    String quantity,
    String? caliberId,
    String manufacturer,
    String bulletSpecification,
    String price,
  ) async {
    // Validate all required fields
    if (name.isEmpty ||
        caliberId == null ||
        manufacturer.isEmpty ||
        quantity.isEmpty ||
        price.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Vyplňte všechna povinná pole: název, kalibr, výrobce, počet kusů a cenu')),
      );
      return;
    }

    // Validate numeric fields
    if (int.tryParse(quantity) == null || double.tryParse(price) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Počet kusů a cena musí být čísla')),
      );
      return;
    }

    final factoryCartridgeData = {
      'name': name.trim(),
      'caliber_id': int.parse(caliberId),
      'type': 'factory',
      'stock_quantity': int.parse(quantity),
      'manufacturer': manufacturer.trim(),
      'price': double.parse(price),
      'barcode': barcode.isEmpty ? null : barcode.trim(),
      'bullet_specification':
          bulletSpecification.isEmpty ? null : bulletSpecification.trim(),
    };

    // Rest of the method stays the same...
    try {
      if (await isOnline()) {
        await ApiService.createFactoryCartridge(factoryCartridgeData);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Náboj byl úspěšně přidán')),
        );
      } else {
        await DatabaseHelper().addOfflineRequest(
          'create_factory_cartridge',
          factoryCartridgeData,
        );
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Náboj byl přidán do fronty pro synchronizaci')),
        );
      }
      _refreshCartridges();
    } catch (error) {
      print('Chyba při přidávání továrního náboje: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chyba při přidávání náboje')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventář nábojů'),
        backgroundColor: Colors.blueGrey,
        elevation: 0,
        actions: [
          StreamBuilder<bool>(
            stream: _connectivityHelper.onConnectionChange,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? false;
              _previousOnlineState = isOnline;

              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Stack(
                  children: [
                    Tooltip(
                      message: isOnline ? 'Online' : 'Offline',
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          isOnline ? Icons.cloud_done : Icons.cloud_off,
                          key: ValueKey(isOnline),
                          color: isOnline
                              ? Colors.lightBlueAccent
                              : Colors.grey.shade500,
                          size: 28,
                        ),
                      ),
                    ),
                    if (_pendingRequestsCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Text(
                          '$_pendingRequestsCount',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshCartridges,
        child: PageStorage(
          bucket: _bucket,
          child: Column(
            children: [
              _buildToggleButtons(),
              _buildZeroStockSwitch(),
              _buildCaliberDropdown(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : (_showFactoryCartridges
                            ? widget.factoryCartridges.isEmpty
                            : widget.reloadCartridges.isEmpty)
                        ? const Center(
                            child: Text(
                              'Žádné náboje nenalezeny',
                              style: TextStyle(fontSize: 16),
                            ),
                          )
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _buildCartridgeList(),
                              _buildCartridgeList(),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _showFactoryCartridges
          ? StreamBuilder<bool>(
              stream: _connectivityHelper.onConnectionChange,
              builder: (context, snapshot) {
                final isOnline = snapshot.data ?? false;

                return FloatingActionButton(
                  onPressed: isOnline
                      ? () => _showAddFactoryCartridgeDialog()
                      : null, // Disabled when offline
                  child: const Icon(Icons.add, color: Colors.white),
                  tooltip: isOnline
                      ? 'Přidat tovární náboj'
                      : 'Přidání náboje není v offline režimu dostupné',
                  backgroundColor: isOnline ? Colors.blueGrey : Colors.grey,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                );
              },
            )
          : null,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    onLongPress: _swapToggleButtons,
                    child: AnimatedContainer(
                      // Added animation
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _buildStyledButton(
                        icon: _factoryLeft
                            ? Icons.factory_outlined
                            : Icons.build_circle_outlined,
                        label: _factoryLeft ? 'Tovární' : 'Přebíjené',
                        isActive: _factoryLeft == _showFactoryCartridges,
                        onPressed: () {
                          setState(() {
                            _showFactoryCartridges = _factoryLeft;
                            _tabController.animateTo(_factoryLeft
                                ? 0
                                : 1); // Sync with TabController
                            _updateCartridges(_showFactoryCartridges
                                ? originalFactoryCartridges
                                : originalReloadCartridges);
                          });
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onLongPress: _swapToggleButtons,
                    child: AnimatedContainer(
                      // Added animation
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _buildStyledButton(
                        icon: _factoryLeft
                            ? Icons.build_circle_outlined
                            : Icons.factory_outlined,
                        label: _factoryLeft ? 'Přebíjené' : 'Tovární',
                        isActive: _factoryLeft != _showFactoryCartridges,
                        onPressed: () {
                          setState(() {
                            _showFactoryCartridges = !_factoryLeft;
                            _tabController.animateTo(!_factoryLeft
                                ? 0
                                : 1); // Sync with TabController
                            _updateCartridges(_showFactoryCartridges
                                ? originalFactoryCartridges
                                : originalReloadCartridges);
                          });
                        },
                      ),
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

  void _showAddFactoryCartridgeDialog() {
    final nameController = TextEditingController();
    final barcodeController = TextEditingController();
    final quantityController = TextEditingController();
    final manufacturerController = TextEditingController();
    final bulletSpecController = TextEditingController();
    final priceController = TextEditingController();
    String? selectedCaliberId;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text('Přidat tovární náboj'),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Základní informace',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Název náboje *',
                      prefixIcon: const Icon(Icons.label),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: manufacturerController,
                    decoration: InputDecoration(
                      labelText: 'Výrobce *',
                      prefixIcon: const Icon(Icons.factory),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCaliberSelector((String id) {
                    selectedCaliberId = id;
                  }),
                  const SizedBox(height: 20),
                  const Text(
                    'Technické údaje',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bulletSpecController,
                    decoration: InputDecoration(
                      labelText: 'Specifikace střely *',
                      prefixIcon: const Icon(Icons.adjust),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Skladové informace',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Cena *',
                            prefixIcon: const Icon(Icons.attach_money),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: quantityController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Počet kusů',
                            prefixIcon: const Icon(Icons.inventory),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: barcodeController,
                    decoration: InputDecoration(
                      labelText: 'Čárový kód',
                      prefixIcon: const Icon(Icons.qr_code),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Zrušit'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _saveFactoryCartridge(
                        nameController.text,
                        barcodeController.text,
                        quantityController.text,
                        selectedCaliberId,
                        manufacturerController.text,
                        bulletSpecController.text,
                        priceController.text,
                      ),
                      child: const Text('Přidat'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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

  Widget _buildCaliberSelector(Function(String) onCaliberSelected) {
    return FutureBuilder<List<dynamic>>(
      future: ApiService.getCalibers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Chyba při načítání kalibrů'),
          );
        }

        return Theme(
          data: Theme.of(context).copyWith(
            scrollbarTheme: ScrollbarThemeData(
              thumbVisibility: MaterialStateProperty.all(true),
              thickness: MaterialStateProperty.all(6.0),
            ),
          ),
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Kalibr *',
              prefixIcon: const Icon(Icons.adjust),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            isExpanded: true,
            menuMaxHeight:
                MediaQuery.of(context).size.height * 0.5, // Increased to 50%
            dropdownColor: Colors.white,
            icon: const Icon(Icons.arrow_drop_down),
            style: const TextStyle(color: Colors.black87, fontSize: 16),
            items: snapshot.data!.map((caliber) {
              return DropdownMenuItem<String>(
                value: caliber['id'].toString(),
                child: Text(
                  caliber['name'],
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: (value) => onCaliberSelected(value!),
          ),
        );
      },
    );
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
    print("Počet položek v dropdown menu: ${calibers.length}");
    print("Dostupné kalibry: ${calibers.join(', ')}");
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: calibers.contains(selectedCaliber) ? selectedCaliber : null,
            icon: const Icon(Icons.arrow_drop_down),
            isExpanded: true,
            menuMaxHeight: MediaQuery.of(context).size.height * 0.6,
            items: calibers
                .map((caliber) => DropdownMenuItem<String>(
                      value: caliber,
                      child: Text(
                        caliber ?? 'Neznámý kalibr',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ))
                .toList(),
            onChanged: (String? newValue) {
              setState(() {
                selectedCaliber = newValue;
                print("Vybraný kalibr: $newValue"); // Pro debug
              });
              _updateCartridges(_showFactoryCartridges
                  ? widget.factoryCartridges
                  : widget.reloadCartridges);
            },
          ),
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

    return RefreshIndicator(
      onRefresh: _refreshCartridges,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: filteredCartridges.length,
        itemBuilder: (context, index) {
          final cartridge = filteredCartridges[index];
          final name = cartridge['name'] ?? 'Neznámý náboj';
          final caliberId =
              cartridge['caliber_id'] ?? cartridge['caliber']?['id'];
          final caliberName = cartridge['caliber_name'] ??
              cartridge['caliber']?['name'] ??
              'Neznámý kalibr';
          final stock = cartridge['stock_quantity'] ?? 0;
          final hasBarcode =
              cartridge['barcode'] != null && cartridge['barcode'].isNotEmpty;
          final isMonitored = cartridge['caliber']?['is_monitored'] ?? false;

          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _navigateToDetail(cartridge),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name and Barcode section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (hasBarcode)
                            Icon(Icons.qr_code,
                                size: 20, color: Colors.grey[600]),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Info section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Caliber and Bell - Clickable
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => caliberId != null
                                  ? _showMonitoringDialog(caliberId)
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.adjust,
                                      size: 16,
                                      color: Colors.blueGrey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      caliberName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      isMonitored
                                          ? Icons.notifications_active
                                          : Icons.notifications_off,
                                      size: 16,
                                      color: isMonitored
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Stock Counter - Not clickable
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: stock > 0
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2,
                                  size: 16,
                                  color: stock > 0 ? Colors.green : Colors.red,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$stock ks',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        stock > 0 ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.w500,
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
              ),
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchMonitoringStatus(int caliberId) async {
    try {
      // Use caliber data from cartridge response
      final cartridge = widget.factoryCartridges.firstWhere(
        (c) => c['caliber']?['id'] == caliberId,
        orElse: () => widget.reloadCartridges.firstWhere(
          (c) => c['caliber']?['id'] == caliberId,
          orElse: () => {},
        ),
      );

      if (cartridge['caliber'] != null) {
        final caliber = cartridge['caliber'];
        return {
          'is_monitored': caliber['is_monitored'] ?? false,
          'monitoring_threshold': caliber['monitoring_threshold'] ?? 100,
          'name': caliber['name']
        };
      }

      // Fallback to DB
      final db = await DatabaseHelper().database;
      final result =
          await db.query('calibers', where: 'id = ?', whereArgs: [caliberId]);

      if (result.isNotEmpty) {
        return {
          'is_monitored': result.first['is_monitored'] == 1,
          'monitoring_threshold': result.first['monitoring_threshold'] ?? 100,
          'name': result.first['name']
        };
      }
    } catch (e) {
      print('Error in _fetchMonitoringStatus: $e');
    }
    return null;
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

  Future<List<Map<String, dynamic>>> _getCaliberCartridges(
      int caliberId) async {
    try {
      final db = await DatabaseHelper().database;

      // Clean SQL query without comments
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

  void _showMonitoringDialog(int caliberId) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blueGrey),
          ),
        ),
      );

      // Fetch data
      final status = await _fetchMonitoringStatus(caliberId);
      final totalStock = await _getCaliberTotalStock(caliberId);

      // Remove loading
      if (!mounted) return;
      Navigator.pop(context);

      // Handle errors
      if (status == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nepodařilo se načíst data kalibru')),
        );
        return;
      }

      // Setup state
      final caliberName = status['name'] ?? 'Neznámý kalibr';
      var isMonitored = status['is_monitored'] ?? false;
      var threshold = status['monitoring_threshold'] ?? 100;

      // Show dialog
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (dialogContext) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blueGrey,
              primary: Colors.blueGrey,
            ),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
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
                    _buildStockInfoSection(totalStock, caliberId),
                    const SizedBox(height: 16),
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
                                setDialogState(() => isMonitored = value),
                          ),
                          if (isMonitored) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: TextFormField(
                                initialValue: threshold.toString(),
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
                                onChanged: (value) => setDialogState(() =>
                                    threshold =
                                        int.tryParse(value) ?? threshold),
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
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Zrušit'),
                ),
                FilledButton(
                  onPressed: () => _saveMonitoringSettings(
                    caliberId: caliberId,
                    isMonitored: isMonitored,
                    threshold: threshold,
                    context: dialogContext,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                  ),
                  child: const Text('Uložit'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      print('Error in monitoring dialog: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Došlo k chybě při zpracování požadavku')),
      );
    }
  }

  Widget _buildStockInfoSection(int totalStock, int caliberId) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
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
          _buildCartridgesList(caliberId),
        ],
      ),
    );
  }

  Widget _buildCartridgesList(int caliberId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rozpis nábojů:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ...snapshot.data!.map((cartridge) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          cartridge['name'],
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '${cartridge['stock_quantity']} ks',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                )),
          ],
        );
      },
    );
  }

  Widget _buildMonitoringControls({
    required bool isMonitored,
    required int threshold,
    required ValueChanged<bool> onMonitoringChanged,
    required ValueChanged<int> onThresholdChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Zapnout monitorování'),
            subtitle: const Text('Upozornění při nízkém stavu'),
            value: isMonitored,
            onChanged: onMonitoringChanged,
          ),
          if (isMonitored) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextFormField(
                initialValue: threshold.toString(),
                decoration: InputDecoration(
                  labelText: 'Minimální množství',
                  suffix: const Text('ks'),
                  helperText: 'Zobrazit varování při poklesu pod tuto hodnotu',
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) =>
                    onThresholdChanged(int.tryParse(value) ?? threshold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveMonitoringSettings({
    required int caliberId,
    required bool isMonitored,
    required int threshold,
    required BuildContext context,
  }) async {
    try {
      final success =
          await _toggleMonitoring(caliberId, isMonitored, threshold);
      if (success && context.mounted) {
        Navigator.pop(context);
        _refreshCartridges();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMonitored
                  ? 'Monitorování kalibru bylo zapnuto'
                  : 'Monitorování kalibru bylo vypnuto',
            ),
          ),
        );
      }
    } catch (e) {
      print('Error saving monitoring settings: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chyba při ukládání nastavení')),
        );
      }
    }
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
