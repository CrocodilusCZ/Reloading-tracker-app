import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';

class WeaponSelectionWidget extends StatefulWidget {
  final String? cartridgeId;
  final Function(String) onWeaponSelected;

  const WeaponSelectionWidget({
    Key? key,
    required this.cartridgeId,
    required this.onWeaponSelected,
  }) : super(key: key);

  @override
  _WeaponSelectionWidgetState createState() => _WeaponSelectionWidgetState();
}

class _WeaponSelectionWidgetState extends State<WeaponSelectionWidget> {
  String? selectedWeaponId;
  List<Map<String, dynamic>> weapons = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.cartridgeId != null) {
      _loadWeapons();
    }
  }

  @override
  void didUpdateWidget(WeaponSelectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cartridgeId != oldWidget.cartridgeId) {
      _loadWeapons();
    }
  }

  Future<void> _loadWeapons() async {
    if (widget.cartridgeId == null) return;

    setState(() => isLoading = true);
    try {
      // First get cartridge details to get caliber ID
      final cartridge =
          await ApiService.getCartridgeById(int.parse(widget.cartridgeId!));

      // Extract caliber ID from cartridge
      final caliberId = cartridge['caliber']['id'];
      print(
          'Načítám zbraně pro kalibr ID: $caliberId z náboje ID: ${widget.cartridgeId}');

      // Then load weapons for that caliber
      final weaponsList = await ApiService.getUserWeaponsByCaliber(caliberId);

      setState(() {
        weapons = weaponsList;
        isLoading = false;
      });
    } catch (e) {
      print('Chyba při načítání zbraní: $e');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při načítání zbraní: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cartridgeId == null) {
      return Text('Nejdříve vyberte náboj');
    }

    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (weapons.isEmpty) {
      return Text('Žádné kompatibilní zbraně nenalezeny');
    }

    return DropdownButtonFormField<String>(
      value: selectedWeaponId,
      decoration: InputDecoration(
        labelText: 'Vyberte zbraň',
        border: OutlineInputBorder(),
      ),
      items: weapons.map((weapon) {
        return DropdownMenuItem(
          value: weapon['id'].toString(),
          child: Text(weapon['name']),
        );
      }).toList(),
      onChanged: (value) {
        setState(() => selectedWeaponId = value);
        if (value != null) {
          widget.onWeaponSelected(value);
        }
      },
    );
  }
}
