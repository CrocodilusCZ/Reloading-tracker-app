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
        isProcessing = true;
        await controller.pauseCamera();
        setState(() {
          scannedCode = scanData.code;
        });

        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 500);
        }

        await _checkBarcode(scannedCode!);
      }
    });
  }

  Future<void> _resetScanner() async {
    setState(() {
      scannedCode = null;
      barcodeStatus = null;
    });
    await controller?.resumeCamera();
    isProcessing = false;
  }

  Future<void> _checkBarcode(String scannedBarcode) async {
    final response = await ApiService.checkBarcode(scannedBarcode);
    print('Odpověď API (kontrola čárového kódu): $response');

    if (response['exists'] == true) {
      setState(() {
        barcodeStatus =
            'Čárový kód je přiřazen k náboji ${response['cartridge']['name']}';
      });

      String caliberName = response['cartridge']['caliber'] != null
          ? response['cartridge']['caliber']['name']
          : 'Neznámý kalibr';

      int packageSize =
          response['cartridge']['package_size'] ?? 0; // Získáme `package_size`

      await _showIncreaseStockDialog(
          scannedBarcode,
          response['cartridge']['name'],
          response['cartridge']['manufacturer'] ?? 'Neznámý výrobce',
          caliberName,
          packageSize); // Předáme `packageSize` do dialogu
    } else {
      setState(() {
        barcodeStatus = 'Čárový kód není přiřazen.';
      });
      await _showAssignBarcodeDialog(scannedBarcode); // Přímo zobrazíme dialog
    }
  }

  Future<void> _showIncreaseStockDialog(
      String scannedBarcode,
      String cartridgeName,
      String manufacturerName,
      String caliber,
      int packageSize) async {
    // Přidáme `packageSize` jako parametr

    final TextEditingController quantityController = TextEditingController(
        text: packageSize > 0
            ? packageSize.toString()
            : ''); // Předvyplníme `packageSize`

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
                int quantity = int.tryParse(quantityController.text) ?? 0;
                Navigator.pop(dialogContext);
                if (quantity > 0) {
                  try {
                    await ApiService.increaseStockByBarcode(
                        scannedBarcode, quantity);
                    _showMessage(
                        'Skladová zásoba byla navýšena o $quantity kusů.');
                  } catch (e) {
                    _showMessage('Chyba při navýšení skladové zásoby.');
                  }
                }
                await _resetScanner();
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _resetScanner();
              },
              child: const Text('Zrušit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAssignBarcodeDialog(String scannedBarcode) async {
    final cartridgesResponse = await ApiService.getFactoryCartridges();
    print('Odpověď API (seznam továrních nábojů): $cartridgesResponse');

    if (cartridgesResponse.isEmpty) {
      _showMessage('Nemáte žádné tovární náboje k přiřazení.');
      await _resetScanner();
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Přiřadit čárový kód nebo vytvořit nový náboj'),
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
                              Navigator.pop(dialogContext);
                              _showMessage(
                                  'Čárový kód byl přiřazen k náboji: ${cartridge['name']}\n'
                                  'Výrobce: ${cartridge['manufacturer'] ?? "Neznámý"}\n'
                                  'Kalibr: ${cartridge['caliber']['name']}\n'
                                  'Specifikace střely: ${cartridge['bullet_specification'] ?? "Neznámá"}\n'
                                  'Cena za kus: ${cartridge['price']} Kč\n'
                                  'Skladová zásoba: ${cartridge['stock_quantity']} ks');
                              await _resetScanner();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasBarcode
                            ? Colors.grey
                            : Theme.of(context).primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4.0),
                          side:
                              const BorderSide(color: Colors.black, width: 2.0),
                        ),
                        minimumSize: const Size(double.infinity, 60),
                        padding: const EdgeInsets.symmetric(
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
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _showCreateNewCartridgeForm(scannedBarcode);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4.0),
                      side: const BorderSide(color: Colors.black, width: 2.0),
                    ),
                    minimumSize: const Size(double.infinity, 60),
                    padding: const EdgeInsets.symmetric(
                        vertical: 16.0, horizontal: 12.0),
                  ),
                  child: const Text(
                    'Vytvořit nový náboj',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _resetScanner();
              },
              child: const Text('Zrušit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSelectionDialog(String scannedBarcode) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Čárový kód není přiřazen'),
          content: const Text('Vyberte možnost:'),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _showAssignBarcodeDialog(scannedBarcode);
              },
              child: const Text('Přiřadit k existujícímu náboji'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _showCreateNewCartridgeForm(scannedBarcode);
              },
              child: const Text('Vytvořit nový náboj'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateNewCartridgeForm(String scannedBarcode) async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController manufacturerController =
        TextEditingController();
    final TextEditingController bulletSpecController = TextEditingController();
    final TextEditingController priceController = TextEditingController();
    final TextEditingController stockController = TextEditingController();
    final TextEditingController packageSizeController = TextEditingController();
    bool isFavorite = false;
    int? selectedCaliberId;

    // Načtení seznamu kalibrů
    final calibers =
        await ApiService.getCalibers(); // Předpoklad metody na načtení kalibrů

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Vytvořit nový náboj'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration:
                          const InputDecoration(labelText: 'Název náboje'),
                    ),
                    TextField(
                      controller: manufacturerController,
                      decoration: const InputDecoration(labelText: 'Výrobce'),
                    ),
                    TextField(
                      controller: bulletSpecController,
                      decoration: const InputDecoration(
                          labelText: 'Specifikace střely'),
                    ),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Cena za kus'),
                    ),
                    TextField(
                      controller: stockController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Skladová zásoba'),
                    ),
                    TextField(
                      controller:
                          packageSizeController, // Přidáno pro prodejní balení
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Velikost prodejního balení'),
                    ),
                    TextFormField(
                      controller: TextEditingController(
                          text: selectedCaliberId != null
                              ? calibers.firstWhere((caliber) =>
                                  caliber['id'] == selectedCaliberId)['name']
                              : "Vyberte kalibr"),
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Kalibr'),
                      onTap: () async {
                        // Otevřít dialog s výběrem kalibrů
                        await showDialog(
                          context: context,
                          builder: (BuildContext dialogContext) {
                            return AlertDialog(
                              title: const Text('Vyberte kalibr'),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: Scrollbar(
                                  thumbVisibility: true,
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: calibers.length,
                                    itemBuilder: (context, index) {
                                      final caliber = calibers[index];
                                      return ListTile(
                                        title: Text(caliber['name']),
                                        onTap: () {
                                          setState(() {
                                            selectedCaliberId = caliber['id'];
                                          });
                                          Navigator.pop(dialogContext);
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                              actions: <Widget>[
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                  },
                                  child: const Text('Zrušit'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Oblíbený'),
                        Switch(
                          value: isFavorite,
                          onChanged: (value) {
                            setState(() {
                              isFavorite = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    if (selectedCaliberId == null) {
                      _showMessage('Vyberte prosím kalibr.');
                      return;
                    }

                    final cartridgeData = {
                      'name': nameController.text,
                      'manufacturer': manufacturerController.text,
                      'bullet_specification': bulletSpecController.text,
                      'caliber_id':
                          selectedCaliberId, // Dynamicky vybraný kalibr
                      'price': double.tryParse(priceController.text) ?? 0.0,
                      'stock_quantity': int.tryParse(stockController.text) ?? 0,
                      'package_size':
                          int.tryParse(packageSizeController.text) ?? 1,
                      'barcode': scannedBarcode,
                      'is_favorite': isFavorite,
                    };

                    try {
                      final response = await ApiService.createFactoryCartridge(
                          cartridgeData);
                      _showMessage(
                          'Nový náboj byl vytvořen: ${response['name']}');
                    } catch (e) {
                      _showMessage('Chyba při vytváření náboje: $e');
                    }

                    await _resetScanner();
                  },
                  child: const Text('Vytvořit'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _resetScanner();
                  },
                  child: const Text('Zrušit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

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
