import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/helpers/connectivity_helper.dart';
import 'package:shooting_companion/helpers/database_helper.dart';

class WeaponSelectionWidget extends StatefulWidget {
  final String? caliberId; // Changed from cartridgeId
  final Function(String) onWeaponSelected;

  const WeaponSelectionWidget({
    Key? key,
    required this.caliberId, // Changed from cartridgeId
    required this.onWeaponSelected,
  }) : super(key: key);

  @override
  _WeaponSelectionWidgetState createState() => _WeaponSelectionWidgetState();
}

class _WeaponSelectionWidgetState extends State<WeaponSelectionWidget> {
  String? selectedWeaponId;
  List<Map<String, dynamic>> weapons = [];
  bool isLoading = true;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    if (widget.caliberId != null) {
      // Changed from cartridgeId
      _loadWeapons();
    }
  }

  @override
  void didUpdateWidget(WeaponSelectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.caliberId != oldWidget.caliberId) {
      // Changed from cartridgeId
      _loadWeapons();
    }
  }

  Future<void> _loadWeapons() async {
    if (widget.caliberId == null) return; // Changed from cartridgeId

    setState(() => isLoading = true);
    try {
      final caliberId =
          int.parse(widget.caliberId!); // Changed from cartridgeId
      final localWeapons = await DatabaseHelper.getWeaponsByCaliber(caliberId);

      setState(() {
        weapons = localWeapons;
        isLoading = false;
      });
    } catch (e) {
      print('ERROR: Failed to load weapons: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    if (widget.caliberId == null) {
      // Changed from cartridgeId
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
