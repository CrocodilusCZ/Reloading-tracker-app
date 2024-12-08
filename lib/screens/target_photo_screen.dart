import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:shooting_companion/services/api_service.dart';
import 'package:shooting_companion/widgets/cartridge_selection_widget.dart';
import 'package:shooting_companion/widgets/weapon_selection_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TargetPhotoScreen extends StatefulWidget {
  @override
  _TargetPhotoScreenState createState() => _TargetPhotoScreenState();
}

class _TargetPhotoScreenState extends State<TargetPhotoScreen> {
  int _currentStep = 0;
  String? selectedCartridgeId;
  String? selectedWeaponId;
  File? targetImage;
  final TextEditingController distanceController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  Future<void> _takePhoto() async {
    final ImagePicker picker = ImagePicker();
    // Add imageQuality parameter to reduce file size
    final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50, // Reduces image quality to 50%
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
    print('Starting submit data...');

    // Check required data
    if (targetImage == null) {
      print('No image selected');
      return;
    }
    if (selectedCartridgeId == null) {
      print('No cartridge selected');
      return;
    }

    try {
      // Get token
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('api_token');
      if (token == null) {
        print('No auth token found');
        return;
      }

      // Log file details
      print('Image path: ${targetImage!.path}');
      print('Image size: ${await targetImage!.length()} bytes');
      print('CartridgeId: $selectedCartridgeId');
      print('WeaponId: $selectedWeaponId');
      print('Distance: ${distanceController.text}');
      print('Notes: ${notesController.text}');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
            '${ApiService.baseUrl}/cartridges/$selectedCartridgeId/targets'),
      );

      // Add headers
      request.headers.addAll(
          {'Authorization': 'Bearer $token', 'Accept': 'application/json'});

      print('Adding image to request...');
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          targetImage!.path,
        ),
      );

      // Add other fields
      if (distanceController.text.isNotEmpty) {
        request.fields['distance'] = distanceController.text;
      }
      if (notesController.text.isNotEmpty) {
        request.fields['notes'] = notesController.text;
      }
      if (selectedWeaponId != null) {
        request.fields['weapon_id'] = selectedWeaponId!;
      }

      print('Sending request to: ${request.url}');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 201) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terč byl úspěšně uložen')),
        );
      } else {
        throw Exception(
            'Server returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('Error in _submitData: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba při ukládání: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Fotografie terče')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 3) {
            setState(() => _currentStep++);
          } else {
            print('Attempting to submit data...'); // Debug print
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
              onCartridgeSelected: (id) =>
                  setState(() => selectedCartridgeId = id),
            ),
            isActive: _currentStep >= 0,
          ),
          Step(
            title: Text('Výběr zbraně'),
            content: WeaponSelectionWidget(
              cartridgeId: selectedCartridgeId,
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
                    child: Text('Vyfotit terč'),
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
    );
  }
}
