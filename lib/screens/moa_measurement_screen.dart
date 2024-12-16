import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
import 'package:vector_math/vector_math_64.dart' as vector;

enum EditMode { calibration, shots, none }

class Group {
  final List<Offset> points;
  final double moaValue;
  final Rect boundingBox;

  Group({
    required this.points,
    required this.moaValue,
    required this.boundingBox,
  });

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'moa': moaValue,
        'bounding_box': {
          'left': boundingBox.left,
          'top': boundingBox.top,
          'width': boundingBox.width,
          'height': boundingBox.height,
        }
      };
}

class MoaMeasurementData {
  final String originalImagePath;
  final List<Group> groups;
  final List<Offset> calibrationPoints;
  final double calibrationValue; // mm

  MoaMeasurementData({
    required this.originalImagePath,
    required this.groups,
    required this.calibrationPoints,
    required this.calibrationValue,
  });

  Map<String, dynamic> toJson() => {
        'image': originalImagePath,
        'groups': groups.map((g) => g.toJson()).toList(),
        'calibration': {
          'points':
              calibrationPoints.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
          'value_mm': calibrationValue
        }
      };
}

class MoaPainter extends CustomPainter {
  final List<List<Offset>> shotGroups;
  final int currentGroupIndex;
  final List<Offset> calibrationPoints;
  final Map<int, GroupStats> groupStats;
  final Offset? selectedPoint;
  final bool hideCalibration;
  final bool showStats;
  final Size displaySize;
  final bool isExport;

  const MoaPainter({
    required this.shotGroups,
    required this.currentGroupIndex,
    required this.calibrationPoints,
    required this.groupStats,
    required this.showStats,
    required this.displaySize,
    this.selectedPoint,
    this.hideCalibration = false,
    this.isExport = false,
  });

  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Calculate scale factor for export
    final exportScaleFactor = isExport ? (size.width / displaySize.width) : 1.0;
    final fontSize = (isExport ? 24.0 : 6.0) * exportScaleFactor;
    final strokeWidth =
        (isExport ? 2.0 : 1.0) * exportScaleFactor; // Zmenšeno z 4.0
    final circleRadius =
        (isExport ? 4.0 : 2.0) * exportScaleFactor; // Zmenšeno z 8.0
    final padding = (isExport ? 8.0 : 2.0) * exportScaleFactor;

