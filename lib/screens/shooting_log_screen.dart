import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'package:shooting_companion/services/api_service.dart'; // Import API služby
import 'package:vibration/vibration.dart'; // Import balíčku vibration

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
  bool isLoading = false; // Přidána proměnná isLoading pro sledování načítání

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

  Future<Position> _getCurrentLocation() async {
    // Získání aktuální pozice
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Služba určování polohy je zakázaná.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Přístup k poloze byl odepřen.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Přístup k poloze je trvale zakázán.');
    }

    // Vrátí aktuální pozici
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  // Volání API pro zjištění informací o náboji
  Future<void> _fetchCartridgeInfo(String code) async {
    try {
      final response = await ApiService.checkBarcode(code); // Volání API služby

      // Ověření, zda odpověď obsahuje požadované informace
      if (response.containsKey('cartridge') && response['cartridge'] != null) {
        final cartridge = response['cartridge'];
        final caliber = cartridge['caliber'];

        setState(() {
          cartridgeData = response;
          cartridgeInfo = 'Náboj: ${cartridge['name'] ?? 'Neznámý'}, '
              'Kalibr: ${caliber?['name'] ?? 'Neznámý'}';
        });

        // Zavibrujte po úspěšném načtení dat
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 200); // Vibrace na 200 ms
        }

        // Načtení zbraní odpovídajících kalibru, pokud kalibr existuje
        if (caliber != null && caliber['id'] != null) {
          _fetchUserWeapons(caliber['id']);
        }
      } else {
        // Pokud není náboj v systému zaveden, zobrazí se uživatelsky přívětivější zpráva
        setState(() {
          cartridgeInfo =
              'Náboj s tímto čárovým kódem není v systému zaveden. Začněte prosím přiřazením kódu k náboji v "Sken&Navýšení Skladu"';
        });
        controller?.resumeCamera(); // Obnovení kamery při chybě
      }
    } catch (e) {
      setState(() {
        cartridgeInfo =
            'Chyba při načítání náboje. Zkontrolujte prosím připojení a zkuste to znovu.'; // Zobrazení přívětivější chyby
      });
      controller?.resumeCamera(); // Obnovení kamery při chybě
    }
  }

  // Volání API pro získání zbraní uživatele odpovídajících kalibru
  Future<void> _fetchUserWeapons(int caliberId) async {
    try {
      final weaponsResponse =
          await ApiService.getUserWeaponsByCaliber(caliberId); // Volání API
      setState(() {
        userWeapons = weaponsResponse; // Uložení zbraní uživatele
      });
      _showWeaponsDialog(); // Zobrazení dialogu s výpisem zbraní
    } catch (e) {
      print('Chyba při načítání zbraní: $e');
      controller?.resumeCamera(); // Obnovení kamery při chybě
    }
  }

  // Volání API pro získání aktivit uživatele
  Future<void> _fetchUserActivities() async {
    setState(() {
      isLoading = true; // Začátek načítání
    });
    try {
      final activitiesResponse =
          await ApiService.getUserActivities(); // Volání API
      setState(() {
        userActivities = activitiesResponse; // Uložení aktivit uživatele
      });
    } catch (e) {
      print('Chyba při načítání aktivit: $e');
    } finally {
      setState(() {
        isLoading = false; // Konec načítání
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
  void _showWeaponsDialog() {
    controller?.pauseCamera(); // Pauza kamery při otevření dialogu

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
                        _showShootingLogForm(weapon['id']);
                      },
                    );
                  }).toList(),
                )
              : Text('Žádné zbraně odpovídající kalibru nebyly nalezeny.'),
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
    ).then((_) {
      controller?.resumeCamera(); // Obnovení kamery po zavření dialogu
    });
  }

  void _showShootingLogForm(int weaponId) async {
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
                    if (ammoCountController.text.isNotEmpty &&
                        selectedActivity != null &&
                        dateController.text.isNotEmpty) {
                      _createShootingLog(
                        weaponId,
                        int.parse(ammoCountController.text),
                        selectedActivity!,
                        dateController.text,
                        noteController.text,
                      );
                      Navigator.of(context).pop();
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
    String date,
    String note,
  ) async {
    if (cartridgeData == null ||
        cartridgeData!['cartridge'] == null ||
        cartridgeData!['cartridge']['id'] == null) {
      print('Chyba: Naskenovaný náboj nebo cartridge data nejsou k dispozici');
      return;
    }

    try {
      final dynamic idValue = cartridgeData!['cartridge']['id'];
      final int cartridgeId =
          idValue is int ? idValue : int.parse(idValue.toString());

      final response = await ApiService.createShootingLog({
        "weapon_id": weaponId,
        "cartridge_id": cartridgeId,
        "activity_type": activityType,
        "shots_fired": shotsFired, // Počet vystřelených nábojů
        "date": date, // Datum aktivity
        "note": note, // Poznámka
      });

      // Zpracování úspěšné odpovědi
      if (response.containsKey('shooting_log_id')) {
        print(
            'Záznam ve střeleckém deníku byl úspěšně vytvořen: ID ${response['shooting_log_id']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Záznam úspěšně uložen. ID: ${response['shooting_log_id']}'),
          ),
        );
      } else {
        // Zpracování chyby, pokud API vrátí jiný výsledek než úspěšné vytvoření
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identifikace náboje'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0), // Přidání paddingu po stranách
                child: Text(
                  scannedCode != null
                      ? (cartridgeInfo ?? 'Načítám informace o náboji...')
                      : 'Naskenujte QR kód',
                  textAlign: TextAlign.center, // Zarovnání textu na střed
                  style: TextStyle(fontSize: 16), // Nastavení velikosti písma
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
