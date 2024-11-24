import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

Future<bool> isOnline() async {
  var connectivityResult = await Connectivity().checkConnectivity();
  if (connectivityResult == ConnectivityResult.none) {
    return false;
  }

  try {
    final result = await InternetAddress.lookup('8.8.8.8');
    if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
      return true;
    }
  } catch (e) {
    print('Chyba při ověřování připojení k internetu: $e');
  }
  return false;
}

class ConnectivityMonitor {
  final BuildContext context;
  final Function(bool) onConnectionChange;
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _subscription;

  ConnectivityMonitor({
    required this.context,
    required this.onConnectionChange,
  });

  Future<void> startMonitoring() async {
    // Počáteční kontrola stavu připojení
    final initialStatus = await isOnline();
    _handleConnectionChange(initialStatus);

    // Sleduj změny připojení
    _subscription = _connectivity.onConnectivityChanged
        .listen((List<ConnectivityResult> results) async {
      // Check if any of the results indicate a connection
      final hasConnection =
          results.any((result) => result != ConnectivityResult.none);
      if (hasConnection) {
        final currentStatus = await isOnline();
        _handleConnectionChange(currentStatus);
      } else {
        _handleConnectionChange(false);
      }
    });
  }

  void _handleConnectionChange(bool isOnline) {
    onConnectionChange(isOnline);

    // Prevent showing multiple SnackBars
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isOnline
              ? 'Jste online. Data se budou synchronizovat s API.'
              : 'Jste offline. Data budou načtena z lokální databáze.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void stopMonitoring() {
    _subscription.cancel();
  }
}