    // Add this block BEFORE the shotGroups loop
    if (!hideCalibration && calibrationPoints.isNotEmpty) {
      final calibrationPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = strokeWidth; // Odstraněno * 2

      // Draw line between points if we have both
      if (calibrationPoints.length == 2) {
        canvas.drawLine(
          calibrationPoints[0],
          calibrationPoints[1],
          calibrationPaint..style = PaintingStyle.stroke,
        );
      }

      // Draw points
      for (var point in calibrationPoints) {
        canvas.drawCircle(
          point,
          circleRadius * 2,
          calibrationPaint..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(
          point,
          circleRadius, // Zmenšeno z 2
          calibrationPaint..style = PaintingStyle.fill,
        );
      }
    }

    for (int i = 0; i < shotGroups.length; i++) {
      final isCurrentGroup = i == currentGroupIndex;
      final shots = shotGroups[i];

      if (!isCurrentGroup && groupStats.containsKey(i) && showStats) {
        final stats = groupStats[i]!;

        // Draw bounding box
        canvas.drawRect(
            stats.boundingBox,
            Paint()
              ..color = Colors.blue.withOpacity(0.15)
              ..style = PaintingStyle.fill);

        canvas.drawRect(
            stats.boundingBox,
            Paint()
              ..color = Colors.blue.withOpacity(0.5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth);

        // Draw statistics
        textPainter.text = TextSpan(
          text: 'G${i + 1}: ${stats.maxMoa.toStringAsFixed(2)} MOA',
          style: TextStyle(
            color: Colors.black87,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        );

        textPainter.layout(maxWidth: size.width);
        final textSize = textPainter.size;

        // White background for text
        canvas.drawRect(
          Rect.fromLTWH(
            stats.boundingBox.left,
            stats.boundingBox.bottom + padding,
            textSize.width + padding * 2,
            textSize.height + padding,
          ),
          Paint()
            ..color = Colors.white.withOpacity(0.9)
            ..style = PaintingStyle.fill,
        );

        textPainter.paint(
          canvas,
          Offset(
            stats.boundingBox.left + padding,
            stats.boundingBox.bottom + padding,
          ),
        );
      }

      // Draw shots
      final shotPaint = Paint()
        ..color = isCurrentGroup ? Colors.red : Colors.orange
        ..strokeWidth = strokeWidth;

      for (int j = 0; j < shots.length; j++) {
        final shot = shots[j];
        final isSelected = shot == selectedPoint;

        if (isSelected) {
          canvas.drawCircle(
            shot,
            circleRadius * 4,
            Paint()
              ..color = Colors.yellow.withOpacity(0.3)
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(
            shot,
            circleRadius * 2.5,
            Paint()
              ..color = Colors.blue
              ..strokeWidth = strokeWidth
              ..style = PaintingStyle.stroke,
          );
        }

        canvas.drawCircle(
            shot, circleRadius, shotPaint..style = PaintingStyle.fill);

        // Shot number
        textPainter.text = TextSpan(
          text: '${j + 1}',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize * 1.2,
            fontWeight: FontWeight.w500,
          ),
        );
        textPainter.layout();
        textPainter.paint(
            canvas, Offset(shot.dx + padding * 3, shot.dy - padding * 3));
      }
    }
  }

  @override
  bool shouldRepaint(MoaPainter oldDelegate) {
    return shotGroups != oldDelegate.shotGroups ||
        currentGroupIndex != oldDelegate.currentGroupIndex ||
        calibrationPoints != oldDelegate.calibrationPoints ||
        selectedPoint != oldDelegate.selectedPoint ||
        hideCalibration != oldDelegate.hideCalibration ||
        groupStats != oldDelegate.groupStats;
  }
}

class MoaMeasurementScreen extends StatefulWidget {
  final File imageFile;

  const MoaMeasurementScreen({
    Key? key,
    required this.imageFile,
  }) : super(key: key);

  @override
  _MoaMeasurementScreenState createState() => _MoaMeasurementScreenState();
}

class GroupStats {
  final double minMoa;
  final double maxMoa;
  final double avgMoa;
  final Rect boundingBox;

  GroupStats({
    required this.minMoa,
    required this.maxMoa,
    required this.avgMoa,
    required this.boundingBox,
  });
}

class _MoaMeasurementScreenState extends State<MoaMeasurementScreen> {
  List<Offset> _shots = [];
  List<Offset> _calibrationPoints = [];
  Offset? _selectedPoint;
  bool _calibrationComplete = false;
  double? _moaValue;
  EditMode _currentMode = EditMode.calibration;
  final TextEditingController calibrationController =
      TextEditingController(text: '25.4'); // 1 inch default
  final TextEditingController distanceController = TextEditingController();
  bool _isMovingCalibrationPoint = false;
  bool _editingMode = false;
  bool _isEditMode = false;
  final TransformationController _transformationController =
      TransformationController();
  bool _showDistanceInput = true;
  List<List<Offset>> _shotGroups = [[]]; // Seznam skupin zásahů
  int _currentGroupIndex = 0; // Aktuální skupina
  Map<int, double> _moaValues = {};
  List<List<List<Offset>>> _undoHistory = []; // History of shot groups
  List<List<List<Offset>>> _redoHistory = []; // Redo stack
  static const int maxHistoryLength = 20; // Limit history size
  Map<int, GroupStats> _groupStats = {};
  bool _showGroupStats = true;
  final GlobalKey _imageKey = GlobalKey();

  @override
  void dispose() {
    _transformationController.dispose();
    calibrationController.dispose();
    distanceController.dispose();
    super.dispose();
  }

  void _handleZoomIn() {
    final double currentScale =
        _transformationController.value.getMaxScaleOnAxis();
    if (currentScale < 5.0) {
      // Get the center of the screen
      final size = context.size!;
      final center = Offset(size.width / 2, size.height / 2);

      // Create matrix that keeps the center point
      final matrix = Matrix4.identity()
        ..translate(center.dx, center.dy)
        ..scale(currentScale + 0.5)
        ..translate(-center.dx, -center.dy);

      _transformationController.value = matrix;
    }
  }

  void _handleZoomOut() {
    final double currentScale =
        _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.0) {
      // Min zoom limit
      _transformationController.value = Matrix4.identity()
        ..scale(currentScale - 0.5);
    }
  }

  Future<void> _saveAnnotatedImage() async {
    try {
      final data = await _getMeasurementData();
      Navigator.pop(context, data);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save measurement: $e')),
      );
    }
  }

