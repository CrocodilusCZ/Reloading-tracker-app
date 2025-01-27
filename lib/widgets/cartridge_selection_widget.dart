import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/helpers/connectivity_helper.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import '../screens/qr_scan_screen.dart';

class CartridgeSelectionWidget extends StatefulWidget {
  final void Function(
          String cartridgeId, String caliberId, String cartridgeName)
      onCartridgeSelected;
  const CartridgeSelectionWidget({
    Key? key,
    required this.onCartridgeSelected,
  }) : super(key: key);

  @override
  _CartridgeSelectionWidgetState createState() =>
      _CartridgeSelectionWidgetState();
}

class _CartridgeSelectionWidgetState extends State<CartridgeSelectionWidget> {
  String? selectedCartridgeId;
  String? selectedCaliberId;
  String? selectedFilter;
  List<Map<String, dynamic>> cartridges = [];
  bool isLoading = true;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadCartridges();
  }

  List<Map<String, dynamic>> get filteredCartridges {
    print('DEBUG: Current filter: $selectedFilter'); // Debug print
    if (selectedFilter == null) return cartridges;
    return cartridges.where((c) {
      final type = c['cartridge_type']?.toString().toLowerCase();
      print('DEBUG: Cartridge ${c['name']} type: $type'); // Debug print
      return type == selectedFilter;
    }).toList();
  }

  // Update _loadCartridges() method:
  Future<void> _loadCartridges() async {
    try {
      final localCartridges = await _dbHelper.getAllCartridges();
      if (localCartridges.isNotEmpty) {
        setState(() {
          cartridges = localCartridges.map((c) {
            // Ensure cartridge_type is set
            if (c['cartridge_type'] == null) {
              c['cartridge_type'] =
                  c['type'] ?? 'factory'; // Try fallback to 'type' field
            }
            return c;
          }).toList();
          isLoading = false;
        });
      }

      final connectivityHelper = ConnectivityHelper();
      final hasInternet = await connectivityHelper.hasInternetConnection();
      if (hasInternet) {
        final response = await ApiService.getAllCartridges();

        final List<Map<String, dynamic>> factoryCartridges =
            (response['factory'] as List? ?? []).map((item) {
          final map = Map<String, dynamic>.from(item);
          map['cartridge_type'] = 'factory'; // Set type explicitly
          return map;
        }).toList();

        final List<Map<String, dynamic>> reloadCartridges =
            (response['reload'] as List? ?? []).map((item) {
          final map = Map<String, dynamic>.from(item);
          map['cartridge_type'] = 'reload'; // Set type explicitly
          return map;
        }).toList();

        final List<Map<String, dynamic>> apiCartridges = [
          ...factoryCartridges,
          ...reloadCartridges,
        ];

        await _dbHelper.cacheCartridges(apiCartridges);

        setState(() {
          cartridges = apiCartridges;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při načítání nábojů: $e')),
      );
    }
  }

  // Add this method to CartridgeSelectionWidget class
  Future<void> _handleBarcodeScanning() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const QRScanScreen()),
      );

      if (result == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vyhledávání náboje...')),
      );

      final String scannedBarcode = result.toString().trim();
      if (scannedBarcode.isEmpty) throw Exception('Prázdný čárový kód');

      final bool isOnline = await ConnectivityHelper().hasInternetConnection();
      print('Connection status: ${isOnline ? "Online" : "Offline"}');

      Map<String, dynamic>? cartridgeData;
      try {
        if (isOnline) {
          print('Fetching from API: $scannedBarcode');
          final apiResponse = await ApiService.checkBarcode(scannedBarcode);
          cartridgeData = apiResponse['cartridge'];
        } else {
          print('Fetching from local DB: $scannedBarcode');
          cartridgeData =
              await DatabaseHelper().getCartridgeByBarcode(scannedBarcode);
        }
        print('Response data: $cartridgeData');
      } catch (e) {
        print('Data fetch error: $e');
        throw Exception(isOnline
            ? 'Chyba při komunikaci s API'
            : 'Chyba při čtení z databáze');
      }

      if (cartridgeData == null) {
        throw Exception('Náboj nebyl nalezen');
      }

      final id = cartridgeData['id']?.toString();
      final caliberId = cartridgeData['caliber_id']?.toString();

      if (id == null || caliberId == null) {
        print('Invalid cartridge data: $cartridgeData');
        throw Exception('Neplatná data náboje');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      setState(() {
        selectedCartridgeId = id;
      });

      widget.onCartridgeSelected(id, caliberId,
          cartridgeData['name'].toString() // získat název z načtených dat
          );
    } catch (e, stackTrace) {
      print('Error in barcode scanning: $e');
      print('Stack trace: $stackTrace');

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().contains('Exception:')
              ? e.toString().replaceAll('Exception: ', '')
              : 'Chyba při skenování'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _handleBarcodeScanning,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Naskenovat kód'),
        ),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FilterChip(
              label: Text('Vše'),
              selected: selectedFilter == null,
              onSelected: (selected) {
                setState(() {
                  selectedFilter = selected ? null : selectedFilter;
                  selectedCartridgeId =
                      null; // Reset selection when filter changes
                });
              },
            ),
            FilterChip(
              label: Text('Tovární'),
              selected: selectedFilter == 'factory',
              onSelected: (selected) {
                setState(() {
                  selectedFilter = selected ? 'factory' : null;
                  selectedCartridgeId =
                      null; // Reset selection when filter changes
                });
              },
            ),
            FilterChip(
              label: Text('Přebíjené'),
              selected: selectedFilter == 'reload',
              onSelected: (selected) {
                setState(() {
                  selectedFilter = selected ? 'reload' : null;
                  selectedCartridgeId =
                      null; // Reset selection when filter changes
                });
              },
            ),
          ],
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: selectedCartridgeId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Vyberte náboj....',
            border: OutlineInputBorder(),
          ),
          // Simplified selected item display
          selectedItemBuilder: (BuildContext context) {
            return filteredCartridges.map((cartridge) {
              return Text(
                cartridge['name'] ?? 'Unnamed',
                overflow: TextOverflow.ellipsis,
              );
            }).toList();
          },
          // Keep detailed items in dropdown
          items: filteredCartridges.map((cartridge) {
            // Debug print to check cartridge data
            print('DEBUG: Cartridge data: ${cartridge.toString()}');

            String? caliber = cartridge['caliber_name'];
            if (caliber == null) {
              // Try to get caliber from caliber object if it exists
              caliber = cartridge['caliber']?['name'];
            }

            // Debug print for caliber
            print('DEBUG: Caliber for ${cartridge['name']}: $caliber');

            return DropdownMenuItem(
              value: cartridge['id'].toString(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cartridge['name'] ?? 'Unnamed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    [
                      caliber ?? 'Unknown Caliber', // Add fallback text
                      cartridge['cartridge_type'] == 'factory'
                          ? 'Tovární'
                          : 'Přebíjené',
                      cartridge['manufacturer'],
                    ]
                        .where((item) => item != null && item.isNotEmpty)
                        .join(' • '),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              final selectedCartridge =
                  cartridges.firstWhere((c) => c['id'].toString() == value);

              setState(() {
                selectedCartridgeId = value;
                selectedCaliberId = selectedCartridge['caliber_id'].toString();
              });

              // Pass both IDs to parent
              widget.onCartridgeSelected(
                selectedCartridgeId!,
                selectedCaliberId!,
                selectedCartridge['name'].toString(), // Přidáno
              );
            }
          },
        ),
      ],
    );
  }
}
