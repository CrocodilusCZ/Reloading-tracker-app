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
import 'dart:math' show pi;
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';

class TargetPhotoScreen extends StatefulWidget {
  final Function()? onTargetAdded;

  const TargetPhotoScreen({
    Key? key,
    this.onTargetAdded,
  }) : super(key: key);

  @override
  _TargetPhotoScreenState createState() => _TargetPhotoScreenState();
}

class _TargetPhotoScreenState extends State<TargetPhotoScreen> {
  int _currentStep = 0;
  String? selectedCartridgeId;
  String? selectedCaliberId;
  String? selectedWeaponId;
  String? selectedCartridgeName;
  String? selectedWeaponName;
  File? targetImage;
  final TextEditingController distanceController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final ConnectivityHelper _connectivityHelper = ConnectivityHelper();
  double? _moaValue;
  int? _shotCount;
  MoaMeasurementData? _moaMeasurementData;
  double _imageRotation = 0;

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
      // Get rotated image first
      final File rotatedImage = await _saveRotatedImage();

      // 2. Vytvoření požadavku a lokální uložení
      final photo = TargetPhotoRequest(
        id: 0,
        photoPath: rotatedImage.path,
        note: notesController.text,
        createdAt: DateTime.now(),
        isSynced: false,
        cartridgeId: int.parse(selectedCartridgeId!),
      );

      final DatabaseHelper dbHelper = DatabaseHelper();
      final photoId = await dbHelper.insertTargetPhoto(photo);
      print('DEBUG: Photo saved locally with ID: $photoId');

      // 3. Kontrola připojení
      final connectivityHelper = ConnectivityHelper();
      final hasInternet = await connectivityHelper.hasInternetConnection();
      print('DEBUG: Checking actual internet connectivity...');
      print('DEBUG: Internet connection status: $hasInternet');

