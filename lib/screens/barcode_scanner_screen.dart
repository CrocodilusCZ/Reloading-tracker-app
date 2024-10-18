import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:shooting_companion/services/api_service.dart'; // Import API služby
import 'package:vibration/vibration.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({Key? key}) : super(key: key);

  @override
  _BarcodeScannerScreenState createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  String? scannedCode;
  String? barcodeStatus;
  bool isProcessing = false;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) async {
      if (!isProcessing) {
        isProcessing =
            true; // Nastavení na true, aby se zabránilo opakovanému zpracování
        await controller.pauseCamera(); // Pozastavíme skener
        setState(() {
          scannedCode = scanData.code;
        });

        // Zavibrovat po naskenování kódu
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 500); // Zavibruje na 500 ms
        }

        await _checkBarcode(
            scannedCode!); // Volání funkce pro kontrolu čárového kódu
      }
    });
  }

  // Funkce pro obnovení stavu skeneru po dokončení akce
  Future<void> _resetScanner() async {
    setState(() {
      scannedCode = null;
      barcodeStatus = null;
    });
    await controller?.resumeCamera(); // Obnovíme skener
    isProcessing = false; // Připravíme na další sken
  }

  // Funkce pro ověření, zda je čárový kód přiřazen
  Future<void> _checkBarcode(String scannedBarcode) async {
    final response = await ApiService.checkBarcode(scannedBarcode);
    print('Odpověď API (kontrola čárového kódu): $response');

    if (response['exists'] == true) {
      setState(() {
        barcodeStatus =
            'Čárový kód je přiřazen k náboji ${response['cartridge']['name']}';
      });
      // Zkontrolujeme, zda existuje 'caliber'
      String caliberName = response['cartridge']['caliber'] != null
          ? response['cartridge']['caliber']['name']
          : 'Neznámý kalibr';

      await _showIncreaseStockDialog(
          scannedBarcode,
          response['cartridge']['name'],
          response['cartridge']['manufacturer'] ?? 'Neznámý výrobce',
          caliberName);
    } else {
      setState(() {
        barcodeStatus = 'Čárový kód není přiřazen.';
      });
      // Nabídka přiřazení čárového kódu
      await _showAssignBarcodeDialog(scannedBarcode);
    }
  }

  // Funkce pro zobrazení dialogu k navýšení skladové zásoby
  Future<void> _showIncreaseStockDialog(String scannedBarcode,
      String cartridgeName, String manufacturerName, String caliber) async {
    int quantity = 0;
    final TextEditingController quantityController = TextEditingController();

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
              'Navýšení skladové zásoby pro $cartridgeName (Výrobce: $manufacturerName, Kalibr: $caliber)'),
          content: TextField(
            controller: quantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Zadejte množství'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                quantity = int.tryParse(quantityController.text) ?? 0;
                Navigator.pop(dialogContext); // Zavřít dialog
                if (quantity > 0) {
                  try {
                    // Navýšení skladové zásoby přes API
                    await ApiService.increaseStockByBarcode(
                        scannedBarcode, quantity);

                    // Zobrazení zprávy o úspěšném navýšení skladové zásoby
                    _showMessage(
                        'Skladová zásoba byla navýšena o $quantity kusů.');
                  } catch (e) {
                    // Zobrazit chybovou zprávu, pokud navýšení selže
                    _showMessage('Chyba při navýšení skladové zásoby.');
                  }
                }
                // Resetujeme skener po dokončení akce
                await _resetScanner();
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext); // Zavřít dialog bez akce
                // Resetujeme skener po zavření dialogu
                await _resetScanner();
              },
              child: const Text('Zrušit'),
            ),
          ],
        );
      },
    );
  }

  // Funkce pro zobrazení dialogu s továrními náboji pro přiřazení čárového kódu
  Future<void> _showAssignBarcodeDialog(String scannedBarcode) async {
    final cartridgesResponse = await ApiService.getFactoryCartridges();
    print('Odpověď API (seznam továrních nábojů): $cartridgesResponse');

    if (cartridgesResponse.isEmpty) {
      _showMessage('Nemáte žádné tovární náboje k přiřazení.');
      // Resetujeme skener, protože není žádná akce k provedení
      await _resetScanner();
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // Uložíme dialogContext
        return AlertDialog(
          title: const Text('Přiřadit čárový kód'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('Vyberte náboj pro přiřazení čárového kódu:'),
                const SizedBox(height: 10),
                ...cartridgesResponse.map<Widget>((cartridge) {
                  bool hasBarcode = cartridge['barcode'] != null &&
                      cartridge['barcode'] != '';
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ElevatedButton(
                      onPressed: hasBarcode
                          ? null
                          : () async {
                              await ApiService.assignBarcode(
                                  cartridge['id'], scannedBarcode);
                              Navigator.pop(dialogContext); // Zavřít dialog

                              // Zobrazení detailů náboje při potvrzení
                              _showMessage(
                                  'Čárový kód byl přiřazen k náboji: ${cartridge['name']}\n'
                                  'Výrobce: ${cartridge['manufacturer'] ?? "Neznámý"}\n'
                                  'Kalibr: ${cartridge['caliber']['name']}\n'
                                  'Specifikace střely: ${cartridge['bullet_specification'] ?? "Neznámá"}\n'
                                  'Cena za kus: ${cartridge['price']} Kč\n'
                                  'Skladová zásoba: ${cartridge['stock_quantity']} ks');

                              // Resetujeme skener po dokončení akce
                              await _resetScanner();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasBarcode
                            ? Colors.grey
                            : Theme.of(context).primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4.0),
                          side: BorderSide(color: Colors.black, width: 2.0),
                        ),
                        minimumSize: Size(double.infinity, 60),
                        padding: EdgeInsets.symmetric(
                            vertical: 16.0, horizontal: 12.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cartridge['name'],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: hasBarcode ? Colors.black54 : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Výrobce: ${cartridge['manufacturer'] ?? "Neznámý"}',
                            style: TextStyle(
                              color:
                                  hasBarcode ? Colors.black54 : Colors.white70,
                            ),
                          ),
                          Text(
                            'Kalibr: ${cartridge['caliber']['name']}',
                            style: TextStyle(
                              color:
                                  hasBarcode ? Colors.black54 : Colors.white70,
                            ),
                          ),
                          Text(
                            'Specifikace střely: ${cartridge['bullet_specification'] ?? "Neznámá"}',
                            style: TextStyle(
                              color:
                                  hasBarcode ? Colors.black54 : Colors.white70,
                            ),
                          ),
                          Text(
                            'Cena za kus: ${cartridge['price']} Kč',
                            style: TextStyle(
                              color:
                                  hasBarcode ? Colors.black54 : Colors.white70,
                            ),
                          ),
                          Text(
                            'Skladová zásoba: ${cartridge['stock_quantity']} ks',
                            style: TextStyle(
                              color:
                                  hasBarcode ? Colors.black54 : Colors.white70,
                            ),
                          ),
                          if (hasBarcode)
                            const Text(
                              'Čárový kód již přiřazen',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext); // Zavřít dialog bez akce
                // Resetujeme skener po zavření dialogu
                await _resetScanner();
              },
              child: const Text('Zrušit'),
            ),
          ],
        );
      },
    );
  }

  // Zobrazení zprávy
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (scannedCode != null) ...[
                  Text('Naskenovaný kód: $scannedCode'),
                  const SizedBox(height: 16),
                  Text(barcodeStatus ?? 'Kontrola čárového kódu...'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
