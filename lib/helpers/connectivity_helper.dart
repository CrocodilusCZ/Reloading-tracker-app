import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

Future<bool> isOnline() async {
  var connectivityResult = await Connectivity().checkConnectivity();
  return connectivityResult != ConnectivityResult.none;
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
    // Initial check
    final initialResult = await _connectivity.checkConnectivity();
    _handleConnectionChange(initialResult != ConnectivityResult.none);

    // Start listening for changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      // Check if any of the results indicate an online connection
      final isOnline = !results.contains(ConnectivityResult.none);
      _handleConnectionChange(isOnline);
    });
  }

  void _handleConnectionChange(bool isOnline) {
    onConnectionChange(isOnline);

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