      if (!hasInternet) {
        String imagePath;
        if (_moaMeasurementData != null) {
          // Ensure we use permanent storage
          final directory = await getApplicationDocumentsDirectory();
          final fileName =
              'annotated_${DateTime.now().millisecondsSinceEpoch}.png';
          final permanentPath = '${directory.path}/$fileName';

          // Debug logging
          print(
              'Copying annotated image from: ${_moaMeasurementData!.originalImagePath}');
          print('To permanent location: $permanentPath');

          // Check if source exists
          if (!await File(_moaMeasurementData!.originalImagePath).exists()) {
            print('ERROR: Source annotated image does not exist!');
            throw Exception('Annotated image not found');
          }

          // Copy with verification
          final File newFile =
              await File(_moaMeasurementData!.originalImagePath)
                  .copy(permanentPath);

          if (!await newFile.exists()) {
            print('ERROR: Failed to copy annotated image!');
            throw Exception('Failed to save annotated image');
          }

          imagePath = permanentPath;
          print('Successfully saved annotated image to permanent storage');
        } else {
          imagePath = rotatedImage.path;
        }

        var requestJsonData = {
          'photo_id': photoId,
          'photo_path': imagePath, // Použijeme cestu k anotovanému obrázku
          'notes': notesController.text,
          'distance': distanceController.text,
          'weapon_id': selectedWeaponId,
          'cartridge_id': selectedCartridgeId,
        };

        // Zbytek kódu zůstává stejný
        if (_moaMeasurementData != null) {
          requestJsonData['moa_data'] = _moaMeasurementData!.toJson();
        } else if (_moaValue != null) {
          requestJsonData['moa_value'] = _moaValue;
          requestJsonData['shot_count'] = _shotCount;
        }

        final requestData = {
          'request_type': 'upload_target_photo',
          'data': jsonEncode(requestJsonData),
          'status': 'pending',
        };

        await dbHelper.insertOfflineRequest(requestData);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Terč byl uložen lokálně a bude synchronizován později'),
          ),
        );
        return;
      }

      // 4. Online synchronizace
      try {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        String? token = prefs.getString('api_token');
        if (token == null) {
          throw Exception('Authentication token not found');
        }

        var request = http.MultipartRequest(
          'POST',
          Uri.parse(
              '${ApiService.baseUrl}/cartridges/$selectedCartridgeId/targets'),
        );

        request.headers.addAll(
            {'Authorization': 'Bearer $token', 'Accept': 'application/json'});

        // Přidání souboru
        if (_moaMeasurementData != null) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'image',
              _moaMeasurementData!.originalImagePath,
            ),
          );
        } else {
          request.files.add(
            await http.MultipartFile.fromPath('image', rotatedImage.path),
          );
        }

        // Přidání polí
        if (distanceController.text.isNotEmpty) {
          final distance =
              double.parse(distanceController.text).round().toString();
          request.fields['distance'] = distance;
        }

        if (notesController.text.isNotEmpty) {
          request.fields['notes'] = notesController.text;
        }

        if (selectedWeaponId != null) {
          request.fields['weapon_id'] = selectedWeaponId!;
        }

        if (_moaMeasurementData != null) {
          final moaGroups = _moaMeasurementData!.groups
              .map((group) =>
                  {'moa': group.moaValue, 'shot_count': group.points.length})
              .toList();
          request.fields['moa_data'] = jsonEncode({'groups': moaGroups});
        } else if (_moaValue != null) {
          request.fields['moa_data'] = jsonEncode({
            'groups': [
              {'moa': _moaValue, 'shot_count': _shotCount}
            ]
          });
        }

        // Odeslání a zpracování odpovědi
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        print('\n=== API RESPONSE DEBUG ===');
        print('Status code: ${response.statusCode}');
        print('Body: ${response.body}');

        if (response.statusCode == 201) {
          await dbHelper.markPhotoAsSynced(photoId);

          // Add callback here
          widget.onTargetAdded?.call();

          if (!context.mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Terč byl úspěšně uložen a synchronizován')),
          );
        } else {
          final responseData = json.decode(response.body);
          if (responseData['error'] == 'Nedostatek volného místa') {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Nedostatek místa na serveru. Terč byl uložen lokálně.',
                      ),
                    ),
                  ],
                ),
                duration: Duration(seconds: 5),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            throw Exception(
                'Server returned ${response.statusCode}: ${response.body}');
          }
        }
      } catch (e) {
        print('Error syncing with server: $e');
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Terč uložen lokálně a bude synchronizován později'),
          ),
        );
      }
    } catch (e) {
      print('Error in _submitData: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při ukládání: $e')),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
        maxWidth: 1920,
        maxHeight: 1080);

    if (photo != null) {
      setState(() {
        targetImage = File(photo.path);
      });
      print('Selected image size: ${await targetImage!.length()} bytes');
    }
  }

  Future<File> _saveRotatedImage() async {
    if (targetImage == null || _imageRotation == 0) {
      return targetImage!;
    }

    // Načtení původního obrázku
    final imageBytes = await targetImage!.readAsBytes();
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // Vytvoření plátna pro otočený obrázek
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Rotace
    canvas.translate(image.width / 2, image.height / 2);
    canvas.rotate(_imageRotation);
    canvas.translate(-image.width / 2, -image.height / 2);

    // Vykreslení obrázku
    canvas.drawImage(image, Offset.zero, Paint());

    // Vytvoření nového obrázku
    final picture = recorder.endRecording();
    final rotatedImage = await picture.toImage(image.width, image.height);
    final pngBytes =
        await rotatedImage.toByteData(format: ui.ImageByteFormat.png);

    // Uložení do nového souboru
    final directory = await getTemporaryDirectory();
    final fileName = 'rotated_${DateTime.now().millisecondsSinceEpoch}.png';
    final rotatedFile = File('${directory.path}/$fileName');
    await rotatedFile.writeAsBytes(pngBytes!.buffer.asUint8List());

    return rotatedFile;
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
                onCartridgeSelected: (cartridgeId, caliberId, cartridgeName) {
                  setState(() {
                    selectedCartridgeId = cartridgeId;
                    selectedCaliberId = caliberId;
                    selectedCartridgeName =
                        cartridgeName; // Přidat ukládání názvu
                  });
                },
              ),
              isActive: _currentStep >= 0,
            ),
            Step(
              title: Text('Výběr zbraně'),
              content: WeaponSelectionWidget(
                caliberId: selectedCaliberId,
                onWeaponSelected: (id, name) => setState(() {
                  selectedWeaponId = id;
                  selectedWeaponName = name; // Použít název ze zbraně místo ID
                }),
              ),
              isActive: _currentStep >= 1,
            ),
            Step(
              title: Text('Fotografie'),
              content: Column(
                children: [
                  if (targetImage != null) ...[
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.rotate(
                          angle: _imageRotation,
                          child: Image.file(targetImage!, height: 200),
                        ),
                        Positioned(
                          bottom: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.rotate_left,
                                    color: Colors.white),
                                onPressed: () => setState(() {
                                  _imageRotation -= pi / 2;
                                }),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                ),
                              ),
                              SizedBox(width: 8),
                              IconButton(
                                icon: Icon(Icons.rotate_right,
                                    color: Colors.white),
                                onPressed: () => setState(() {
                                  _imageRotation += pi / 2;
                                }),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: TextButton(
                        onPressed: () => setState(() => targetImage = null),
                        child: Text('Zrušit výběr'),
                      ),
                    ),
                  ] else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _takePhoto,
                          icon: Icon(Icons.camera_alt, color: Colors.white),
                          label: Text(
                            'Vyfotit',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            elevation: 3,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _pickFromGallery,
                          icon: Icon(Icons.photo_library, color: Colors.white),
                          label: Text(
                            'Vybrat',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            elevation: 3,
                          ),
                        ),
                      ],
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
                        final rotatedImage = await _saveRotatedImage();
                        final MoaMeasurementData? result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MoaMeasurementScreen(
                              imageFile: rotatedImage, // Already rotated image
                              weaponName: selectedWeaponName,
                              cartridgeName: selectedCartridgeName,
                              distance: distanceController.text.isNotEmpty
                                  ? double.tryParse(distanceController.text)
                                  : null,
                            ),
                          ),
                        );

                        if (result != null) {
                          setState(() {
                            _moaMeasurementData = result;
                            if (result.groups.isNotEmpty) {
                              _moaValue = result.groups[0].moaValue;
                              _shotCount = result.groups[0].points.length;
                            }
                            if (result.distance != null) {
                              distanceController.text =
                                  result.distance.toString();
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
