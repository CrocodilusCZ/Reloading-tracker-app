import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:simple_login_app/services/api_service.dart'; // Import API služby

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
        isProcessing = true; // Okamžitě nastavíme isProcessing na true
        await controller.pauseCamera(); // Pozastavíme skener
        setState(() {
          scannedCode = scanData.code;
        });
        await _checkBarcode(scannedCode!);
        // Skener znovu spustíme po dokončení akce v dialozích
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
      // Nabídka navýšení skladové zásoby
      await _showIncreaseStockDialog(
          scannedBarcode, response['cartridge']['name']);
    } else {
      setState(() {
        barcodeStatus = 'Čárový kód není přiřazen.';
      });
      // Nabídka přiřazení čárového kódu
      await _showAssignBarcodeDialog(scannedBarcode);
    }
    // Nyní _resetScanner() voláme až po dokončení akce v dialozích
  }

  // Funkce pro zobrazení dialogu k navýšení skladové zásoby
  Future<void> _showIncreaseStockDialog(
      String scannedBarcode, String cartridgeName) async {
    int quantity = 0;
    final TextEditingController quantityController = TextEditingController();

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // Uložíme dialogContext
        return AlertDialog(
          title: Text('Navýšení skladové zásoby pro $cartridgeName'),
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
            child: ListBody(
              children: <Widget>[
                const Text('Vyberte náboj pro přiřazení čárového kódu:'),
                ...cartridgesResponse.map<Widget>((cartridge) {
                  return ListTile(
                    title: Text(cartridge['name']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Výrobce: ${cartridge['manufacturer'] ?? "Neznámý"}'),
                        Text('Kalibr: ${cartridge['caliber']['name']}'),
                        Text(
                            'Specifikace střely: ${cartridge['bullet_specification'] ?? "Neznámá"}'),
                        Text('Cena za kus: ${cartridge['price']} Kč'),
                        Text(
                            'Skladová zásoba: ${cartridge['stock_quantity']} ks'),
                      ],
                    ),
                    onTap: () async {
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
