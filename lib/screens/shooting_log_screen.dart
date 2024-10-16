import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'dart:io';
import 'package:simple_login_app/services/api_service.dart'; // Import API služby

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

  // Volání API pro zjištění informací o náboji
  Future<void> _fetchCartridgeInfo(String code) async {
    try {
      final response = await ApiService.checkBarcode(code); // Volání API služby
      setState(() {
        cartridgeData = response; // Uložení celého objektu pro pozdější použití
        cartridgeInfo = 'Náboj: ${response['cartridge']['name']}, '
            'Kalibr: ${response['cartridge']['caliber']['name']}';
      });
      // Načtení zbraní odpovídajících kalibru
      _fetchUserWeapons(response['cartridge']['caliber']['id']);
    } catch (e) {
      setState(() {
        cartridgeInfo = 'Chyba při načítání náboje: $e'; // Zobrazení chyby
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

  // Formulář pro vytvoření nového záznamu ve střeleckém deníku
  void _showShootingLogForm(int weaponId) {
    TextEditingController ammoCountController = TextEditingController();
    TextEditingController activityTypeController = TextEditingController();
    TextEditingController noteController = TextEditingController();
    TextEditingController dateController = TextEditingController();

    controller?.pauseCamera(); // Pauza kamery při otevření dialogu

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Vytvoření záznamu ve střeleckém deníku'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: ammoCountController,
                  decoration:
                      InputDecoration(labelText: 'Počet vystřelených nábojů'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: activityTypeController,
                  decoration: InputDecoration(labelText: 'Typ aktivity'),
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
                    activityTypeController.text.isNotEmpty &&
                    dateController.text.isNotEmpty) {
                  _createShootingLog(
                    weaponId,
                    int.parse(ammoCountController.text),
                    activityTypeController.text,
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
    ).then((_) {
      controller?.resumeCamera(); // Obnovení kamery po zavření dialogu
    });
  }

  // Vytvoření záznamu ve střeleckém deníku
  Future<void> _createShootingLog(
    int weaponId,
    int ammoCount,
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
        "cartridge_id": cartridgeId, // Dynamicky získané ID náboje
        "activity_type": activityType,
        "ammo_count": ammoCount,
        "activity_date": date,
        "note": note,
      });
      print('Záznam ve střeleckém deníku byl úspěšně vytvořen: $response');
    } catch (e) {
      print('Chyba při vytváření záznamu ve střeleckém deníku: $e');
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
              child: Text(
                scannedCode != null
                    ? (cartridgeInfo ?? 'Načítám informace o náboji...')
                    : 'Naskenujte QR kód',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
