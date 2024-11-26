import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';

class FactoryCartridgeForm extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final String? scannedBarcode;
  final Function(Map<String, dynamic>)? onSave;

  const FactoryCartridgeForm({
    Key? key,
    this.initialData,
    this.scannedBarcode,
    this.onSave,
  }) : super(key: key);

  @override
  State<FactoryCartridgeForm> createState() => FactoryCartridgeFormState();
}

class FactoryCartridgeFormState extends State<FactoryCartridgeForm> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController manufacturerController = TextEditingController();
  final TextEditingController bulletSpecController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController stockController = TextEditingController();
  final TextEditingController packageSizeController = TextEditingController();
  bool isFavorite = false;
  int? selectedCaliberId;
  List<Map<String, dynamic>> calibers = [];

  @override
  void initState() {
    super.initState();
    _loadCalibers();
    _initializeControllers();
  }

  void _initializeControllers() {
    if (widget.initialData != null) {
      nameController.text = widget.initialData!['name'] ?? '';
      manufacturerController.text = widget.initialData!['manufacturer'] ?? '';
      bulletSpecController.text =
          widget.initialData!['bullet_specification'] ?? '';
      priceController.text = widget.initialData!['price']?.toString() ?? '';
      stockController.text =
          widget.initialData!['stock_quantity']?.toString() ?? '';
      packageSizeController.text =
          widget.initialData!['package_size']?.toString() ?? '';
      isFavorite = widget.initialData!['is_favorite'] ?? false;
      selectedCaliberId = widget.initialData!['caliber_id'];
    }
  }

  Future<void> _loadCalibers() async {
    try {
      final response = await ApiService.getCalibers();
      setState(() {
        calibers = List<Map<String, dynamic>>.from(
            response.map((item) => Map<String, dynamic>.from(item)));
      });
    } catch (e) {
      print('Error loading calibers: $e');
      // Optional: Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při načítání kalibrů: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Název náboje'),
          ),
          TextField(
            controller: manufacturerController,
            decoration: const InputDecoration(labelText: 'Výrobce'),
          ),
          TextField(
            controller: bulletSpecController,
            decoration: const InputDecoration(labelText: 'Specifikace střely'),
          ),
          TextField(
            controller: priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cena za kus'),
          ),
          TextField(
            controller: stockController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Skladová zásoba'),
          ),
          TextField(
            controller: packageSizeController,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Velikost prodejního balení'),
          ),
          TextFormField(
            controller: TextEditingController(
                text: selectedCaliberId != null
                    ? calibers
                        .firstWhere((c) => c['id'] == selectedCaliberId)['name']
                    : "Vyberte kalibr"),
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Kalibr'),
            onTap: () => _showCaliberDialog(context),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Oblíbený'),
              Switch(
                value: isFavorite,
                onChanged: (value) => setState(() => isFavorite = value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCaliberDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Vyberte kalibr'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: calibers.length,
              itemBuilder: (context, index) {
                final caliber = calibers[index];
                return ListTile(
                  title: Text(caliber['name']),
                  onTap: () {
                    setState(() => selectedCaliberId = caliber['id']);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zrušit'),
            ),
          ],
        );
      },
    );
  }

  Map<String, dynamic> getFormData() {
    return {
      'name': nameController.text,
      'manufacturer': manufacturerController.text,
      'bullet_specification': bulletSpecController.text,
      'caliber_id': selectedCaliberId,
      'price': double.tryParse(priceController.text) ?? 0.0,
      'stock_quantity': int.tryParse(stockController.text) ?? 0,
      'package_size': int.tryParse(packageSizeController.text) ?? 1,
      'barcode': widget.scannedBarcode,
      'is_favorite': isFavorite,
    };
  }
}
