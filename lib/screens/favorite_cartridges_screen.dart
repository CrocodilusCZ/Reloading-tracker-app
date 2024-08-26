import 'package:flutter/material.dart';
import 'package:simple_login_app/services/api_service.dart';

class FavoriteCartridgesScreen extends StatelessWidget {
  const FavoriteCartridgesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Oblíbené náboje'),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: ApiService.getFavoriteCartridges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Žádné oblíbené náboje'));
          } else {
            final cartridges = snapshot.data!;
            return ListView.builder(
              itemCount: cartridges.length,
              itemBuilder: (context, index) {
                final cartridge = cartridges[index];
                return ListTile(
                  title: Text(
                    '${cartridge['caliber_name']} - ${cartridge['bullet_name']}',
                    style: const TextStyle(fontFamily: 'Roboto'),
                  ),
                  subtitle: Text(
                    'Prach: ${cartridge['powder_name']} (${cartridge['powder_weight']}g)\nZápalka: ${cartridge['primer_name']}',
                    style: const TextStyle(fontFamily: 'Roboto'),
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Cena: ${cartridge['price']} Kč',
                        style: const TextStyle(fontFamily: 'Roboto'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Skladem: ${cartridge['stock_quantity']} ks',
                        style: const TextStyle(fontFamily: 'Roboto'),
                      ),
                    ],
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
