import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart'; // Import API služby

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
  bool _showFactoryCartridges = true;
  bool _showZeroStock = false;
  String? selectedCaliber;
  List<String> calibers = []; // Seznam kalibrů pro filtr

  @override
  void initState() {
    super.initState();
    // Načtení počátečního seznamu kalibrů
    _updateCalibers();
  }

  void _updateCalibers() {
    // Dynamické načítání kalibrů na základě aktuální záložky
    calibers = _getUniqueCalibers(_showFactoryCartridges
        ? widget.factoryCartridges
        : widget.reloadCartridges);
    calibers.insert(0, "Vše"); // Přidání možnosti "Vše" na začátek seznamu
    selectedCaliber = "Vše"; // Výchozí hodnota
  }

  List<String> _getUniqueCalibers(List<Map<String, dynamic>> cartridges) {
    return cartridges
        .map((cartridge) => cartridge['caliber']['name'] as String)
        .toSet()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventář Nábojů'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Column(
        children: [
          // Přepínač mezi továrními a přebíjenými náboji
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ToggleButtons(
              isSelected: [_showFactoryCartridges, !_showFactoryCartridges],
              onPressed: (index) {
                setState(() {
                  _showFactoryCartridges = index == 0;
                  _updateCalibers(); // Aktualizace kalibrů při změně záložky
                });
              },
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Tovární náboje'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Přebíjené náboje'),
                ),
              ],
            ),
          ),

          // Tlačítko pro zobrazení/skrytí nábojů s nulovou dostupností
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Zobrazit náboje s nulovou dostupností'),
                Switch(
                  value: _showZeroStock,
                  onChanged: (value) {
                    setState(() {
                      _showZeroStock = value;
                    });
                  },
                ),
              ],
            ),
          ),

          // Dropdown pro výběr kalibru
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: DropdownButton<String>(
              value: selectedCaliber,
              hint: const Text("Vyberte kalibr"),
              onChanged: (String? newValue) {
                setState(() {
                  selectedCaliber = newValue;
                });
              },
              isExpanded: true,
              items: calibers
                  .map((caliber) => DropdownMenuItem<String>(
                        value: caliber,
                        child: Text(caliber),
                      ))
                  .toList(),
            ),
          ),

          // Zobrazení nábojů podle přepínače a filtru kalibru
          Expanded(
            child: _showFactoryCartridges
                ? _buildCartridgeSection(widget.factoryCartridges, context)
                : _buildCartridgeSection(widget.reloadCartridges, context),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterByCaliber(
      List<Map<String, dynamic>> cartridges) {
    var filtered = cartridges;

    // Filtr kalibru
    if (selectedCaliber != null && selectedCaliber != "Vše") {
      filtered = filtered
          .where((cartridge) => cartridge['caliber']['name'] == selectedCaliber)
          .toList();
    }

    // Filtr pro náboje s nulovou dostupností
    if (!_showZeroStock) {
      filtered = filtered
          .where((cartridge) => (cartridge['stock_quantity'] ?? 0) > 0)
          .toList();
    }

    return filtered;
  }

  Widget _buildCartridgeSection(
      List<Map<String, dynamic>> cartridges, BuildContext context) {
    final filteredCartridges = _filterByCaliber(cartridges);
    return ListView.builder(
      itemCount: filteredCartridges.length,
      itemBuilder: (context, index) {
        final cartridge = filteredCartridges[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            title: Text(
              cartridge['name'],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'Kalibr: ${cartridge['caliber']['name']}, Cena: ${cartridge['price']} Kč, Sklad: ${cartridge['stock_quantity']} ks',
              style: const TextStyle(fontSize: 16),
            ),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              // Otevření detailní obrazovky pro daný náboj
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CartridgeDetailScreen(
                    cartridge: cartridge,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
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
  List<dynamic> userActivities = [];
  List<dynamic> userWeapons = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchUserActivities();
  }

  Future<void> _fetchUserActivities() async {
    setState(() {
      isLoading = true;
    });
    try {
      final activitiesResponse = await ApiService.getUserActivities();
      setState(() {
        userActivities = activitiesResponse;
      });
    } catch (e) {
      print('Chyba při načítání aktivit: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _fetchCompatibleWeapons(int caliberId) async {
    try {
      final weaponsResponse =
          await ApiService.getUserWeaponsByCaliber(caliberId);
      setState(() {
        userWeapons = weaponsResponse;
      });
      _showWeaponsDialog();
    } catch (e) {
      print('Chyba při načítání kompatibilních zbraní: $e');
    }
  }

  void _showWeaponsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Zbraně odpovídající kalibru'),
          content: userWeapons.isNotEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: userWeapons.map((weapon) {
                    return ListTile(
                      title: Text(weapon['name']),
                      subtitle: Text('ID: ${weapon['id']}'),
                      onTap: () {
                        Navigator.of(context)
                            .pop(); // Zavřít dialog po výběru zbraně
                        _showShootingLogForm(context, weapon);
                      },
                    );
                  }).toList(),
                )
              : Text('Žádné zbraně odpovídající kalibru nebyly nalezeny.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Zavřít dialog
              },
              child: const Text('Zavřít'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartridge = widget.cartridge;
    return Scaffold(
      appBar: AppBar(
        title: Text(cartridge['name']),
        backgroundColor: Colors.blueGrey,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Název náboje
              Text(
                cartridge['name'],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              if (cartridge['type'] == 'factory') ...[
                // Kalibr a komponenty pro tovární náboj
                _buildSectionTitle('Kalibr a Výrobce'),
                _buildStripedInfoRow('Kalibr', cartridge['caliber']['name'], 0),
                _buildStripedInfoRow(
                    'Výrobce', cartridge['manufacturer'] ?? 'Neznámý', 1),
                _buildStripedInfoRow('Specifikace střely',
                    cartridge['bullet_specification'] ?? 'Neznámá střela', 2),
              ] else ...[
                // Kalibr a komponenty pro přebíjený náboj
                _buildSectionTitle('Kalibr a Komponenty'),
                _buildStripedInfoRow('Kalibr', cartridge['caliber']['name'], 0),
                _buildStripedInfoRow(
                    'Střela',
                    cartridge['bullet'] != null
                        ? '${cartridge['bullet']['manufacturer']} - ${cartridge['bullet']['name']} (${cartridge['bullet']['weight_grains']} gr)'
                        : 'Neznámá střela',
                    1),
                _buildStripedInfoRow(
                    'Prach',
                    cartridge['powder'] != null
                        ? '${cartridge['powder']['manufacturer']} - ${cartridge['powder']['name']}'
                        : 'Neznámý prach',
                    2),
                _buildStripedInfoRow(
                    'Navážka prachu',
                    cartridge['powder_weight'] != null
                        ? '${cartridge['powder_weight']} gr'
                        : 'Neznámá navážka',
                    3),
                _buildStripedInfoRow(
                    'Zápalka',
                    cartridge['primer'] != null
                        ? '${cartridge['primer']['categories']} - ${cartridge['primer']['name']}'
                        : 'Neznámá zápalka',
                    4),

                const SizedBox(height: 16),

                // Technické informace pro přebíjený náboj
                _buildSectionTitle('Technické Informace'),
                _buildStripedInfoRow(
                    'OAL',
                    cartridge['oal'] != null
                        ? '${cartridge['oal']} mm'
                        : 'Neznámá délka',
                    5),
                _buildStripedInfoRow(
                    'Rychlost',
                    cartridge['velocity_ms'] != null
                        ? '${cartridge['velocity_ms']} m/s'
                        : 'Neznámá rychlost',
                    6),
                _buildStripedInfoRow(
                    'Standardní deviace',
                    cartridge['standard_deviation'] != null
                        ? '${cartridge['standard_deviation']}'
                        : 'Neznámá',
                    7),
              ],

              const SizedBox(height: 16),

              // Cena a skladem kusů
              _buildSectionTitle('Cena a Dostupnost'),
              _buildStripedInfoRow('Cena', '${cartridge['price']} Kč', 8),
              _buildStripedInfoRow(
                  'Sklad', '${cartridge['stock_quantity']} ks', 9),

              const SizedBox(height: 24),

              // Tlačítko pro přidání záznamu do střeleckého deníku
              Center(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _fetchCompatibleWeapons(
                        widget.cartridge['caliber']['id']);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Přidat záznam do střeleckého deníku'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16.0, horizontal: 24.0),
                    textStyle: const TextStyle(fontSize: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          8.0), // Místo 12 snížíme zaobléní na 8
                    ),
                  ),
                ),
              ),
            ],
          ),
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

  Widget _buildStripedInfoRow(String label, String value, int rowIndex) {
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
          Text(value),
        ],
      ),
    );
  }

  void _showShootingLogForm(
      BuildContext context, Map<String, dynamic> selectedWeapon) {
    TextEditingController ammoCountController = TextEditingController();
    TextEditingController noteController = TextEditingController();

    // Přednastavené dnešní datum
    String todayDate = DateTime.now().toIso8601String().substring(0, 10);
    TextEditingController dateController =
        TextEditingController(text: todayDate);

    String? selectedActivity;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
              'Přidat záznam do střeleckého deníku pro ${widget.cartridge['name']} a zbraň ${selectedWeapon['name']}'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: ammoCountController,
                  decoration:
                      InputDecoration(labelText: 'Počet vystřelených nábojů'),
                  keyboardType: TextInputType.number,
                ),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: 'Typ aktivity'),
                  value: selectedActivity,
                  items:
                      userActivities.map<DropdownMenuItem<String>>((activity) {
                    return DropdownMenuItem<String>(
                      value: activity['activity_name'],
                      child: Text(activity['activity_name']),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedActivity = value;
                    });
                  },
                ),
                TextField(
                  controller: dateController,
                  decoration: InputDecoration(labelText: 'Datum (YYYY-MM-DD)'),
                ),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(labelText: 'Poznámka'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Zavřít dialog bez uložení
              },
              child: const Text('Zrušit'),
            ),
            TextButton(
              onPressed: () {
                if (ammoCountController.text.isNotEmpty &&
                    selectedActivity != null &&
                    dateController.text.isNotEmpty) {
                  _createShootingLog(
                    selectedWeapon['id'],
                    int.parse(ammoCountController.text),
                    selectedActivity!,
                    dateController.text,
                    noteController.text,
                  );
                  Navigator.of(context).pop(); // Zavřít dialog po uložení
                } else {
                  print('Chyba: Vyplňte všechna povinná pole');
                }
              },
              child: const Text('Uložit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createShootingLog(
    int weaponId,
    int shotsFired,
    String activityType,
    String date,
    String note,
  ) async {
    if (widget.cartridge['id'] == null) {
      print('Chyba: Naskenovaný náboj nebo cartridge data nejsou k dispozici');
      return;
    }

    try {
      final response = await ApiService.createShootingLog({
        "weapon_id": weaponId,
        "cartridge_id": widget.cartridge['id'],
        "activity_type": activityType,
        "shots_fired": shotsFired,
        "date": date,
        "note": note,
      });

      if (response.containsKey('success') && response['success'] == true) {
        print('Záznam ve střeleckém deníku byl úspěšně vytvořen: $response');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Záznam úspěšně uložen. ID: ${response['shooting_log_id']}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['error'] ?? 'Chyba při ukládání.')),
        );
      }
    } catch (e) {
      print('Chyba při vytváření záznamu ve střeleckém deníku: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při vytváření záznamu.')),
      );
    }
  }
}
