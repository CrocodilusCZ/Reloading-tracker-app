import 'dart:async';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class ConnectivityHelper {
  static final _checker = InternetConnection();

  static Future<bool> isOnline() async {
    try {
      return await _checker.hasInternetAccess;
    } catch (e) {
      print('Error checking internet connection: $e');
      return false;
    }
  }

  static Future<bool> isOffline() async {
    return !(await isOnline());
  }
}

class ConnectivityMonitor {
  final BuildContext context;
  final Function(bool) onConnectionChange;
  final _checker = InternetConnection();
  late StreamSubscription<InternetStatus> _subscription;

  ConnectivityMonitor({
    required this.context,
    required this.onConnectionChange,
  });

  Future<void> startMonitoring() async {
    final initialStatus = await ConnectivityHelper.isOnline();
    print('Initial connectivity status: $initialStatus'); // Debug print
    _handleConnectionChange(initialStatus);

    _subscription = _checker.onStatusChange.listen(
      (InternetStatus status) {
        final isOnline = status == InternetStatus.connected;
        print(
            'Connection status changed: $status, isOnline: $isOnline'); // Debug print
        _handleConnectionChange(isOnline);
      },
    );
  }

  void _handleConnectionChange(bool isOnline) {
    onConnectionChange(isOnline);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
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
