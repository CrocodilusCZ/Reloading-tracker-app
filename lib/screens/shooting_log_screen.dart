import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:math';
import 'package:shooting_companion/services/api_service.dart'; // Import API služby
import 'package:vibration/vibration.dart'; // Import balíčku vibration
import 'package:shooting_companion/services/weapon_service.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ShootingLogScreen extends StatefulWidget {
  const ShootingLogScreen({Key? key}) : super(key: key);

  @override
  _ShootingLogScreenState createState() => _ShootingLogScreenState();
}

class _ShootingLogScreenState extends State<ShootingLogScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  String? scannedCode;
  String? cartridgeInfo; // Proměnná pro zobrazení informací o náboji
  Map<String, dynamic>? cartridgeData; // Proměnná pro uložení dat z API
  List<dynamic> userWeapons = []; // Proměnná pro zbraně uživatele
  List<dynamic> userActivities = []; // Proměnná pro aktivity uživatele
  List<dynamic> userRanges = []; // Proměnná pro střelnice uživatele
  String? selectedRange; // Přidána proměnná pro aktuální výběr střelnice
  String? dialogSelectedRange = "Bez střelnice";
  bool isLoading = false; // Přidána proměnná isLoading pro sledování načítání
  bool isRangeInitialized = false; // Sleduje, zda je střelnice inicializována
  bool isFlashOn = false; // Výchozí stav svítilny
  bool isAmmoError = false; // Indikuje, zda je problém s počtem nábojů
  String? errorMessage; // Pro ukládání chybové zprávy

  @override
  void initState() {
    super.initState();
    _checkAndRequestLocationPermission(); // Kontrola a žádost o oprávnění k poloze
    _fetchUserRangesAndSelectNearest(); // Načtení střelnic a předvýběr nejbližší
    dialogSelectedRange = selectedRange; // Přiřazení hodnoty po inicializaci
  }

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller?.pauseCamera();
    } else if (Platform.isIOS) {
      controller?.resumeCamera();
    }
  }

  @override
  void dispose() {
    controller?.dispose(); // Uvolnění kamery při ukončení
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      setState(() {
        scannedCode = scanData.code; // Uložení naskenovaného kódu
      });
      if (scannedCode != null) {
        controller.pauseCamera(); // Pauza kamery po naskenování kódu
        _fetchCartridgeInfo(
            scannedCode!); // Volání API pro zjištění informací o náboji
      }
    });
  }

  // Funkce pro výpočet vzdálenosti mezi dvěma body podle Haversinovy formule
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Poloměr Země v kilometrech
    final double dLat = (lat2 - lat1) * pi / 180;
    final double dLon = (lon2 - lon1) * pi / 180;

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c; // Vzdálenost v kilometrech
  }

