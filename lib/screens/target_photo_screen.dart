import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/widgets/cartridge_selection_widget.dart';
import 'package:shooting_companion/widgets/weapon_selection_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shooting_companion/helpers/connectivity_helper.dart';
import 'package:shooting_companion/helpers/database_helper.dart';
import 'package:shooting_companion/models/target_photo_request.dart';

class TargetPhotoScreen extends StatefulWidget {
  @override
  _TargetPhotoScreenState createState() => _TargetPhotoScreenState();
}

class _TargetPhotoScreenState extends State<TargetPhotoScreen> {
  int _currentStep = 0;
  String? selectedCartridgeId;
  String? selectedCaliberId;
  String? selectedWeaponId;
  File? targetImage;
  final TextEditingController distanceController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final ConnectivityHelper _connectivityHelper = ConnectivityHelper();

  Future<void> _takePhoto() async {
    final ImagePicker picker = ImagePicker();
    // Add imageQuality parameter to reduce file size
    final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100, // Reduces image quality to 50%
        maxWidth: 1920, // Limits max width
        maxHeight: 1080 // Limits max height
        );

    if (photo != null) {
      setState(() {
        targetImage = File(photo.path);
      });

      // Log compressed file size
      print('Compressed image size: ${await targetImage!.length()} bytes');
    }
  }

  Future<void> _submitData() async {
    // 1. Validace vstupu
    if (targetImage == null || selectedCartridgeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vyberte fotografii a náboj')),
      );
      return;
    }

    try {
      // 2. Vytvoření požadavku na fotku
      final photo = TargetPhotoRequest(
        id: 0,
        photoPath: targetImage!.path,
        note: notesController.text,
        createdAt: DateTime.now(),
        isSynced: false,
        cartridgeId: int.parse(selectedCartridgeId!),
      );

      // 3. Uložení lokálně
      final DatabaseHelper dbHelper = DatabaseHelper();
      final photoId = await dbHelper.insertTargetPhoto(photo);
      print('DEBUG: Photo saved locally with ID: $photoId');

      // 4. Kontrola připojení
      final connectivityHelper = ConnectivityHelper();
      final hasInternet = await connectivityHelper.hasInternetConnection();
      print('DEBUG: Checking actual internet connectivity...');
      print('DEBUG: Internet connection status: $hasInternet');

      if (!hasInternet) {
        // Debug print to verify data
        print('DEBUG: Saving offline request with photoId: $photoId');

        // 1. Uložení požadavku do offline_requests
        final requestData = {
          'request_type': 'upload_target_photo',
          'data': jsonEncode({
            'photo_id': photoId,
            'photo_path': targetImage!.path,
            'notes': notesController.text,
            'distance': distanceController.text,
            'weapon_id': selectedWeaponId,
            'cartridge_id': selectedCartridgeId,
          }),
          'status': 'pending',
        };

        print('DEBUG: Request data: $requestData');

        await dbHelper.insertOfflineRequest(requestData);

        // Debug print to confirm insertion
        print('DEBUG: Offline request saved successfully');

        // 2. Navigace a zobrazení zprávy uživateli
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Terč byl uložen lokálně a bude synchronizován později')),
        );
        return;
      }

      // 5. Online synchronizace
      try {
        // Získání tokenu
        SharedPreferences prefs = await SharedPreferences.getInstance();
        String? token = prefs.getString('api_token');
        if (token == null) {
          throw Exception('Authentication token not found');
        }

        // Příprava požadavku
        var request = http.MultipartRequest(
          'POST',
          Uri.parse(
              '${ApiService.baseUrl}/cartridges/$selectedCartridgeId/targets'),
        );

        request.headers.addAll(
            {'Authorization': 'Bearer $token', 'Accept': 'application/json'});

        // Přidání souboru s fotkou
        request.files.add(
          await http.MultipartFile.fromPath('image', targetImage!.path),
        );

        // Přidání volitelných polí
        if (distanceController.text.isNotEmpty) {
          request.fields['distance'] = distanceController.text;
        }
        if (notesController.text.isNotEmpty) {
          request.fields['notes'] = notesController.text;
        }
        if (selectedWeaponId != null) {
          request.fields['weapon_id'] = selectedWeaponId!;
        }

        // Odeslání požadavku
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 201) {
          // Úspěch - označit jako synchronizované
          await dbHelper.markPhotoAsSynced(photoId);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Terč byl úspěšně uložen a synchronizován')),
          );
        } else {
          // Chyba serveru
          throw Exception(
              'Server returned ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        print('Error syncing with server: $e');
        Navigator.pop(context);

        // Úspěšně uloženo lokálně, ale synchronizace se nezdařila
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Terč uložen lokálně a bude synchronizován později')),
        );
      }
    } catch (e) {
      // Kritická chyba - nepodařilo se ani lokální uložení
      print('Error in _submitData: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při ukládání: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Fotografie terče',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
            shadows: [
              Shadow(
                offset: Offset(2, 2),
                color: Colors.black54,
                blurRadius: 4,
              ),
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueGrey,
        actions: [
          StreamBuilder<bool>(
            stream: _connectivityHelper.onConnectionChange,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? false;
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Tooltip(
                  message: isOnline ? 'Online' : 'Offline',
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      isOnline ? Icons.cloud_done : Icons.cloud_off,
                      key: ValueKey(isOnline),
                      color: isOnline
                          ? Colors.lightBlueAccent
                          : Colors.grey.shade500,
                      size: 28,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Colors.blueGrey,
            secondary: Colors.blueGrey.shade300,
          ),
        ),
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < 3) {
              setState(() => _currentStep++);
            } else {
              print('Attempting to submit data...');
              _submitData();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            }
          },
          steps: [
            Step(
              title: Text('Výběr náboje'),
              content: CartridgeSelectionWidget(
                onCartridgeSelected: (cartridgeId, caliberId) {
                  setState(() {
                    selectedCartridgeId = cartridgeId;
                    selectedCaliberId = caliberId;
                  });
                },
              ),
              isActive: _currentStep >= 0,
            ),
            Step(
              title: Text('Výběr zbraně'),
              content: WeaponSelectionWidget(
                caliberId: selectedCaliberId,
                onWeaponSelected: (id) => setState(() => selectedWeaponId = id),
              ),
              isActive: _currentStep >= 1,
            ),
            Step(
              title: Text('Fotografie'),
              content: Column(
                children: [
                  if (targetImage != null)
                    Image.file(targetImage!, height: 200)
                  else
                    ElevatedButton(
                      onPressed: _takePhoto,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      child: const Text(
                        'Vyfotit terč',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              isActive: _currentStep >= 2,
            ),
            Step(
              title: Text('Doplňující údaje'),
              content: Column(
                children: [
                  TextField(
                    controller: distanceController,
                    decoration: InputDecoration(
                      labelText: 'Vzdálenost (m)',
                      border: OutlineInputBorder(),
                      suffixText: 'm',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: 'Poznámka',
                      border: OutlineInputBorder(),
                      hintText: 'Volitelná poznámka k terči...',
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              isActive: _currentStep >= 3,
            ),
          ],
        ),
      ),
    );
  }
}
