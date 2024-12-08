import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';

class CartridgeSelectionWidget extends StatefulWidget {
  final Function(String) onCartridgeSelected;

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
  List<Map<String, dynamic>> cartridges = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCartridges();
  }

  Future<void> _loadCartridges() async {
    try {
      final response = await ApiService.getAllCartridges();
      setState(() {
        // Spojíme factory a reload náboje do jednoho listu
        cartridges = [
          ...response['factory'] ?? [],
          ...response['reload'] ?? []
        ];
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při načítání nábojů: $e')),
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
          onPressed: () async {
            // TODO: Implement barcode scanning
          },
          icon: Icon(Icons.qr_code_scanner),
          label: Text('Naskenovat kód'),
        ),
        SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: selectedCartridgeId,
          decoration: InputDecoration(
            labelText: 'Vyberte náboj',
            border: OutlineInputBorder(),
          ),
          items: cartridges.map((cartridge) {
            return DropdownMenuItem(
              value: cartridge['id'].toString(),
              child: Text(cartridge['name']),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              selectedCartridgeId = value;
            });
            if (value != null) {
              widget.onCartridgeSelected(value);
            }
          },
        ),
      ],
    );
  }
}
