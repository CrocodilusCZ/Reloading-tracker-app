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
    controller.scannedDataStream.listen((scanData) {
      if (!isProcessing) {
        setState(() {
          scannedCode = scanData.code;
        });
        _checkBarcode(scannedCode!);
      }
    });
  }

  // Funkce pro ověření, zda je čárový kód přiřazen
  Future<void> _checkBarcode(String scannedBarcode) async {
    setState(() {
      isProcessing = true;
    });

    final response = await ApiService.checkBarcode(scannedBarcode);
    print('Odpověď API (kontrola čárového kódu): $response');

    setState(() {
      isProcessing = false;
      if (response['exists'] == true) {
        barcodeStatus =
            'Čárový kód je přiřazen k náboji ${response['cartridge']['name']}';
        // Nabídka navýšení skladové zásoby
        _showIncreaseStockDialog(scannedBarcode, response['cartridge']['name']);
      } else {
        barcodeStatus = 'Čárový kód není přiřazen.';
        // Nabídka přiřazení čárového kódu
        _showAssignBarcodeDialog(scannedBarcode);
      }
    });
  }

  // Funkce pro zobrazení dialogu k navýšení skladové zásoby
  Future<void> _showIncreaseStockDialog(
      String scannedBarcode, String cartridgeName) async {
    int quantity = 0;
    final TextEditingController quantityController = TextEditingController();

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Navýšení skladové zásoby pro $cartridgeName'),
          content: TextField(
            controller: quantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Zadejte množství'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                quantity = int.tryParse(quantityController.text) ?? 0;
                if (quantity > 0) {
                  ApiService.increaseStockByBarcode(scannedBarcode, quantity);
                  Navigator.pop(context);
                  _showMessage(
                      'Skladová zásoba byla navýšena o $quantity kusů.');
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
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
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Přiřadit čárový kód'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text('Vyberte náboj pro přiřazení čárového kódu:'),
                ...cartridgesResponse.map<Widget>((cartridge) {
                  return ListTile(
                    title: Text(cartridge['name']),
                    subtitle: Text('Kalibr: ${cartridge['caliber']['name']}'),
                    onTap: () async {
                      await ApiService.assignBarcode(
                          cartridge['id'], scannedBarcode);
                      Navigator.pop(context); // Zavřít dialog po přiřazení
                      _showMessage(
                          'Čárový kód byl přiřazen k náboji ${cartridge['name']}.');
                    },
                  );
                }).toList(),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
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