  Future<File> _createAnnotatedImage() async {
    // Load image
    final imageBytes = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // Get actual rendered image dimensions
    final RenderBox renderBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox;
    final Size displaySize = renderBox.size;

    // Calculate viewport-relative position
    final Offset position = renderBox.localToGlobal(Offset.zero);
    final Rect viewport =
        Rect.fromLTWH(0, 0, displaySize.width, displaySize.height);

    // Get image dimensions
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    // Calculate scale maintaining aspect ratio
    final fitScale = min(displaySize.width / imageSize.width,
        displaySize.height / imageSize.height);

    // Calculate centered position
    final scaledWidth = imageSize.width * fitScale;
    final scaledHeight = imageSize.height * fitScale;
    final offsetX = (displaySize.width - scaledWidth) / 2;
    final offsetY = (displaySize.height - scaledHeight) / 2;

    // Debug prints
    print('Image size: $imageSize');
    print('Display size: $displaySize');
    print('Viewport: $viewport');
    print('Scale: $fitScale');
    print('Offsets: ($offsetX, $offsetY)');

    // Updated transform
    Offset transformToImage(Offset displayPoint) {
      if (fitScale <= 0) {
        throw Exception('Invalid scale factor: $fitScale');
      }

      // Transform relative to viewport
      final viewportX = displayPoint.dx - offsetX;
      final viewportY = displayPoint.dy - offsetY;

      // Scale to image coordinates
      final imageX = (viewportX / fitScale).clamp(0.0, imageSize.width);
      final imageY = (viewportY / fitScale).clamp(0.0, imageSize.height);

      return Offset(imageX, imageY);
    }

    // Rest of the method remains the same...
    final transformedGroups = _shotGroups
        .map((group) => group.map(transformToImage).toList())
        .toList();

    final transformedCalibration =
        _calibrationPoints.map(transformToImage).toList();

    // Create stats with preserved MOA values
    final recalculatedStats = <int, GroupStats>{};
    for (var i = 0; i < transformedGroups.length; i++) {
      final shots = transformedGroups[i];
      if (shots.isEmpty) continue;

      // Calculate bounds
      final bounds =
          shots.reduce((a, b) => Offset(min(a.dx, b.dx), min(a.dy, b.dy)));
      final maxBounds =
          shots.reduce((a, b) => Offset(max(a.dx, b.dx), max(a.dy, b.dy)));

      // Create bounding box with padding
      const padding = 10.0;
      final boundingBox = Rect.fromLTRB(bounds.dx - padding,
          bounds.dy - padding, maxBounds.dx + padding, maxBounds.dy + padding);

      // Preserve original MOA values
      final originalStats = _groupStats[i];
      recalculatedStats[i] = GroupStats(
        minMoa: originalStats?.minMoa ?? 0.0,
        maxMoa: originalStats?.maxMoa ?? 0.0,
        avgMoa: originalStats?.avgMoa ?? 0.0,
        boundingBox: boundingBox,
      );
    }

    // Setup canvas with original image dimensions
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw original image
    canvas.drawImage(image, Offset.zero, Paint());

    // Draw all annotations
    final painter = MoaPainter(
      shotGroups: transformedGroups,
      currentGroupIndex: -1,
      calibrationPoints: transformedCalibration,
      selectedPoint: null,
      hideCalibration: false,
      groupStats: recalculatedStats,
      showStats: true,
      displaySize: imageSize, // Pass image size as display size
      isExport: true,
    );
    painter.paint(canvas, imageSize);

    // Create final image
    final picture = recorder.endRecording();
    final annotatedImage = await picture.toImage(image.width, image.height);
    final pngBytes =
        await annotatedImage.toByteData(format: ui.ImageByteFormat.png);

    // Save to temp file
    final directory = await getTemporaryDirectory();
    final fileName = 'annotated_${DateTime.now().millisecondsSinceEpoch}.png';
    final annotatedFile = File('${directory.path}/$fileName');
    await annotatedFile.writeAsBytes(pngBytes!.buffer.asUint8List());

    return annotatedFile;
  }

