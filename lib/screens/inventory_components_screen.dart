import 'package:flutter/material.dart';
import 'package:shooting_companion/services/api_service.dart';

class InventoryComponentsScreen extends StatefulWidget {
  const InventoryComponentsScreen({Key? key}) : super(key: key);

  @override
  State<InventoryComponentsScreen> createState() =>
      _InventoryComponentsScreenState();
}

class _InventoryComponentsScreenState extends State<InventoryComponentsScreen> {
// Add refresh trigger
  final _refreshKey = GlobalKey();
  Future<Map<String, dynamic>>? _inventoryFuture;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  void _loadInventory() {
    setState(() {
      _inventoryFuture = ApiService.getInventoryComponents();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        key: _refreshKey,
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
          iconTheme: const IconThemeData(
            color: Colors.white, // Makes back arrow white
          ),
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
          future: _inventoryFuture,
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

  Future<void> _showStockDialog(
      BuildContext context, Map<String, dynamic> item, String type) {
    final TextEditingController controller = TextEditingController();
    final unit = type == 'powders' ? 'g' : 'ks';
    final currentStock = item['stock_quantity'] as int;
    int changeAmount = 0;

    void handleQuantityChange(StateSetter setState, int amount) {
      setState(() {
        changeAmount += amount;
        controller.text = changeAmount.toString();
      });
    }

    Future<void> handleSave() async {
      if (changeAmount == 0) return;

      try {
        await ApiService.increaseComponentStock(type, item['id'], changeAmount);
        Navigator.pop(context);
        _loadInventory(); // Refresh parent screen
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Chyba: $e')));
      }
    }

    return showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  ListTile(
                    title: Text(
                      item['name'] ?? 'Neznámý název',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    subtitle: Text(
                      'Současný stav: $currentStock $unit',
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Change preview
                  if (changeAmount != 0) ...[
                    Divider(),
                    ListTile(
                      title: Text(
                        'Změna: ${changeAmount > 0 ? "+$changeAmount" : changeAmount} $unit',
                        style: TextStyle(
                            color: changeAmount > 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      subtitle: Text(
                        'Nový stav: ${currentStock + changeAmount} $unit',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  // Quick actions
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () => handleQuantityChange(setState, -100),
                          child: Text('-100'),
                        ),
                        ElevatedButton(
                          onPressed: () => handleQuantityChange(setState, 100),
                          child: Text('+100'),
                        ),
                        ElevatedButton(
                          onPressed: () => handleQuantityChange(setState, 500),
                          child: Text('+500'),
                        ),
                      ],
                    ),
                  ),

                  // Manual input
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Upravit změnu množství',
                        suffixText: unit,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          setState(() {
                            changeAmount = int.tryParse(value) ?? 0;
                          });
                        }
                      },
                    ),
                  ),

                  // Actions
                  ButtonBar(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Zrušit'),
                      ),
                      ElevatedButton(
                        onPressed: handleSave,
                        child: Text('Uložit změnu'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Future<void> _updateStock(String type, int id, int quantity,
      {bool setExact = false}) async {
    try {
      if (setExact) {
        await ApiService.updateComponentStock(type, id, quantity);
      } else {
        await ApiService.increaseComponentStock(type, id, quantity);
      }
      Navigator.pop(context);
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Chyba: $e')));
    }
  }

  Widget _buildComponentList(List<dynamic> items, Color color, IconData icon) {
    String getType(IconData icon) {
      if (icon == Icons.bolt) return 'bullets';
      if (icon == Icons.grain) return 'powders';
      if (icon == Icons.flash_on) return 'primers';
      if (icon == Icons.memory) return 'brasses';
      return '';
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        String subtitle = '';
        if (icon == Icons.bolt) {
          subtitle =
              '${item['manufacturer'] ?? 'Neznámý výrobce'} • ${item['weight_grains'] ?? '?'} gr • ${item['diameter_inches'] ?? '?'} inch';
        } else if (icon == Icons.grain) {
          subtitle =
              'Balení: ${item['weight'] ?? '0'} g • ${item['price_per_package'] ?? '0'} Kč';
        } else if (icon == Icons.flash_on) {
          subtitle =
              '${item['categories'] ?? 'Neznámá'} • ${item['price'] ?? '0'} Kč/ks';
        } else if (icon == Icons.memory) {
          subtitle =
              '${item['caliber']?['name'] ?? 'Neznámý kalibr'} • ${item['caliber']?['bullet_diameter'] ?? '?'} inch';
        }

        return Card(
          elevation: 1,
          child: InkWell(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Left: Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),

                  // Middle: Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item['name'] ?? 'Neznámý název',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right: Stock with tap area
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () =>
                          _showStockDialog(context, item, getType(icon)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${item['stock_quantity'] ?? 0} ${icon == Icons.grain ? 'g' : 'ks'}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.edit_outlined, size: 16, color: color),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
