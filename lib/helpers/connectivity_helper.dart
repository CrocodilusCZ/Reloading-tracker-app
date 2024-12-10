import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shooting_companion/services/sync_service.dart';

class ConnectivityHelper {
  final _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  final _controller = StreamController<bool>.broadcast();
  bool _isOnline = false;
  VoidCallback? _onlineCallback;
  late SyncService _syncService;

  ConnectivityHelper() {
    _initConnectivity();
    _setupConnectivityStream();
  }

  void setOnlineCallback(VoidCallback callback) {
    _onlineCallback = callback;
  }

  void registerSyncService(SyncService syncService) {
    _syncService = syncService;
    onConnectionChange.listen((isOnline) {
      if (isOnline) {
        _syncService.handleOnlineStateChange(true);
      }
    });
  }

  Future<void> _initConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final result = results is List
          ? (results as List<ConnectivityResult>).firstOrNull ??
              ConnectivityResult.none
          : results as ConnectivityResult;
      _updateConnectionStatus(result);
    } catch (e) {
      print('Error checking connectivity: $e');
    }
  }

  void _setupConnectivityStream() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final result =
            results.isNotEmpty ? results.first : ConnectivityResult.none;
        _updateConnectionStatus(result);
      },
    );
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    final isOnline = result != ConnectivityResult.none;
    if (_isOnline != isOnline) {
      _isOnline = isOnline;
      _controller.add(isOnline);
      print('Connection status changed: $result, isOnline: $_isOnline');

      // Spustit synchronizaci při obnovení připojení
      if (isOnline && _onlineCallback != null) {
        _onlineCallback!();
      }
    }
  }

  Future<bool> hasInternetConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (result == ConnectivityResult.none) {
        return false;
      }

      // Skutečná kontrola připojení k internetu
      final response = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return response.isNotEmpty && response[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (e) {
      print('Error checking internet connection: $e');
      return false;
    }
  }

  bool get isOnline => _isOnline;

  Stream<bool> get onConnectionChange => _controller.stream;

  Future<void> dispose() async {
    await _subscription.cancel();
    await _controller.close();
  }

  static void showNoInternetSnackBar(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Není k dispozici připojení k internetu'),
          duration: Duration(seconds: 3),
        ),
      );
    });
  }
}