  Future<MoaMeasurementData> _getMeasurementData() async {
    final annotatedImage = await _createAnnotatedImage();

    final groups = _shotGroups.asMap().entries.map((entry) {
      final index = entry.key;
      return Group(
        points: List<Offset>.from(entry.value),
        moaValue: _moaValues[index] ?? 0.0,
        boundingBox: _groupStats[index]?.boundingBox ?? Rect.zero,
      );
    }).toList();

    return MoaMeasurementData(
      originalImagePath: annotatedImage.path, // Use annotated image path
      groups: groups,
      calibrationPoints: List<Offset>.from(_calibrationPoints),
      calibrationValue: double.parse(calibrationController.text),
    );
  }

  void _saveToHistory() {
    _undoHistory
        .add(_shotGroups.map((group) => List<Offset>.from(group)).toList());
    if (_undoHistory.length > maxHistoryLength) {
      _undoHistory.removeAt(0);
    }
    _redoHistory.clear(); // Clear redo stack when new action is performed
  }

  void _undo() {
    if (_undoHistory.isEmpty) return;

    // Save current state to redo stack
    _redoHistory
        .add(_shotGroups.map((group) => List<Offset>.from(group)).toList());

    setState(() {
      _shotGroups =
          _undoHistory.last.map((group) => List<Offset>.from(group)).toList();
      _undoHistory.removeLast();

      // Ensure current group index is valid
      _currentGroupIndex = min(_currentGroupIndex, _shotGroups.length - 1);

      if (distanceController.text.isNotEmpty) {
        _updateMoaCalculation(distanceController.text);
      }
    });
  }

  void _redo() {
    if (_redoHistory.isEmpty) return;

    // Save current state to undo stack
    _undoHistory
        .add(_shotGroups.map((group) => List<Offset>.from(group)).toList());

    // Restore next state
    setState(() {
      _shotGroups =
          _redoHistory.last.map((group) => List<Offset>.from(group)).toList();
      _redoHistory.removeLast();

      // Update MOA calculation
      if (distanceController.text.isNotEmpty) {
        _updateMoaCalculation(distanceController.text);
      }
    });
  }

  void _deleteSelectedPoint() {
    if (_selectedPoint == null || !_isEditMode) return;

    _saveToHistory(); // Save state before deletion
    setState(() {
      if (_isMovingCalibrationPoint) {
        _calibrationPoints.remove(_selectedPoint);
      } else {
        _shotGroups[_currentGroupIndex].remove(_selectedPoint);
        if (_shotGroups[_currentGroupIndex].isNotEmpty &&
            distanceController.text.isNotEmpty) {
          _updateMoaCalculation(distanceController.text);
        } else {
          _moaValues.remove(_currentGroupIndex);
        }
      }
      _selectedPoint = null;
    });
  }

  void _handleTap(TapDownDetails details) {
    setState(() {
      switch (_currentMode) {
        case EditMode.calibration:
          if (_calibrationPoints.length < 2) {
            _saveToHistory(); // Save state before adding point
            _calibrationPoints.add(details.localPosition);
            if (_calibrationPoints.length == 2) {
              _calibrationComplete = true;
              _currentMode = EditMode.shots;
              if (distanceController.text.isNotEmpty) {
                _updateMoaCalculation(distanceController.text);
                setState(() => _showDistanceInput = false);
              }
            }
          }
          break;

        case EditMode.shots:
          _saveToHistory(); // Save state before adding shot
          _shotGroups[_currentGroupIndex].add(details.localPosition);
          if (distanceController.text.isNotEmpty) {
            _updateMoaCalculation(distanceController.text);
            _moaValues[_currentGroupIndex] = _moaValue ?? 0.0;
          }
          break;

        case EditMode.none:
          break;
      }
    });
  }

