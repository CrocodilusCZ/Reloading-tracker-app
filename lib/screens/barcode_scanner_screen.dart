import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:shooting_companion/services/api_service.dart'; // Import API služby
import 'package:vibration/vibration.dart';
import 'package:shooting_companion/widgets/factory_cartridge_form.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final String? source;
  final Map<String, dynamic>? currentCartridge;

  const BarcodeScannerScreen({
    Key? key,
    this.source,
    this.currentCartridge,
  }) : super(key: key);

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
    await controller?.resumeCamera();
    setState(() {
      isProcessing = false;
      barcodeStatus = null;
      scannedCode = null;
    });
  }

  Future<void> _checkBarcode(String scannedBarcode) async {
    final response = await ApiService.checkBarcode(scannedBarcode);
    print('Odpověď API (kontrola čárového kódu): $response');

    final bool isCartridgeDetailScreen = widget.source == 'cartridge_detail';
    final bool barcodeExists = response['exists'] == true;

    setState(() {
      barcodeStatus = barcodeExists
          ? 'Čárový kód je přiřazen k náboji ${response['cartridge']['name']}'
          : 'Čárový kód není přiřazen.';
    });

    if (isCartridgeDetailScreen) {
      // Logic for CartridgeDetailScreen
      if (barcodeExists) {
        _showMessage('Tento čárový kód je již přiřazen k jinému náboji');
        await _resetScanner();
      } else {
        try {
          await ApiService.assignBarcode(
              widget.currentCartridge!['id'], scannedBarcode);
          _showMessage('Čárový kód byl úspěšně přiřazen');
          Navigator.pop(context);
        } catch (e) {
          _showMessage('Chyba při přiřazování čárového kódu');
          await _resetScanner();
        }
      }
    } else {
      // Logic for main barcode scanner screen
      if (barcodeExists) {
        String caliberName =
            response['cartridge']['caliber']?['name'] ?? 'Neznámý kalibr';
        int packageSize = response['cartridge']['package_size'] ?? 0;
        await _showIncreaseStockDialog(
          scannedBarcode,
          response['cartridge']['name'],
          response['cartridge']['manufacturer'] ?? 'Neznámý výrobce',
          caliberName,
          packageSize,
        );
      } else {
        await _showAssignBarcodeDialog(scannedBarcode);
      }
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
    try {
      final cartridgesResponse = await ApiService.getFactoryCartridges();
      print('Odpověď API (seznam továrních nábojů): $cartridgesResponse');

      if (cartridgesResponse.isEmpty) {
        _showMessage('Nemáte žádné tovární náboje k přiřazení.');
        await _resetScanner();
        return;
      }

      // Sort cartridges - unassigned first
      final sortedCartridges = [...cartridgesResponse]..sort((a, b) {
          bool aHasBarcode = a['barcode'] != null && a['barcode'] != '';
          bool bHasBarcode = b['barcode'] != null && b['barcode'] != '';
          return aHasBarcode ? 1 : -1;
        });

      await showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Přiřadit čárový kód'),
            content: Container(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Create New Button at top
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add_circle_outline,
                            color: Colors.white),
                        label: const Text(
                          'Vytvořit nový náboj',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await _showCreateNewCartridgeForm(scannedBarcode);
                        },
                      ),
                    ),

                    const Divider(height: 24),

                    // Available cartridges section
                    const Text(
                      'Dostupné náboje k přiřazení:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    ...sortedCartridges.map<Widget>((cartridge) {
                      bool hasBarcode = cartridge['barcode'] != null &&
                          cartridge['barcode'] != '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: hasBarcode ? 0 : 2,
                        color: hasBarcode ? Colors.grey.shade100 : Colors.white,
                        child: InkWell(
                          onTap: hasBarcode
                              ? null
                              : () async {
                                  try {
                                    await ApiService.assignBarcode(
                                        cartridge['id'], scannedBarcode);
                                    Navigator.pop(dialogContext);
                                    _showMessage(
                                        'Čárový kód byl úspěšně přiřazen k náboji ${cartridge['name']}');
                                  } catch (e) {
                                    _showMessage(
                                        'Chyba při přiřazování čárového kódu: ${e.toString()}');
                                  }
                                  await _resetScanner();
                                },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        cartridge['name'],
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: hasBarcode
                                              ? Colors.grey
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (hasBarcode)
                                      const Icon(Icons.qr_code,
                                          color: Colors.grey)
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${cartridge['manufacturer'] ?? "Neznámý"} • ${cartridge['caliber']['name']}',
                                  style: TextStyle(
                                    color: hasBarcode
                                        ? Colors.grey
                                        : Colors.black54,
                                  ),
                                ),
                                Text(
                                  '${cartridge['price']} Kč • Zásoba: ${cartridge['stock_quantity']} ks',
                                  style: TextStyle(
                                    color: hasBarcode
                                        ? Colors.grey
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
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
    } catch (e) {
      _showMessage('Chyba při načítání továrních nábojů: ${e.toString()}');
      await _resetScanner();
    }
  }

  Widget _buildCartridgeButton({
    required Map<String, dynamic> cartridge,
    required bool hasBarcode,
    required BuildContext dialogContext,
    required String scannedBarcode,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ElevatedButton(
        onPressed: hasBarcode
            ? null
            : () async {
                try {
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
                } catch (e) {
                  _showMessage(
                      'Chyba při přiřazování čárového kódu: ${e.toString()}');
                } finally {
                  await _resetScanner();
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor:
              hasBarcode ? Colors.grey : Theme.of(dialogContext).primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4.0),
            side: const BorderSide(color: Colors.black, width: 2.0),
          ),
          minimumSize: const Size(double.infinity, 60),
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        ),
        child: _buildCartridgeButtonContent(cartridge, hasBarcode),
      ),
    );
  }

  Widget _buildCartridgeButtonContent(
      Map<String, dynamic> cartridge, bool hasBarcode) {
    return Column(
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
        ...[
          'Výrobce',
          'Kalibr',
          'Specifikace střely',
          'Cena za kus',
          'Skladová zásoba'
        ].map((label) => _buildInfoRow(label, cartridge, hasBarcode)).toList(),
        if (hasBarcode)
          const Text(
            'Čárový kód již přiřazen',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  Widget _buildInfoRow(
      String label, Map<String, dynamic> cartridge, bool hasBarcode) {
    String value = '';
    switch (label) {
      case 'Výrobce':
        value = '${cartridge['manufacturer'] ?? "Neznámý"}';
        break;
      case 'Kalibr':
        value = cartridge['caliber']['name'];
        break;
      case 'Specifikace střely':
        value = '${cartridge['bullet_specification'] ?? "Neznámá"}';
        break;
      case 'Cena za kus':
        value = '${cartridge['price']} Kč';
        break;
      case 'Skladová zásoba':
        value = '${cartridge['stock_quantity']} ks';
        break;
    }

    return Text(
      '$label: $value',
      style: TextStyle(
        color: hasBarcode ? Colors.black54 : Colors.white70,
      ),
    );
  }

  Widget _buildCreateNewButton(
      BuildContext dialogContext, String scannedBarcode) {
    return ElevatedButton(
      onPressed: () async {
        Navigator.pop(dialogContext);
        await _showCreateNewCartridgeForm(scannedBarcode);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(dialogContext).primaryColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4.0),
          side: const BorderSide(color: Colors.black, width: 2.0),
        ),
        minimumSize: const Size(double.infinity, 60),
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
      ),
      child: const Text(
        'Vytvořit nový náboj',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
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
    final nameController = TextEditingController();
    final barcodeController = TextEditingController(text: scannedBarcode);
    final quantityController = TextEditingController();
    final manufacturerController = TextEditingController();
    final bulletSpecController = TextEditingController();
    final priceController = TextEditingController();
    String? selectedCaliberId;

    await showDialog(
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
                    enabled: false,
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
                      onPressed: () {
                        Navigator.pop(context);
                        _resetScanner();
                      },
                      child: const Text('Zrušit'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          await ApiService.createFactoryCartridge({
                            'name': nameController.text,
                            'caliber_id': selectedCaliberId,
                            'manufacturer': manufacturerController.text,
                            'bullet_specification': bulletSpecController.text,
                            'price': double.tryParse(priceController.text) ?? 0,
                            'stock_quantity':
                                int.tryParse(quantityController.text) ?? 0,
                            'barcode': scannedBarcode,
                          });
                          Navigator.pop(context);
                          _showMessage('Nový náboj byl vytvořen');
                        } catch (e) {
                          _showMessage('Chyba při vytváření náboje: $e');
                        }
                        await _resetScanner();
                      },
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

        return DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: 'Kalibr *',
            prefixIcon: const Icon(Icons.adjust),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          isExpanded: true,
          items: snapshot.data!.map((caliber) {
            return DropdownMenuItem<String>(
              value: caliber['id'].toString(),
              child: Text(
                caliber['name'],
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            );
          }).toList(),
          onChanged: (value) => onCaliberSelected(value!),
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
