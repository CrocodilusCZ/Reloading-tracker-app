import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';

class InventoryComponentsScreen extends StatelessWidget {
  const InventoryComponentsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Přehled Skladových Zásob Komponent'),
        backgroundColor: Colors.blueGrey,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: ApiService.getInventoryComponents(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Chyba: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return const Center(
                child: Text('Žádné skladové zásoby nebyly nalezeny.'));
          }

          final data = snapshot.data!;
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCategoryCard(context, 'Střely', data['bullets'],
                      'bullets', Icons.bolt),
                  _buildCategoryCard(context, 'Prachy', data['powders'],
                      'powders', Icons.grain),
                  _buildCategoryCard(context, 'Zápalky', data['primers'],
                      'primers', Icons.flash_on),
                  _buildCategoryCard(context, 'Nábojnice', data['brasses'],
                      'brasses', Icons.memory),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, String title,
      List<dynamic> components, String type, IconData icon) {
    // Určení specifické ikony pro každý typ
    IconData cardIcon;
    switch (type) {
      case 'bullets':
        cardIcon = Icons.sports_martial_arts; // Ikona pro střely
        break;
      case 'powders':
        cardIcon = Icons.grain; // Ikona pro prachy
        break;
      case 'primers':
        cardIcon = Icons.local_fire_department; // Ikona pro zápalky
        break;
      case 'brasses':
        cardIcon = Icons.build_circle; // Ikona pro nábojnice
        break;
      default:
        cardIcon = Icons.help_outline; // Výchozí ikona
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: Icon(cardIcon, color: Colors.blueGrey, size: 32),
        title: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        children: components.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Nenalezeny žádné položky.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              ]
            : components
                .map((component) =>
                    _buildComponentCard(context, component, type))
                .toList(),
      ),
    );
  }

  Widget _buildComponentCard(
      BuildContext context, Map<String, dynamic> component, String type) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blueGrey.shade100,
          child: Icon(
            type == 'bullets'
                ? Icons.sports_martial_arts
                : type == 'powders'
                    ? Icons.grain
                    : type == 'primers'
                        ? Icons.local_fire_department
                        : Icons.build_circle,
            color: Colors.blueGrey,
          ),
        ),
        title: Text(
          component['name'] ?? 'Neznámý',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          type == 'bullets'
              ? 'Váha: ${component['weight_grains']} grains | Výrobce: ${component['manufacturer']}'
              : type == 'powders'
                  ? 'Výrobce: ${component['manufacturer']} | Skladem: ${component['stock_quantity']} g'
                  : type == 'primers'
                      ? 'Kategorie: ${component['categories']} | Skladem: ${component['stock_quantity']} ks'
                      : 'Kalibr: ${component['caliber.name']} | Skladem: ${component['stock_quantity']} ks',
          style: const TextStyle(color: Colors.grey),
        ),
        onTap: () => _showComponentDetails(context, component, type),
      ),
    );
  }

  Map<String, String> _getFieldsByType(String type) {
    switch (type) {
      case 'bullets':
        return {
          'name': 'Název',
          'weight_grains': 'Váha (grains)',
          'manufacturer': 'Výrobce',
          'diameter_inches': 'Průměr (inches)',
          'price': 'Cena (Kč)',
          'stock_quantity': 'Skladová Zásoba (ks)',
        };
      case 'powders':
        return {
          'manufacturer': 'Výrobce',
          'name': 'Název',
          'stock_quantity': 'Skladem gramů',
        };
      case 'primers':
        return {
          'categories': 'Kategorie',
          'name': 'Název',
          'price': 'Cena (Kč)',
          'stock_quantity': 'Skladová Zásoba (ks)',
        };
      case 'brasses':
        return {
          'caliber.name': 'Kalibr',
          'name': 'Název',
          'stock_quantity': 'Skladová Zásoba (ks)',
        };
      default:
        return {};
    }
  }

  void _showComponentDetails(
      BuildContext context, Map<String, dynamic> component, String type) {
    final fields = _getFieldsByType(type);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Detail položky: ${component['name'] ?? 'Neznámá'}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: fields.entries.map((entry) {
                final value =
                    _resolveNestedField(component, entry.key.split('.'));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    '${entry.value}: ${value ?? 'Neznámá'}',
                    style: const TextStyle(fontSize: 16),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Zavřít'),
            ),
          ],
        );
      },
    );
  }

  dynamic _resolveNestedField(Map<String, dynamic> map, List<String> fields) {
    var current = map;
    for (var field in fields) {
      if (current[field] is Map<String, dynamic>) {
        current = current[field];
      } else {
        return current[field];
      }
    }
    return current;
  }
}