// Funkce pro předvýběr nejbližší střelnice
  String? _getNearestRange(
      List<dynamic> ranges, double userLat, double userLon) {
    double? minDistance;
    String? nearestRange;

    for (final range in ranges) {
      final String location = range['location'];
      try {
        // Parsování souřadnic střelnice
        final List<String> coords = location.split(',');
        final double rangeLat = double.parse(coords[0].trim());
        final double rangeLon = double.parse(coords[1].trim());

        print('Souřadnice střelnice: $rangeLat, $rangeLon');

        // Výpočet vzdálenosti
        final double distance =
            _calculateDistance(userLat, userLon, rangeLat, rangeLon);

        print('Vzdálenost ke střelnici "${range['name']}": $distance km');

        // Aktualizace nejbližší střelnice
        if (minDistance == null || distance < minDistance) {
          minDistance = distance;
          nearestRange = range['name'];
        }
      } catch (e) {
        print('Chyba při parsování souřadnic střelnice: $e, data: $location');
      }
    }

    print(
        'Nejbližší střelnice: $nearestRange, vzdálenost: ${minDistance ?? 0} km');
    return nearestRange;
  }

  Future<void> _fetchUserRangesAndSelectNearest() async {
    try {
      final rangesResponse = await ApiService.getUserRanges();
      setState(() {
        userRanges = rangesResponse ?? [];
        isRangeInitialized = true;
      });

      if (userRanges.isEmpty) {
        print('Žádné střelnice nebyly nalezeny.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Žádné střelnice nebyly nalezeny')),
        );
        return;
      }

      final currentPosition = await _getCurrentLocation();
      final nearestRange = _getNearestRange(
        userRanges,
        currentPosition.latitude,
        currentPosition.longitude,
      );

      setState(() {
        selectedRange = nearestRange;
      });

      if (mounted && nearestRange != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Střelnice byla automaticky vybrána na základě polohy',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        nearestRange,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF2C3E50),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(8),
          ),
        );
      }

      print('Předvybraná střelnice: $selectedRange');
    } catch (e) {
      print('Chyba při načítání střelnic: $e');
      setState(() {
        isRangeInitialized = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chyba při načítání střelnic')),
        );
      }
    }
  }

  Future<void> _checkAndRequestLocationPermission() async {
    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        // Služba polohy není zapnutá
        throw 'Služba určování polohy je zakázaná. Zapněte ji v nastavení.';
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Oprávnění k poloze bylo zamítnuto.';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Uživatel trvale zakázal oprávnění
        throw 'Oprávnění k poloze je trvale zakázáno. Upravte to v nastavení.';
      }

      print('Oprávnění k poloze úspěšně uděleno.');
    } catch (e) {
      print('Chyba při kontrole oprávnění k poloze: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
          ),
        ),
      );
    }
  }

  Future<Position> _getCurrentLocation() async {
    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      print('Služba polohy aktivní: $isServiceEnabled');

      if (!isServiceEnabled) {
        throw 'Služba určování polohy je zakázaná.';
      }

      var permission = await Geolocator.checkPermission();
      print('Aktuální oprávnění: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        print('Oprávnění po žádosti: $permission');
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        throw 'Přístup k poloze je zakázán.';
      }

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      print('Získaná poloha: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('Chyba při získávání polohy: $e');
      throw Exception('Nepodařilo se získat polohu.');
    }
  }

  Future<bool> isOnline() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    return connectivityResult != ConnectivityResult.none;
  }

  //Ovládání svítilny
  Future<void> _toggleFlash() async {
    try {
      await controller!.toggleFlash(); // Přepnutí svítilny
      final flashStatus =
          await controller!.getFlashStatus(); // Získání aktuálního stavu
      setState(() {
        isFlashOn = flashStatus ?? false; // Aktualizace stavu podle výsledku
      });
      print('Stav svítilny: $flashStatus');
    } catch (e) {
      print('Chyba při přepínání svítilny: $e');
    }
  }

  void _simulateQRScan() {
    print('Simulace QR kódu spuštěna');
    setState(() {
      scannedCode = 'TEST_CODE_123';
    });

    print('Naskenovaný kód: $scannedCode');
    _fetchCartridgeInfo(scannedCode!);
  }

  void _showCartridgeInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Informace o náboji'),
          content: Text(cartridgeInfo ?? 'Žádné informace k zobrazení.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Po potvrzení pokračovat na výběr zbraní
                _fetchUserWeapons(cartridgeData!['cartridge']['caliber']['id']);
              },
              child: const Text('Pokračovat'),
            ),
          ],
        );
      },
    );
  }

  // Add to _fetchCartridgeInfo method:
  Future<void> _fetchCartridgeInfo(String code) async {
    print('Hledám náboj pro kód: $code');

    try {
      final dbHelper = DatabaseHelper();

      // First try local database
      final localCartridge = await dbHelper.getCartridgeByBarcode(code);
      print('Database query result: $localCartridge');

      if (localCartridge != null) {
        print('Náboj nalezen v lokální DB');
        setState(() {
          cartridgeData = {
            'cartridge': {
              ...localCartridge,
              'caliber': {
                'id': localCartridge['caliber_id'],
                'name': localCartridge['caliber_name']
              }
            }
          };
          cartridgeInfo = 'Náboj: ${localCartridge['name']}\n'
              'Kalibr: ${localCartridge['caliber_name']}\n'
              'Sklad: ${localCartridge['stock_quantity']} ks';
        });
        _showCartridgeInfoDialog();
        return;
      }

      // If not found locally, try online API
      final bool online = await isOnline();
      if (online) {
        final apiResponse = await ApiService.checkBarcode(code);
        if (apiResponse['cartridge'] != null) {
          setState(() {
            cartridgeData = apiResponse;
            cartridgeInfo = 'Náboj: ${apiResponse['cartridge']['name']}\n'
                'Kalibr: ${apiResponse['cartridge']['caliber']['name']}\n'
                'Sklad: ${apiResponse['cartridge']['stock_quantity']} ks';
          });
          _showCartridgeInfoDialog();
          return;
        }
      }

      // Not found anywhere
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Náboj nebyl nalezen nikde')),
      );
    } catch (e) {
      print('Chyba při hledání náboje: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      controller?.resumeCamera();
    }
  }

  //Metoda pro načtení střelnic
  Future<void> _fetchUserRanges() async {
    try {
      final rangesResponse = await ApiService.getUserRanges();
      print('Odpověď z API: $rangesResponse'); // Debug výstup
      if (rangesResponse is List) {
        setState(() {
          userRanges = rangesResponse; // Uložení odpovědi do userRanges
        });
        print('Střelnice úspěšně načteny: $userRanges'); // Potvrzení uložení
      } else {
        print('Neočekávaný formát odpovědi: $rangesResponse');
      }
    } catch (e) {
      print('Chyba při načítání střelnic: $e');
    }
  }

  // Volání API pro získání zbraní uživatele odpovídajících kalibru
  Future<void> _fetchUserWeapons(int caliberId) async {
    try {
      final weapons = await WeaponService.fetchWeaponsByCaliber(caliberId);
      setState(() {
        userWeapons = weapons;
      });
      _showWeaponsDialog();
    } catch (e) {
      print('Chyba při načítání zbraní: $e');
      controller?.resumeCamera();
    }
  }

  // Volání API pro získání aktivit uživatele
  Future<void> _fetchUserActivities() async {
    setState(() {
      isLoading = true;
    });

    try {
      final bool online = await isOnline();

      if (online) {
        try {
          final activitiesResponse = await ApiService.getUserActivities();
          setState(() {
            userActivities = activitiesResponse;
          });
        } catch (e) {
          print('Chyba při online načítání aktivit: $e');
          // Fallback to offline
          final localActivities = await DatabaseHelper().getActivities();
          setState(() {
            userActivities = localActivities;
          });
        }
      } else {
        // Offline mode
        print('Načítám aktivity z offline databáze...');
        final localActivities = await DatabaseHelper().getActivities();
        setState(() {
          userActivities = localActivities;
        });
      }
    } catch (e) {
      print('Chyba při načítání aktivit: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při načítání aktivit')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Zobrazení dialogového okna s výpisem aktivit
  void _showActivitiesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Vyberte aktivitu'),
          content: userActivities.isNotEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: userActivities.map((activity) {
                    return ListTile(
                      title: Text(activity['activity_name']),
                      subtitle: Text('Datum: ${activity['date'] ?? 'N/A'}'),
                      onTap: () {
                        Navigator.of(context)
                            .pop(); // Zavřít dialog po výběru aktivity
                        _showShootingLogForm(
                            activity['id']); // Použijte ID aktivity
                      },
                    );
                  }).toList(),
                )
              : Text('Žádné aktivity nebyly nalezeny.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Zavřít dialog bez výběru
              },
              child: const Text('Zavřít'),
            ),
          ],
        );
      },
    );
  }

  // Zobrazení dialogového okna s výpisem zbraní
  // In shooting_log_screen.dart
  void _showWeaponsDialog() {
    controller?.pauseCamera(); // Pauza kamery při otevření dialogu

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
              'Vyberte zbraň pro ${cartridgeData?['cartridge']?['name'] ?? 'Neznámý náboj'}'),
          content: userWeapons.isNotEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: userWeapons
                      .map((weapon) {
                        // Add null checks for weapon data
                        final name = weapon['weapon_name'] ??
                            weapon['name'] ??
                            'Neznámá zbraň';
                        final id = weapon['weapon_id']?.toString() ??
                            weapon['id']?.toString();

                        if (id == null) {
                          print('Warning: Weapon without ID: $weapon');
                          return SizedBox.shrink(); // Skip invalid weapons
                        }

                        return ListTile(
                          title: Text(name),
                          subtitle: Text('ID: $id'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showShootingLogForm(int.parse(id));
                          },
                        );
                      })
                      .where((widget) => widget is ListTile)
                      .toList(), // Filter out null widgets
                )
              : Text('Žádné zbraně odpovídající kalibru nebyly nalezeny.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Zavřít'),
            ),
          ],
        );
      },
    ).then((_) {
      controller?.resumeCamera();
    });
  }

  void _showShootingLogForm(int weaponId) async {
    if (!isRangeInitialized) {
      await _fetchUserRangesAndSelectNearest();
    }

    if (!isRangeInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Načítám data střelnice, zkuste to prosím za chvíli.'),
        ),
      );
      return;
    }

    // Debugovací výstup pro kontrolu dostupných střelnic
    print('Před zobrazením formuláře - dostupné střelnice: $userRanges');

    // Inicializace dialogSelectedRange podle aktuální hodnoty selectedRange
    dialogSelectedRange = selectedRange ?? 'Bez střelnice';

    await _fetchUserActivities();

    if (isLoading) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return Center(
            child: CircularProgressIndicator(),
          );
        },
      );
      return;
    }

    TextEditingController ammoCountController = TextEditingController();
    TextEditingController noteController = TextEditingController();
    String todayDate = DateTime.now().toIso8601String().substring(0, 10);
    TextEditingController dateController =
        TextEditingController(text: todayDate);
    String? selectedActivity;

    // Vytvoříme StatefulBuilder pro aktualizaci stavu uvnitř dialogu
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Vytvoření záznamu ve střeleckém deníku'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: ammoCountController,
                      decoration: InputDecoration(
                          labelText: 'Počet vystřelených nábojů'),
                      keyboardType: TextInputType.number,
                    ),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(labelText: 'Typ aktivity'),
                      value: selectedActivity,
                      items: userActivities
                          .map<DropdownMenuItem<String>>((activity) {
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
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Střelnice'),
                      value: dialogSelectedRange,
                      items: [
                        const DropdownMenuItem<String>(
                          value:
                              "Bez střelnice", // Hodnota musí být konzistentní
                          child: Text('Bez střelnice'),
                        ),
                        ...userRanges.map<DropdownMenuItem<String>>((range) {
                          return DropdownMenuItem<String>(
                            value: range[
                                'name'], // Předpokládáme, že střelnice má pole 'name'
                            child: Text(range['name']),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setState(() {
                          dialogSelectedRange = value;
                        });
                      },
                    ),
                    TextField(
                      controller: dateController,
                      decoration:
                          InputDecoration(labelText: 'Datum (YYYY-MM-DD)'),
                    ),
                    TextField(
                      controller: noteController,
                      decoration: InputDecoration(labelText: 'Poznámka'),
                    ),
                    SizedBox(height: 10),
                    FutureBuilder<Position>(
                      future: _getCurrentLocation(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Text('Načítám souřadnice...');
                        } else if (snapshot.hasError) {
                          return Text(
                              'Chyba při získávání souřadnic: ${snapshot.error}');
                        } else if (snapshot.hasData) {
                          return Text(
                            'Aktuální poloha: Lat: ${snapshot.data!.latitude}, Lon: ${snapshot.data!.longitude}',
                            style: TextStyle(color: Colors.grey),
                          );
                        }
                        return Text('Nepodařilo se získat souřadnice');
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Zrušit'),
                ),
                TextButton(
                  onPressed: () {
                    final shotsFired = int.tryParse(ammoCountController.text);
                    if (shotsFired == null ||
                        shotsFired <= 0 ||
                        selectedActivity == null) {
                      setState(() {
                        isAmmoError = shotsFired == null || shotsFired <= 0;
                        errorMessage = 'Vyplňte všechna povinná pole!';
                      });
                      return;
                    }

                    // Zavolání metody _createShootingLog s chybovým callbackem
                    _createShootingLog(
                      weaponId,
                      shotsFired,
                      selectedActivity!,
                      dialogSelectedRange,
                      dateController.text,
                      noteController.text,
                      (error) {
                        // Callback pro zpracování chyby
                        setState(() {
                          errorMessage = error;
                          if (error == 'Not enough ammunition.') {
                            isAmmoError =
                                true; // Nastavení chyby u počtu nábojů
                          }
                        });
                      },
                    );
                  },
                  child: const Text('Uložit'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      controller?.resumeCamera();
    });
  }

  // Vytvoření záznamu ve střeleckém deníku
  Future<void> _createShootingLog(
    int weaponId,
    int shotsFired,
    String activityType,
    String? rangeName,
    String date,
    String note,
    Function(String) onErrorCallback,
  ) async {
    final dbHelper = DatabaseHelper();

    final shootingLogData = {
      "weapon_id": weaponId,
      "cartridge_id": cartridgeData!['cartridge']['id'],
      "activity_type": activityType,
      "range": rangeName,
      "shots_fired": shotsFired,
      "date": date,
      "note": note,
    };

    try {
      bool online = await isOnline();

      if (online) {
        try {
          final response = await ApiService.createShootingLog(shootingLogData);

          if (response != null && response['success'] == true) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Záznam úspěšně uložen. ID: ${response['shooting_log_id']}'),
                duration: const Duration(seconds: 3),
              ),
            );

            // Check for warning
            if (response['warning'] != null) {
              final warning = response['warning'];
              if (warning['type'] == 'low_stock') {
                await Future.delayed(const Duration(seconds: 1));

                final cartridgesList = (warning['cartridges'] as List)
                    .map((c) => '${c['name']}: ${c['stock']} ks')
                    .join('\n');

                ScaffoldMessenger.of(context).showSnackBar(
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

            Navigator.of(context).pop();
            return; // Success - exit early
          }

          throw Exception(response['error'] ?? 'Chyba při ukládání.');
        } catch (e) {
          print('API Error: $e');
          await _saveOfflineShootingLog(shootingLogData, dbHelper);
        }
      } else {
        await _saveOfflineShootingLog(shootingLogData, dbHelper);
      }
    } catch (e) {
      print('Chyba při vytváření záznamu: $e');
      onErrorCallback(e.toString());
    }
  }

  Future<void> _saveOfflineShootingLog(
      Map<String, dynamic> data, DatabaseHelper dbHelper) async {
    try {
      print('DEBUG: Cartridge ID pro ověření: ${data['cartridge_id']}');

      // Změnit na správnou metodu pro získání náboje podle ID
      final cartridge =
          await dbHelper.getDataById('cartridges', data['cartridge_id']);
      if (cartridge == null) {
        throw Exception('Chyba: Náboj nebyl nalezen v databázi');
      }

      final currentStock = cartridge['stock_quantity'] as int;
      final requestedShots = data['shots_fired'] as int;

      if (requestedShots > currentStock) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Nedostatek střeliva'),
              content: Text(
                  'Nelze zaznamenat $requestedShots výstřelů.\nDostupné množství: $currentStock ks'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return;
      }

      // Save offline request if validation passes
      await dbHelper.addOfflineRequest(
        'create_shooting_log',
        data,
      );

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Záznam uložen offline pro pozdější synchronizaci')),
      );
    } catch (e) {
      // This catch block now only handles real errors like DB access issues
      print('Chyba při ukládání offline záznamu: $e');
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Chyba'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Přidat záznam do střeleckého deníku'),
      ),
      body: Column(
        children: <Widget>[
          // Oblast pro QR scanner
          Expanded(
            flex: 4,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: Colors.blue,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: 250,
              ),
            ),
          ),
          // Oblast pro ovládání
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Stav svítilny
                Text('Svítilna je ${isFlashOn ? "zapnutá" : "vypnutá"}'),
                // Tlačítko pro zapnutí/vypnutí svítilny
                ElevatedButton(
                  onPressed: _toggleFlash, // Metoda pro přepnutí svítilny
                  child:
                      Text(isFlashOn ? 'Vypnout svítilnu' : 'Zapnout svítilnu'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
