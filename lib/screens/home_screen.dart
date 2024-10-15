import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  final String username;

  const HomeScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Domovská Stránka'),
      ),
      body: Center( // Tento widget zajistí, že celý obsah bude vycentrován jak horizontálně, tak vertikálně
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Vertikální centrování sloupce
          crossAxisAlignment: CrossAxisAlignment.center, // Horizontální centrování sloupce
          children: [
            Text(
              'Uživatel: $username',
              style: const TextStyle(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/qr');
              },
              child: const Text('QR'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/inventory');
              },
              child: const Text('Inventář'),
            ),
          ],
        ),
      ),
    );
  }
}
