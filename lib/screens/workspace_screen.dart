import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../components/ar_view_wrapper.dart';
import '../components/glass_container.dart';
import '../theme/app_colors.dart';

class WorkspaceScreen extends StatefulWidget {
  final bool isFirstTimeInWorkspace;
  const WorkspaceScreen({super.key, this.isFirstTimeInWorkspace = false});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late double _opacity = 0.5;
  late bool _isLocked = false;
  late bool _showTutorial = widget.isFirstTimeInWorkspace;
  dynamic _arController;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  
  // Track the current node to update its properties
  dynamic _imageNode;
  bool _isFloating = false;
  bool _hasPlaneFocus = false;
  vector.Matrix4? _imageTransform;
  Timer? _previewTimer;
  double _imageScale = 0.3;
  double _imageRotationZ = 0.0;
  double _baseScale = 0.3;
  double _baseRotation = 0.0;

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  void _onARViewCreated(dynamic controller) {
    setState(() => _arController = controller);
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _imageFile = File(image.path);
          _isFloating = true;
          _isLocked = false;
        });
        _startPreviewTracking();
        _addARImageNode();
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _addARImageNode() {
    if (_arController == null || _imageFile == null) return;

    // Remove existing node
    if (_imageNode != null) {
      if (_arController is ARKitController) {
        _arController.remove('drawing_node');
      } else if (_arController is ArCoreController) {
        // ArCore node removal
      }
    }

    if (_arController is ARKitController) {
      // Apply scale and user-rotation on top of surface transform
      final transform = (_imageTransform ?? vector.Matrix4.identity()).clone();
      // Rotate around the Z-axis of the placed plane (feels like rotating the image in-place)
      transform.multiply(vector.Matrix4.rotationZ(_imageRotationZ));

      _imageNode = ARKitNode(
        name: 'drawing_node',
        geometry: ARKitPlane(
          width: _imageScale,
          height: _imageScale,
          materials: [
            ARKitMaterial(
              diffuse: ARKitMaterialProperty.image(_imageFile!.path),
              doubleSided: true,
              transparency: _isFloating ? 0.3 : _opacity,
            ),
          ],
        ),
        transformation: transform,
      );
      _arController.add(_imageNode);
    } else if (_arController is ArCoreController) {
      _imageNode = ArCoreNode(
        image: ArCoreImage(
          bytes: _imageFile!.readAsBytesSync(),
          width: 400,
          height: 400,
        ),
        position: _imageTransform?.getTranslation() ?? vector.Vector3(0, -0.1, -0.4),
      );
      (_arController as ArCoreController).addArCoreNode(_imageNode);
    }
  }

  void _removeARImageNode() {
    if (_imageNode != null && _arController != null) {
      if (_arController is ARKitController) {
        _arController.remove('drawing_node');
      }
      _imageNode = null;
    }
  }

  void _handleTap() {
    if (_isFloating) {
      if (!_hasPlaneFocus) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please aim at a detected surface first.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      _previewTimer?.cancel();
      setState(() {
        _isFloating = false;
        _isLocked = true;
        _hasPlaneFocus = true; // Lock hides prompt
      });

      // Finalize image node (update transparency and ensure final position)
      _addARImageNode();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Position Fixed! View Locked.'),
          backgroundColor: AppColors.neonBlue,
        ),
      );
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _imageScale;
    _baseRotation = _imageRotationZ;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (!_isFloating) return;
    if (details.pointerCount >= 2) {
      setState(() {
        _imageScale = (_baseScale * details.scale).clamp(0.05, 1.5);
        _imageRotationZ = _baseRotation - details.rotation;
      });
      _addARImageNode();
    }
  }

  void _startPreviewTracking() {
    _previewTimer?.cancel();
    _previewTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _updatePreviewPosition();
    });
  }

  void _updatePreviewPosition() {
    if (!_isFloating || _arController == null) return;

    if (_arController is ARKitController) {
      _arController.performHitTest(x: 0.5, y: 0.5).then((results) {
        // Filter strictly for plane intersections, ignore feature points
        final planeResults = results.where((r) => 
          r.type == ARKitHitTestResultType.existingPlaneUsingExtent || 
          r.type == ARKitHitTestResultType.existingPlane
        ).toList();
        
        if (planeResults.isNotEmpty) {
          final result = planeResults.first;
          final hitPosition = result.worldTransform.getTranslation();

          // ARPlaneDetection.horizontal already ensures only floor/table planes are detected.
          // No ceiling or wall filtering needed at this level.
          final targetTransform = vector.Matrix4.identity();
          targetTransform.setRotation(vector.Matrix3.rotationX(-1.5708));
          // ARKit hit-test Y sits slightly above the physical surface (anchor centroid offset).
          // Subtract 2mm to push the image flush against the actual table.
          targetTransform.setTranslation(vector.Vector3(
            hitPosition.x,
            hitPosition.y - 0.002,
            hitPosition.z,
          ));

          if (!_hasPlaneFocus) setState(() => _hasPlaneFocus = true);

          if (_imageTransform == null || 
              (targetTransform.getTranslation() - _imageTransform!.getTranslation()).length > 0.005) {
            setState(() { _imageTransform = targetTransform; });
            _addARImageNode();
          }
        } else {
          // No plane detected. Hide the image entirely.
          if (_hasPlaneFocus || _imageNode != null) {
            setState(() {
              _hasPlaneFocus = false;
              _imageTransform = null;
            });
            _removeARImageNode();
          }
        }
      });
    }
  }

  void _resetWorkspace() {
    _previewTimer?.cancel();
    if (_arController != null && _imageNode != null) {
      _arController.remove('drawing_node');
    }
    setState(() {
      _imageFile = null;
      _imageNode = null;
      _imageTransform = null;
      _isFloating = false;
      _hasPlaneFocus = false;
      _isLocked = false;
      _opacity = 0.5;
      _imageScale = 0.3;
      _imageRotationZ = 0.0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Workspace Reset')),
    );
  }

  void _updateOpacity(double value) {
    setState(() => _opacity = value);
    
    // Update live node transparency
    if (_imageNode != null && _arController is ARKitController) {
      // Re-add or update logic depending on plugin version
      // For simplicity in this plugin, we re-apply the node with new settings
      _addARImageNode();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // AR Viewport — gestures on top for scale/rotate during preview
          GestureDetector(
            onTap: _handleTap,
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            child: ARViewWrapper(onARViewCreated: _onARViewCreated),
          ),

          // Placement Reticle (Center of screen)
          if (_isFloating)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _hasPlaneFocus ? AppColors.neonBlue : Colors.white54, 
                        width: 2
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.add, 
                        color: _hasPlaneFocus ? AppColors.neonBlue : Colors.white54, 
                        size: 24
                      ),
                    ),
                  ).animate(
                    target: _hasPlaneFocus ? 1 : 0,
                    onPlay: (controller) => controller.repeat(reverse: true)
                  ).scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 800.ms),
                  
                  // Contextual Prompt
                  if (!_hasPlaneFocus)
                    Padding(
                      padding: const EdgeInsets.only(top: 15),
                      child: GlassContainer(
                        borderRadius: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: const Text(
                          'Move phone to find a surface...',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ).animate().fadeIn().slideY(begin: 0.2),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: GlassContainer(
                        borderRadius: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.straighten, color: Colors.white70, size: 14),
                            const SizedBox(width: 5),
                            Text(
                              '${(_imageScale * 100).toStringAsFixed(0)}cm',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.rotate_right, color: Colors.white70, size: 14),
                            const SizedBox(width: 5),
                            Text(
                              '${(_imageRotationZ * 57.3).toStringAsFixed(0)}°',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(),
                    ),
                ],
              ),
            ),
          
          // Right Tools Toolbar (Snapchat Style)
          Positioned(
            top: 60,
            right: 15,
            child: Column(
              children: [
                _buildSideButton(
                  icon: Icons.info_outline,
                  onTap: () => setState(() => _showTutorial = true),
                ),
                if (_imageFile != null) ...[
                  const SizedBox(height: 20),
                  _buildSideButton(
                    icon: Icons.refresh,
                    onTap: _resetWorkspace,
                  ),
                ],
                if (!_isLocked && _imageFile != null)
                  _buildVerticalOpacitySlider()
                else ...[
                  _buildSideButton(
                    icon: Icons.history,
                    onTap: () {}, // Future: History
                  ),
                  const SizedBox(height: 20),
                  _buildSideButton(
                    icon: Icons.settings_outlined,
                    onTap: () {}, // Future: Settings
                  ),
                ],
              ],
            ).animate().fadeIn(duration: 800.ms).slideX(begin: 0.5),
          ),

          // Bottom Navigation (Snapchat Style)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Removed horizontal slider from here
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_imageFile != null)
                        _buildSnapIcon(
                          icon: Icons.opacity,
                          onTap: () {}, // Handled by slider visibility
                          isActive: true,
                        ),
                      
                      // Main Super Button
                      _buildSuperButton(),
                      
                      if (_imageFile != null)
                        _buildSnapIcon(
                          icon: _isLocked ? Icons.lock : Icons.lock_open,
                          onTap: () => setState(() => _isLocked = !_isLocked),
                          isActive: _isLocked,
                          activeColor: AppColors.neonPink,
                        ),
                    ],
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.5),
          ),
          
          // Step-by-Step Info Tutorial Overlay
          if (_showTutorial) _buildTutorialOverlay(),
        ],
      ),
    );
  }

  Widget _buildSideButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(10),
        borderRadius: 50,
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildSnapIcon({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
    Color? activeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black26,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30, width: 1.5),
        ),
        child: Icon(
          icon,
          color: isActive ? (activeColor ?? AppColors.neonBlue) : Colors.white,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildSuperButton() {
    return GestureDetector(
      onTap: _isFloating ? _handleTap : _pickImage,
      child: Container(
        width: 85,
        height: 85,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 5),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isFloating 
                ? (_hasPlaneFocus ? AppColors.neonBlue : Colors.grey[800]) 
                : Colors.white24,
            boxShadow: [
              if (_isFloating && _hasPlaneFocus)
                BoxShadow(
                  color: AppColors.neonBlue.withValues(alpha: 0.5),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Icon(
            _isFloating ? Icons.check : Icons.photo_library,
            color: _isFloating ? Colors.black : Colors.white,
            size: 38,
          ),
        ),
      ).animate(target: _isFloating ? 1 : 0)
       .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), curve: Curves.elasticOut),
    );
  }

  Widget _buildTutorialOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: GlassContainer(
            borderRadius: 30,
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'AR Studio Guide',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.neonBlue,
                  ),
                ),
                const SizedBox(height: 25),
                _buildTutorialStep(Icons.touch_app, 'Tap on any surface to place your sketch once it is detected.'),
                const SizedBox(height: 20),
                _buildTutorialStep(Icons.opacity, 'Use the slider to blend the sketch with your paper.'),
                const SizedBox(height: 20),
                _buildTutorialStep(Icons.lock, 'Lock your view to freeze the sketch in place while you draw.'),
                const SizedBox(height: 40),
                GestureDetector(
                  onTap: () => setState(() => _showTutorial = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Text('Start Creating', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
        ),
      ),
    );
  }

  Widget _buildVerticalOpacitySlider() {
    return Column(
      children: [
        const Icon(Icons.opacity, color: Colors.white, size: 20),
        const SizedBox(height: 10),
        SizedBox(
          width: 44,
          height: 150,
          child: GlassContainer(
            borderRadius: 30,
            child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                activeTrackColor: AppColors.neonBlue,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: _opacity,
                onChanged: _updateOpacity,
              ),
            ),
          ),
        ),
      ),
      ],
    ).animate().fadeIn().slideX(begin: 0.2);
  }

  Widget _buildTutorialStep(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.neonBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.neonBlue, size: 24),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
        ),
      ],
    );
  }
}
