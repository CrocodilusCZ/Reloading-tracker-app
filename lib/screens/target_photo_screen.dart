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
import 'package:shooting_companion/screens/moa_measurement_screen.dart';

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
  double? _moaValue;
  int? _shotCount;
  MoaMeasurementData? _moaMeasurementData;

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
        print('DEBUG: Saving offline request with photoId: $photoId');

        // Prepare request data including MOA if available
        var requestJsonData = {
          'photo_id': photoId,
          'photo_path': targetImage!.path,
          'notes': notesController.text,
          'distance': distanceController.text,
          'weapon_id': selectedWeaponId,
          'cartridge_id': selectedCartridgeId,
        };

        // Add complete MOA measurement data if available
        if (_moaMeasurementData != null) {
          requestJsonData['moa_data'] = _moaMeasurementData!.toJson();
        } else if (_moaValue != null) {
          // Fallback to simple MOA value
          requestJsonData['moa_value'] = _moaValue;
          requestJsonData['shot_count'] = _shotCount;
        }

        // Create final request structure
        final requestData = {
          'request_type': 'upload_target_photo',
          'data': jsonEncode(requestJsonData),
          'status': 'pending',
        };

        print('DEBUG: Request data: $requestData');

        // Save to database
        await dbHelper.insertOfflineRequest(requestData);
        print('DEBUG: Offline request saved successfully');

        // Navigate back and show confirmation
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Terč byl uložen lokálně a bude synchronizován později'),
          ),
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
        if (_moaMeasurementData != null) {
          request.files.add(
            await http.MultipartFile.fromPath(
                'image', _moaMeasurementData!.originalImagePath),
          );
        } else {
          request.files.add(
            await http.MultipartFile.fromPath('image', targetImage!.path),
          );
        }

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
        if (_moaMeasurementData != null) {
          request.fields['moa_data'] =
              jsonEncode(_moaMeasurementData!.toJson());
        } else if (_moaValue != null) {
          request.fields['moa_value'] = _moaValue.toString();
          request.fields['shot_count'] = _shotCount.toString();
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
              title: Text('MOA Měření'),
              content: Column(
                children: [
                  if (targetImage != null)
                    ElevatedButton(
                      onPressed: () async {
                        final MoaMeasurementData? result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MoaMeasurementScreen(
                              imageFile: targetImage!,
                            ),
                          ),
                        );

                        if (result != null) {
                          setState(() {
                            _moaMeasurementData = result;
                            // Keep simple values for compatibility
                            if (result.groups.isNotEmpty) {
                              _moaValue = result.groups[0].moaValue;
                              _shotCount = result.groups[0].points.length;
                            }
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        padding:
                            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: Text(
                        'Měřit MOA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (_moaMeasurementData != null) ...[
                    SizedBox(height: 16),
                    ...(_moaMeasurementData!.groups
                        .asMap()
                        .entries
                        .map((entry) {
                      final index = entry.key;
                      final group = entry.value;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Skupina ${index + 1}: ${group.moaValue.toStringAsFixed(2)} MOA',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text('Počet zásahů: ${group.points.length}'),
                          SizedBox(height: 8),
                        ],
                      );
                    })),
                  ],
                ],
              ),
              isActive: _currentStep >= 3,
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