  void _handlePanStart(DragStartDetails details) {
    final pos = details.localPosition;

    // In edit mode, only allow moving selected point
    if (_isEditMode && _selectedPoint != null) {
      final distance = (_selectedPoint! - pos).distance;
      if (distance < 20) {
        // Detection radius
        _isMovingCalibrationPoint = _calibrationPoints.contains(_selectedPoint);
        return; // Allow dragging only if near selected point
      }
      return; // If not near selected point, do nothing
    }

    // Normal calibration point selection logic remains for non-edit mode
    double minDistance = double.infinity;
    Offset? closest;
    bool isCalibrationPoint = false;

    for (var point in _calibrationPoints) {
      final distance = (point - pos).distance;
      if (distance < minDistance && distance < 20) {
        minDistance = distance;
        closest = point;
        isCalibrationPoint = true;
      }
    }

    if (closest == null) {
      for (var shot in _shotGroups[_currentGroupIndex]) {
        final distance = (shot - pos).distance;
        if (distance < minDistance && distance < 20) {
          minDistance = distance;
          closest = shot;
        }
      }
    }

    setState(() {
      if (closest != null) {
        HapticFeedback.lightImpact(); // Light feedback when starting to drag
        _selectedPoint = closest;
        _isMovingCalibrationPoint = isCalibrationPoint;
      }
    });
  }

// Fix _handlePanUpdate for shot groups
  void _handlePanUpdate(DragUpdateDetails details) {
    if (_selectedPoint != null) {
      setState(() {
        if (_isMovingCalibrationPoint) {
          final index = _calibrationPoints.indexOf(_selectedPoint!);
          if (index != -1) {
            _calibrationPoints[index] = details.localPosition;
            _selectedPoint = details.localPosition;
            if (distanceController.text.isNotEmpty) {
              _updateMoaCalculation(distanceController.text);
            }
          }
        } else {
          // Find and update shot in current group
          final currentShots = _shotGroups[_currentGroupIndex];
          final index = currentShots.indexOf(_selectedPoint!);
          if (index != -1) {
            _shotGroups[_currentGroupIndex][index] = details.localPosition;
            _selectedPoint = details.localPosition;
            if (distanceController.text.isNotEmpty) {
              _updateMoaCalculation(distanceController.text);
            }
          }
        }
      });
    }
  }

  void _updateMoaCalculation(String distance) {
    final currentShots = _shotGroups[_currentGroupIndex];

    if (currentShots.isEmpty ||
        _calibrationPoints.length != 2 ||
        calibrationController.text.isEmpty) {
      setState(() {
        _moaValues.remove(_currentGroupIndex);
        _groupStats.remove(_currentGroupIndex);
      });
      return;
    }

    try {
      // Basic calculations
      final distanceMeters = double.parse(distance);
      final distanceYards = distanceMeters * 1.0936;
      final calibrationPixels =
          (_calibrationPoints[1] - _calibrationPoints[0]).distance;
      final calibrationMm = double.parse(calibrationController.text);
      final pixelsPerMm = calibrationPixels / calibrationMm;

      // Group statistics
      double maxDistance = 0;
      double minDistance = double.infinity;
      double sumDistances = 0;
      int pairCount = 0;

      // Find min/max coordinates for bounding box
      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;

      // Calculate distances and bounds
      for (final shot in currentShots) {
        minX = min(minX, shot.dx);
        minY = min(minY, shot.dy);
        maxX = max(maxX, shot.dx);
        maxY = max(maxY, shot.dy);

        for (final otherShot in currentShots) {
          if (shot != otherShot) {
            final dist = (shot - otherShot).distance;
            maxDistance = max(maxDistance, dist);
            minDistance = min(minDistance, dist);
            sumDistances += dist;
            pairCount++;
          }
        }
      }

      // Calculate MOA values
      final avgDistance =
          pairCount > 0 ? (sumDistances / pairCount).toDouble() : 0.0;

      final convertToMoa = (double pixels) {
        final inches = (pixels / pixelsPerMm) / 25.4;
        return (inches * 95.5) / distanceYards;
      };

      final maxMoa = convertToMoa(maxDistance);
      final minMoa = convertToMoa(minDistance);
      final avgMoa = convertToMoa(avgDistance);

      // Create bounding box with padding
      final padding = 10.0;
      final boundingBox = Rect.fromLTRB(
        minX - padding,
        minY - padding,
        maxX + padding,
        maxY + padding,
      );

      setState(() {
        _moaValues[_currentGroupIndex] = maxMoa; // Keep original behavior
        _moaValue = maxMoa; // Backward compatibility

        _groupStats[_currentGroupIndex] = GroupStats(
          maxMoa: maxMoa,
          minMoa: minMoa,
          avgMoa: avgMoa,
          boundingBox: boundingBox,
        );
      });
    } catch (e) {
      setState(() {
        _moaValues.remove(_currentGroupIndex);
        _moaValue = null;
        _groupStats.remove(_currentGroupIndex);
      });
    }
  }

