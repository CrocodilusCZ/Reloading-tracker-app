import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';

class InventoryComponentsScreen extends StatelessWidget {
  const InventoryComponentsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Skladové Zásoby',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.blueGrey[800],
          elevation: 0,
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            tabs: const [
              Tab(
                icon: Icon(Icons.bolt),
                text: 'Střely',
              ),
              Tab(
                icon: Icon(Icons.grain),
                text: 'Prachy',
              ),
              Tab(
                icon: Icon(Icons.flash_on),
                text: 'Zápalky',
              ),
              Tab(
                icon: Icon(Icons.memory),
                text: 'Nábojnice',
              ),
            ],
          ),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: ApiService.getInventoryComponents(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingState();
            }
            if (snapshot.hasError) {
              return _buildErrorState(snapshot.error);
            }
            if (!snapshot.hasData) {
              return _buildEmptyState();
            }

            final data = snapshot.data!;
            return TabBarView(
              children: [
                _buildComponentList(
                    data['bullets'], Colors.blue[700]!, Icons.bolt),
                _buildComponentList(
                    data['powders'], Colors.green[700]!, Icons.grain),
                _buildComponentList(
                    data['primers'], Colors.orange[700]!, Icons.flash_on),
                _buildComponentList(
                    data['brasses'], Colors.brown[700]!, Icons.memory),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.blueGrey),
      ),
    );
  }

  Widget _buildErrorState(dynamic error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text('Chyba: $error', style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Žádné skladové zásoby'),
        ],
      ),
    );
  }

  Widget _buildComponentList(List<dynamic> items, Color color, IconData icon) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color),
            ),
            title: Text(
              item['name'] ?? 'Neznámý název',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  item['caliber']?['name'] ?? 'Neznámý kalibr',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${item['stock_quantity'] ?? 0} ks',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
