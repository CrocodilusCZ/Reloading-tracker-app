import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart'; // Import API služby
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/screens/cartridge_detail_screen.dart';

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

  @override
  void initState() {
    super.initState();
    originalFactoryCartridges = List.from(widget.factoryCartridges);
    originalReloadCartridges = List.from(widget.reloadCartridges);
    calibers = _getUniqueCalibers(
        [...originalFactoryCartridges, ...originalReloadCartridges]);
    calibers.insert(0, "Vše");
    selectedCaliber = "Vše";
  }

  void _updateCartridges(List<Map<String, dynamic>> cartridges) {
    print("Aktualizuji náboje...");
    print("Před filtrem: ${cartridges.length} nábojů");

    final sourceCartridges = _showFactoryCartridges
        ? originalFactoryCartridges
        : originalReloadCartridges;

    final filteredCartridges = _filterByCaliber(sourceCartridges);

    print("Po filtru: ${filteredCartridges.length} nábojů");

    setState(() {
      if (_showFactoryCartridges) {
        widget.factoryCartridges.clear();
        widget.factoryCartridges.addAll(filteredCartridges);
      } else {
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
    print("Před filtrem: ${cartridges.length} nábojů");

    var filtered = cartridges;

    if (selectedCaliber != null && selectedCaliber != "Vše") {
      filtered = filtered.where((cartridge) {
        String? caliberName;

        // Podpora různých zdrojů dat (SQLite nebo API)
        if (cartridge.containsKey('caliber_name') &&
            cartridge['caliber_name'] != null) {
          caliberName = cartridge['caliber_name'] as String;
        } else if (cartridge['caliber'] != null &&
            cartridge['caliber']['name'] != null) {
          caliberName = cartridge['caliber']['name'] as String;
        }

        return caliberName == selectedCaliber;
      }).toList();
      print("Po filtru kalibru: ${filtered.length} nábojů");
    }

    if (!_showZeroStock) {
      filtered = filtered.where((cartridge) {
        final stockQuantity = cartridge['stock_quantity'] ?? 0;
        return stockQuantity > 0;
      }).toList();
      print("Po filtru skladové dostupnosti: ${filtered.length} nábojů");
    }

    return filtered;
  }

  Future<List<Map<String, dynamic>>> fetchCartridges(bool isOnline) async {
    try {
      if (isOnline) {
        final apiCartridges = await ApiService.getAllCartridges();

        if (apiCartridges == null) {
          throw Exception('Žádná data z API.');
        }

        final factory = apiCartridges['factory'] ?? [];
        final reload = apiCartridges['reload'] ?? [];
        print(
            "Načteno z API: Factory=${factory.length}, Reload=${reload.length}");

        return [...factory, ...reload];
      } else {
        return await fetchCartridgesFromSQLite();
      }
    } catch (e) {
      print("Chyba při načítání dat: $e");
      return await fetchCartridgesFromSQLite();
    }
  }

  Future<List<Map<String, dynamic>>> fetchCartridgesFromSQLite() async {
    try {
      final db = await DatabaseHelper().database;
      final data = await db.rawQuery('''
    SELECT cartridges.*, calibers.name AS caliber_name
    FROM cartridges
    LEFT JOIN calibers ON cartridges.caliber_id = calibers.id
    ''');

      if (data.isEmpty) {
        throw Exception('Žádné náboje nejsou dostupné v offline režimu.');
      }

      print(
          "Načtené cartridge s kalibry: ${data.map((e) => e.toString()).join('\n')}");
      return data;
    } catch (e) {
      print("Chyba při načítání dat z SQLite: $e");
      throw Exception('Chyba při načítání dat z lokální databáze.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventář Nábojů'),
        backgroundColor: Colors.blueGrey,
      ),
      body: PageStorage(
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
    );
  }

  Widget _buildToggleButtons() {
    return Card(
      elevation: 3,
      color: Colors.grey.shade200,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Center(
          child: ToggleButtons(
            borderRadius: BorderRadius.circular(10),
            selectedColor: Colors.white,
            fillColor: Colors.blueGrey,
            color: Colors.blueGrey,
            isSelected: [
              _showFactoryCartridges,
              !_showFactoryCartridges,
            ],
            onPressed: (index) {
              setState(() {
                _showFactoryCartridges = index == 0;
                _updateCalibers();
              });
            },
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Tovární náboje',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Přebíjené náboje',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
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
              onChanged: (value) {
                setState(() {
                  _showZeroStock = value;
                  _updateCartridges(_showFactoryCartridges
                      ? originalFactoryCartridges
                      : originalReloadCartridges);
                });
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

    if (filteredCartridges.isEmpty) {
      return const Center(
        child: Text(
          'Žádné náboje odpovídající filtru.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredCartridges.length,
      itemBuilder: (context, index) {
        final cartridge = filteredCartridges[index];
        final name = cartridge['name'] ?? 'Neznámý náboj';

        // Získání názvu kalibru
        final caliberName = cartridge.containsKey('caliber_name')
            ? cartridge['caliber_name']
            : (cartridge['caliber']?['name'] ?? 'Neznámý kalibr');
        final stock = cartridge['stock_quantity'] ?? 0;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 3,
          child: ListTile(
            title: Text(name),
            subtitle: Text('Kalibr: $caliberName, Sklad: $stock ks'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CartridgeDetailScreen(cartridge: cartridge),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
