import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:shooting_companion/services/api_service.dart'; // Import API služby
import 'package:vibration/vibration.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
  bool isFlashOn = false; // Výchozí stav svítilny
  Map<String, int> stockQuantities = {};

  @override
  void initState() {
    super.initState();
    // Zajistí, že při otevření obrazovky bude skener resetován
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetScanner();
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _updateStockQuantity(String barcode, int newStock) {
    setState(() {
      stockQuantities[barcode] = newStock;
    });
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

        try {
          print('DEBUG: Processing barcode: ${scanData.code}');
          await _checkBarcode(scannedCode!);
        } catch (e) {
          print('ERROR: Failed to process barcode: $e');
          _showMessage('Chyba při zpracování čárového kódu');
          await _resetScanner();
        } finally {
          isProcessing = false;
        }
      }
    });
  }

  Future<bool> isOnline() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    return connectivityResult != ConnectivityResult.none;
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
    try {
      print('DEBUG: Starting barcode check for: $scannedBarcode');

      // Try local DB first
      final dbHelper = DatabaseHelper();
      print('DEBUG: Querying local database...');
      final localCartridge =
          await dbHelper.getCartridgeByBarcode(scannedBarcode);
      print('DEBUG: Local database result: $localCartridge');

      if (localCartridge != null) {
        final bool isCartridgeDetailScreen =
            widget.source == 'cartridge_detail';
        print(
            'DEBUG: Found in local DB. isCartridgeDetailScreen: $isCartridgeDetailScreen');

        setState(() {
          barcodeStatus =
              'Čárový kód je přiřazen k náboji ${localCartridge['name']}';
        });

        if (isCartridgeDetailScreen) {
          print(
              'DEBUG: Cartridge detail screen - showing already assigned message');
          _showMessage('Tento čárový kód je již přiřazen k jinému náboji');
          await _resetScanner();
        } else {
          print('DEBUG: Showing increase stock dialog for local cartridge');
          await _showStockUpdateDialog(
            scannedBarcode,
            localCartridge['name'],
            localCartridge['manufacturer'] ?? 'Neznámý výrobce',
            localCartridge['caliber_name'] ?? 'Neznámý kalibr',
            localCartridge['package_size'] ?? 0,
          );
        }
        return;
      }

      // If not found locally, try API if online
      print('DEBUG: Not found locally, checking online status...');
      if (await isOnline()) {
        print('DEBUG: Device is online, calling API...');
        final response = await ApiService.checkBarcode(scannedBarcode);
        print('DEBUG: API response: $response');

        final bool isCartridgeDetailScreen =
            widget.source == 'cartridge_detail';
        final bool barcodeExists = response['exists'] == true;
        print(
            'DEBUG: barcodeExists: $barcodeExists, isCartridgeDetailScreen: $isCartridgeDetailScreen');

        setState(() {
          barcodeStatus = barcodeExists
              ? 'Čárový kód je přiřazen k náboji ${response['cartridge']['name']}'
              : 'Čárový kód není přiřazen.';
        });

        if (!barcodeExists) {
          print('DEBUG: Barcode not exists, showing assign dialog');
          await _showAssignBarcodeDialog(scannedBarcode);
        } else if (isCartridgeDetailScreen) {
          print(
              'DEBUG: Cartridge detail screen - showing already assigned message');
          _showMessage('Tento čárový kód je již přiřazen k jinému náboji');
          await _resetScanner();
        } else {
          print('DEBUG: Showing increase stock dialog for API cartridge');
          final cartridge = response['cartridge'];
          await _showStockUpdateDialog(
            scannedBarcode,
            cartridge['name'],
            cartridge['manufacturer'] ?? 'Neznámý výrobce',
            cartridge['caliber']['name'] ?? 'Neznámý kalibr',
            cartridge['package_size'] ?? 0,
            cartridgeId: cartridge['id'], // Pass ID directly
          );
        }
      } else {
        print('DEBUG: Device is offline');
        _showMessage('Náboj nebyl nalezen v offline databázi');
        await _resetScanner();
      }
    } catch (e, stackTrace) {
      print('ERROR: Barcode check failed');
      print('Exception: $e');
      print('Stack trace: $stackTrace');
      _showMessage('Chyba při kontrole čárového kódu');
      await _resetScanner();
    }
  }

  Future<void> _showStockUpdateDialog(
      String scannedBarcode,
      String cartridgeName,
      String manufacturerName,
      String caliber,
      int packageSize,
      {int? cartridgeId}) async {
    if (cartridgeId == null) {
      _showMessage('Nelze získat ID náboje');
      return;
    }

    int currentStock = 0;
    final scaffoldContext = context;

    // Get current stock
    if (await isOnline()) {
      try {
        final response = await ApiService.checkBarcode(scannedBarcode);
        if (response['exists'] && response['cartridge'] != null) {
          currentStock = response['cartridge']['stock_quantity'] ?? 0;
          _updateStockQuantity(scannedBarcode, currentStock);
        }
      } catch (e) {
        print('Nelze načíst aktuální stav: $e');
        final dbHelper = DatabaseHelper();
        final cartridge = await dbHelper.getCartridgeByBarcode(scannedBarcode);
        currentStock = stockQuantities[scannedBarcode] ??
            cartridge?['stock_quantity'] ??
            0;
      }
    } else {
      final dbHelper = DatabaseHelper();
      final cartridge = await dbHelper.getCartridgeByBarcode(scannedBarcode);
      currentStock =
          stockQuantities[scannedBarcode] ?? cartridge?['stock_quantity'] ?? 0;
    }

    bool isIncrease = true;
    final quantityController = TextEditingController(
        text: packageSize > 0 ? packageSize.toString() : '');

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Upravit zásobu pro $cartridgeName'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Přidat')),
                      ButtonSegment(value: false, label: Text('Odebrat')),
                    ],
                    selected: {isIncrease},
                    onSelectionChanged: (Set<bool> newValue) {
                      setDialogState(() => isIncrease = newValue.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Výrobce: $manufacturerName'),
                  Text('Kalibr: $caliber'),
                  Text('Aktuálně skladem: $currentStock ks',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    decoration:
                        const InputDecoration(labelText: 'Zadejte množství'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final amount in [1, 10, 100])
                        ElevatedButton(
                          onPressed: () {
                            final currentValue =
                                int.tryParse(quantityController.text) ?? 0;
                            quantityController.text =
                                (currentValue + amount).toString();
                          },
                          child: Text('+$amount'),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Zrušit'),
                ),
                TextButton(
                  onPressed: () async {
                    int quantity = int.tryParse(quantityController.text) ?? 0;
                    if (quantity <= 0) return;

                    Navigator.pop(dialogContext);

                    final adjustedQuantity = isIncrease ? quantity : -quantity;
                    final operation = isIncrease ? 'navýšena' : 'snížena';

                    try {
                      if (await isOnline()) {
                        final response = await ApiService.increaseCartridge(
                            cartridgeId, adjustedQuantity);

                        if (response.containsKey('newStock')) {
                          _updateStockQuantity(
                              scannedBarcode, response['newStock']);

                          ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Skladová zásoba byla $operation o $quantity kusů.')));

                          if (response['warning'] != null) {
                            final warning = response['warning'];
                            if (warning['type'] == 'low_stock') {
                              await Future.delayed(const Duration(seconds: 1));

                              final cartridgesList = (warning['cartridges']
                                      as List)
                                  .map((c) => '${c['name']}: ${c['stock']} ks')
                                  .join('\n');

                              ScaffoldMessenger.of(scaffoldContext)
                                  .showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.warning_amber,
                                          color: Colors.white),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(warning['message']),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Celkem nábojů: ${warning['current_total']} ks (limit: ${warning['threshold']} ks)',
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(cartridgesList,
                                                style: const TextStyle(
                                                    fontSize: 12)),
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
                          await _resetScanner();
                          return;
                        }
                        throw Exception('API nevrátilo platnou odpověď');
                      }

                      // Offline mode
                      final newStock = currentStock + adjustedQuantity;
                      _updateStockQuantity(scannedBarcode, newStock);

                      await DatabaseHelper().addOfflineRequest(
                        'update_stock',
                        {'id': cartridgeId, 'quantity': adjustedQuantity},
                      );

                      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Skladová zásoba byla $operation o $quantity kusů.\n'
                            'Změny budou synchronizovány po obnovení připojení.',
                          ),
                        ),
                      );
                    } catch (e) {
                      print('Chyba při úpravě zásob: $e');

                      final newStock = currentStock + adjustedQuantity;
                      _updateStockQuantity(scannedBarcode, newStock);

                      await DatabaseHelper().addOfflineRequest(
                        'update_stock',
                        {'id': cartridgeId, 'quantity': adjustedQuantity},
                      );

                      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Chyba při komunikaci se serverem. Změna uložena offline.'),
                        ),
                      );
                    }

                    await _resetScanner();
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAssignBarcodeDialog(String scannedBarcode) async {
    print('DEBUG: Starting _showAssignBarcodeDialog');

    try {
      // Show loading dialog
      BuildContext? dialogContext;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialogContext = context;
          return const AlertDialog(
            title: Text('Načítání...'),
            content: CircularProgressIndicator(),
          );
        },
      );

      // Fetch data
      print('DEBUG: Fetching factory cartridges...');
      final cartridgesResponse = await ApiService.getFactoryCartridges();
      print('DEBUG: Got ${cartridgesResponse.length} factory cartridges');

      // Close loading dialog
      if (dialogContext != null) {
        Navigator.pop(dialogContext!);
      }

      if (!mounted) return;

      // Sort cartridges...
      print('DEBUG: Sorting cartridges...');
      final sortedCartridges = [...cartridgesResponse]..sort((a, b) {
          bool aHasBarcode = a['barcode'] != null && a['barcode'] != '';
          bool bHasBarcode = b['barcode'] != null && b['barcode'] != '';
          return aHasBarcode ? 1 : -1;
        });

      // Now show the main dialog
      print('DEBUG: Showing main dialog');
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          print('DEBUG: Building main dialog');
          return AlertDialog(
            title: const Text('Přiřadit čárový kód'),
            content: Container(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Create New Button
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
    } catch (e, stack) {
      print('ERROR in _showAssignBarcodeDialog: $e');
      print('Stack trace: $stack');
      if (mounted)
        Navigator.pop(context); // Close loading dialog if still showing
      _showMessage('Chyba při načítání nábojů: ${e.toString()}');
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

  void _toggleFlash() async {
    try {
      await controller?.toggleFlash();
      setState(() {
        isFlashOn = !isFlashOn;
      });
    } catch (e) {
      print('Error toggling flash: $e');
    }
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
              overlay: QrScannerOverlayShape(
                // Přidaný overlay
                borderColor: Colors.blue,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: 250,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Původní zobrazení naskenovaného kódu
                if (scannedCode != null) ...[
                  Text('Naskenovaný kód: $scannedCode'),
                  const SizedBox(height: 16),
                  Text(barcodeStatus ?? 'Kontrola čárového kódu...'),
                ],
                // Nové ovládání svítilny
                Text('Svítilna je ${isFlashOn ? "zapnutá" : "vypnutá"}'),
                ElevatedButton(
                  onPressed: _toggleFlash,
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
