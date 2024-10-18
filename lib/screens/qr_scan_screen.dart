import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shooting_companion/services/api_service.dart';

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});

  @override
  _QRScanScreenState createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.request();
    if (status.isGranted) {
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Kamera je potřeba pro skenování QR kódů')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skenování QR Kódu'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child:
                  Text(isProcessing ? 'Zpracovává se...' : 'Naskenujte QR kód'),
            ),
          )
        ],
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (!isProcessing && scanData.code != null) {
        setState(() {
          isProcessing = true;
        });
        controller.pauseCamera(); // Zastaví kameru po naskenování
        _processScannedData(
            scanData.code!); // Použijte '!', protože scanData.code už není null
      }
    });
  }

  Future<void> _processScannedData(String code) async {
    try {
      final decodedData = jsonDecode(code);
      final int cartridgeId = decodedData['cartridge_id'];

      final cartridge = await ApiService.getCartridgeById(cartridgeId);

      if (cartridge['status'] == 'success') {
        final action = await _showActionDialog(context, cartridge['cartridge']);

        if (action != null) {
          await _sendRequestToServer(cartridgeId, action);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Chyba při získávání informací o náboji: ${cartridge['message']}')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při zpracování QR kódu: $error')),
      );
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  Future<String?> _showActionDialog(
      BuildContext context, Map<String, dynamic> cartridge) async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Vyberte akci pro ${cartridge['name']}'),
          content: Text('Chcete zásobu nábojů navýšit nebo snížit? \n\n'
              'Náboj: ${cartridge['description']}\n'
              'Kalibr: ${cartridge['caliber_name']}\n'
              'Skladem: ${cartridge['stock_quantity']} ks'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, 'increase'),
              child: const Text('Navýšit'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'decrease'),
              child: const Text('Snížit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendRequestToServer(int cartridgeId, String action) async {
    try {
      final cartridgeBeforeUpdate =
          await ApiService.getCartridgeById(cartridgeId);
      final int oldQuantity =
          cartridgeBeforeUpdate['cartridge']['stock_quantity'];

      int quantityChange = action == 'increase' ? 50 : -50;

      final response =
          await ApiService.updateCartridgeQuantity(cartridgeId, quantityChange);

      if (response['status'] == 'success') {
        final cartridgeAfterUpdate =
            await ApiService.getCartridgeById(cartridgeId);
        final int newQuantity =
            cartridgeAfterUpdate['cartridge']['stock_quantity'];

        await _showConfirmationScreen(
            context,
            cartridgeBeforeUpdate['cartridge']['name'],
            oldQuantity,
            newQuantity);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba: ${response['message']}')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při aktualizaci stavu nábojů: $error')),
      );
    }
  }

  Future<void> _showConfirmationScreen(BuildContext context,
      String cartridgeName, int oldQuantity, int newQuantity) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Potvrzení'),
          content: Text(
            'Náboj $cartridgeName byl úspěšně aktualizován.\n'
            'Původní stav: $oldQuantity ks\n'
            'Nový stav: $newQuantity ks\n\n'
            'Chcete pokračovat ve skenování?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ano'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Ne'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      setState(() {
        isProcessing = false;
      });
      controller?.resumeCamera(); // Obnovení kamery po potvrzení pokračování
    } else {
      Navigator.of(context)
          .pop(); // Vrať se zpět na předchozí obrazovku (dashboard)
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}