  Widget _buildModeControls() {
    return Positioned(
      top: 16,
      right: 16,
      child: Card(
        color: Colors.white.withOpacity(0.9),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToggleButtons(
                isSelected: [
                  _currentMode == EditMode.calibration,
                  _currentMode == EditMode.shots,
                ],
                onPressed: (index) {
                  setState(() {
                    _currentMode =
                        index == 0 ? EditMode.calibration : EditMode.shots;
                  });
                },
                children: const [
                  Tooltip(
                    message: 'Režim kalibrace',
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.straighten),
                    ),
                  ),
                  Tooltip(
                    message: 'Režim označování zásahů',
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.add_location),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Text(
                _currentMode == EditMode.calibration ? 'Kalibrace' : 'Zásahy',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoaControls() {
    return Card(
      color: Colors.white.withOpacity(0.9),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode selection buttons
            // In the mode selection buttons Row
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.straighten),
                  onPressed: () =>
                      setState(() => _currentMode = EditMode.calibration),
                  color: _currentMode == EditMode.calibration
                      ? Colors.blue
                      : Colors.grey,
                  tooltip: 'Kalibrace vzdálenosti',
                ),
                // Add green check icon when calibration is complete
                if (_calibrationPoints.length == 2)
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 16,
                  ),
                IconButton(
                  icon: const Icon(Icons.add_location),
                  onPressed: () =>
                      setState(() => _currentMode = EditMode.shots),
                  color: _currentMode == EditMode.shots
                      ? Colors.blue
                      : Colors.grey,
                  tooltip: 'Označit zásahy',
                ),
              ],
            ),

            // Group controls
            if (_currentMode == EditMode.shots) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => setState(() {
                      _shotGroups.add([]);
                      _currentGroupIndex = _shotGroups.length - 1;
                    }),
                    tooltip: 'Nová skupina',
                  ),
                  if (_shotGroups.length > 1)
                    DropdownButton<int>(
                      value: _currentGroupIndex,
                      items: _shotGroups.asMap().entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Text('Skupina ${e.key + 1}'),
                        );
                      }).toList(),
                      onChanged: (index) =>
                          setState(() => _currentGroupIndex = index!),
                    ),
                ],
              ),
            ],

            // Current group info
            if (_shotGroups[_currentGroupIndex].isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Skupina ${_currentGroupIndex + 1}:'),
              Text('Počet zásahů: ${_shotGroups[_currentGroupIndex].length}'),
              if (_moaValues.containsKey(_currentGroupIndex))
                Text(
                  'MOA: ${_moaValues[_currentGroupIndex]!.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
            ],

            TextButton(
              onPressed: () => setState(() {
                _shotGroups = [[]];
                _currentGroupIndex = 0;
                _moaValues.clear();
                _calibrationPoints.clear();
                _currentMode = EditMode.calibration;
              }),
              child: Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevent keyboard shift
      appBar: AppBar(
        title: const Text('MOA Měření'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _undoHistory.isEmpty ? null : _undo,
            tooltip: 'Zpět',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _redoHistory.isEmpty ? null : _redo,
            tooltip: 'Vpřed',
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _moaValue != null
                ? () async {
                    final data = await _getMeasurementData();
                    Navigator.pop(context, data);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAnnotatedImage,
            tooltip: 'Uložit s anotacemi',
          ),
        ],
      ),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Odečteme výšku spodního baru
              final bottomBarHeight = _showDistanceInput ? 80.0 : 0.0;
              final displaySize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight -
                      bottomBarHeight // Zde odečteme výšku spodního baru
                  );

              return Stack(
                children: [
                  // Image and interaction layer with zoom
                  InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 5.0,
                    boundaryMargin: const EdgeInsets.all(0),
                    constrained: true,
                    clipBehavior: Clip.none,
                    scaleEnabled: true,
                    panEnabled: true,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          widget.imageFile,
                          key: _imageKey, // Přidáme GlobalKey
                          fit: BoxFit.contain,
                        ),
                        Positioned.fill(
                          child: GestureDetector(
                            onTapDown: !_isEditMode ? _handleTap : null,
                            onPanStart: _isEditMode ? _handlePanStart : null,
                            onPanUpdate: _isEditMode ? _handlePanUpdate : null,
                            onPanEnd: _isEditMode
                                ? (_) => setState(() => _selectedPoint = null)
                                : null,
                            child: CustomPaint(
                              painter: MoaPainter(
                                shotGroups: _shotGroups,
                                currentGroupIndex: _currentGroupIndex,
                                calibrationPoints: _calibrationPoints,
                                selectedPoint: _selectedPoint,
                                hideCalibration: false,
                                groupStats: _groupStats,
                                showStats: _showGroupStats,
                                displaySize: displaySize, // Pass actual size
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          // Mode selection controls
          Positioned(
            top: 16,
            right: 16,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  // Změna z Row na Column
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      // Původní tlačítka v Row
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_circle),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isEditMode = false);
                          },
                          color: !_isEditMode ? Colors.blue : Colors.grey,
                          tooltip: 'Přidat vstřely',
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isEditMode = true);
                          },
                          color: _isEditMode ? Colors.blue : Colors.grey,
                          tooltip: 'Upravit vstřely',
                        ),
                        IconButton(
                          icon: Icon(_showGroupStats
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() => _showGroupStats = !_showGroupStats);
                          },
                          color: _showGroupStats ? Colors.blue : Colors.grey,
                          tooltip: 'Zobrazit/skrýt statistiky',
                        ),
                      ],
                    ),
                    // Přidaný dropdown pro body v edit módu
                    if (_isEditMode &&
                        _shotGroups[_currentGroupIndex].isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButton<int>(
                            hint: const Text('Vybrat bod'),
                            value: _selectedPoint != null
                                ? _shotGroups[_currentGroupIndex]
                                    .indexOf(_selectedPoint!)
                                : null,
                            items: List.generate(
                              _shotGroups[_currentGroupIndex].length,
                              (index) => DropdownMenuItem(
                                value: index,
                                child: Text('Bod ${index + 1}'),
                              ),
                            ),
                            onChanged: (index) {
                              if (index != null) {
                                HapticFeedback
                                    .selectionClick(); // Add tactile feedback
                                setState(() {
                                  _selectedPoint =
                                      _shotGroups[_currentGroupIndex][index];
                                });
                              }
                            },
                          ),
                          if (_selectedPoint != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                HapticFeedback
                                    .mediumImpact(); // Stronger feedback for deletion
                                _deleteSelectedPoint();
                              },
                              color: Colors.red,
                              tooltip: 'Smazat bod',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Zoom controls
          Positioned(
            bottom: 80,
            right: 16,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.zoom_in),
                    onPressed: _handleZoomIn,
                    tooltip: 'Přiblížit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_out),
                    onPressed: _handleZoomOut,
                    tooltip: 'Oddálit',
                  ),
                ],
              ),
            ),
          ),

          // Calibration instructions
          if (_currentMode == EditMode.calibration)
            Positioned(
              top: 120,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.white.withOpacity(0.9),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.straighten, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Kalibrace měření',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: calibrationController,
                        decoration: const InputDecoration(
                          labelText: 'Zadejte referenční vzdálenost v mm',
                          helperText:
                              'Označte 2 body na terči (např. 1 inch = 25.4 mm)',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) =>
                            _updateMoaCalculation(distanceController.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // MOA controls
          Positioned(
            top: 16,
            left: 16,
            child: _buildMoaControls(),
          ),

          // Animated distance input
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            bottom: _showDistanceInput ? 16 : -80,
            left: 16,
            right: 80, // Leave space for FAB
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: distanceController,
                        decoration: const InputDecoration(
                          labelText: 'Vzdálenost k terči (m)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: _updateMoaCalculation,
                        onSubmitted: (_) {
                          if (distanceController.text.isNotEmpty) {
                            setState(() => _showDistanceInput = false);
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () {
                        if (distanceController.text.isNotEmpty) {
                          setState(() => _showDistanceInput = false);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // FAB for showing distance input
          Positioned(
            bottom:
                _showDistanceInput ? 24 : 16, // Move up when input is visible
            right: 16,
            child: FloatingActionButton(
              mini: true,
              onPressed: () =>
                  setState(() => _showDistanceInput = !_showDistanceInput),
              child: Icon(_showDistanceInput ? Icons.close : Icons.straighten),
              tooltip: 'Vzdálenost k terči',
            ),
          ),
        ],
      ),
    );
  }
}
