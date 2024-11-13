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
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: ExpansionTile(
        leading: Icon(icon, color: Colors.blueGrey),
        title: Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildComponentTable(components, type),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentTable(List<dynamic> components, String type) {
    List<DataColumn> columns;
    List<DataRow> rows;

    switch (type) {
      case 'bullets':
        columns = const [
          DataColumn(label: Text('Název')),
          DataColumn(label: Text('Váha (grains)')),
          DataColumn(label: Text('Výrobce')),
          DataColumn(label: Text('Průměr (inches)')),
          DataColumn(label: Text('Cena (Kč)')),
          DataColumn(label: Text('Skladová Zásoba (ks)')),
        ];
        rows = _buildRows(components, [
          'name',
          'weight_grains',
          'manufacturer',
          'diameter_inches',
          'price',
          'stock_quantity'
        ]);
        break;

      case 'powders':
        columns = const [
          DataColumn(label: Text('Výrobce')),
          DataColumn(label: Text('Název')),
          DataColumn(label: Text('Skladem gramů')),
        ];
        rows =
            _buildRows(components, ['manufacturer', 'name', 'stock_quantity']);
        break;

      case 'primers':
        columns = const [
          DataColumn(label: Text('Kategorie')),
          DataColumn(label: Text('Název')),
          DataColumn(label: Text('Cena (Kč)')),
          DataColumn(label: Text('Skladová Zásoba (ks)')),
        ];
        rows = _buildRows(
            components, ['categories', 'name', 'price', 'stock_quantity']);
        break;

      case 'brasses':
        columns = const [
          DataColumn(label: Text('Kalibr')),
          DataColumn(label: Text('Název')),
          DataColumn(label: Text('Skladová Zásoba (ks)')),
        ];
        rows =
            _buildRows(components, ['caliber.name', 'name', 'stock_quantity']);
        break;

      default:
        columns = [];
        rows = [];
    }

    return components.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('Nenalezeny žádné položky.',
                style: TextStyle(color: Colors.grey)),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: columns,
              rows: rows,
              columnSpacing: 12,
            ),
          );
  }

  List<DataRow> _buildRows(List<dynamic> components, List<String> fields) {
    return List.generate(
      components.length,
      (index) {
        final Map<String, dynamic> component =
            components[index] as Map<String, dynamic>;
        return DataRow.byIndex(
          index: index,
          color: MaterialStateProperty.resolveWith<Color?>(
            (Set<MaterialState> states) =>
                index % 2 == 0 ? Colors.grey[200] : null,
          ),
          cells: fields.map((field) {
            final value = _resolveNestedField(component, field.split('.'));
            return DataCell(
              Text(value?.toString() ?? 'Neznámá'),
            );
          }).toList(),
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
        return current[field]; // vrátí hodnotu, pokud není další úroveň mapy
      }
    }
    return current;
  }
}
