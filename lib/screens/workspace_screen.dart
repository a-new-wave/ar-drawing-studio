import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
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
  late bool _showOpacitySlider = true;
  late bool _showTutorial = widget.isFirstTimeInWorkspace;
  dynamic _arController;
  File? _imageFile;
  String? _libraryAssetPath;
  String _selectedLibraryCategory = 'All';
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
          _libraryAssetPath = null;
          _isFloating = true;
          _isLocked = false;
          _opacity = 0.5; // Reset to 50% on selection
          _showOpacitySlider = true;
        });
        HapticFeedback.lightImpact();
        _startPreviewTracking();
        _addARImageNode();
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _addARImageNode() {
    if (_arController == null || (_imageFile == null && _libraryAssetPath == null)) return;

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

      final imageProperty = _libraryAssetPath != null 
          ? ARKitMaterialProperty.image(_libraryAssetPath!) 
          : ARKitMaterialProperty.image(_imageFile!.path);

      _imageNode = ARKitNode(
        name: 'drawing_node',
        geometry: ARKitPlane(
          width: _imageScale,
          height: _imageScale,
          materials: [
            ARKitMaterial(
              diffuse: imageProperty,
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
        return;
      }

      _previewTimer?.cancel();
      setState(() {
        _isFloating = false;
        _isLocked = false; // Manual lock only now
        _hasPlaneFocus = true; // Lock hides prompt
      });

      // Finalize image node (update transparency and ensure final position)
      _addARImageNode();

      HapticFeedback.vibrate();
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

          if (!_hasPlaneFocus) {
            setState(() => _hasPlaneFocus = true);
            HapticFeedback.mediumImpact();
          }

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
      if (_arController is ARKitController) {
        _arController.remove('drawing_node');
      }
    }
    setState(() {
      _imageFile = null;
      _libraryAssetPath = null;
      _imageNode = null;
      _imageTransform = null;
      _isFloating = false;
      _hasPlaneFocus = false;
      _isLocked = false;
      _opacity = 0.5;
      _imageScale = 0.3;
      _imageRotationZ = 0.0;
      _showOpacitySlider = true;
    });
    HapticFeedback.heavyImpact();
  }

  void _updateOpacity(double value) {
    if ((_opacity - value).abs() > 0.05) {
      HapticFeedback.selectionClick();
    }
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

          // Placement Reticle (Apple Measure Style)
          if (_isFloating)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _hasPlaneFocus ? AppColors.appleYellow : Colors.white, 
                        width: 2.5
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _hasPlaneFocus ? AppColors.appleYellow : Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ).animate(
                    target: _hasPlaneFocus ? 1 : 0,
                    onPlay: (controller) => controller.repeat(reverse: true)
                  ).scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 1000.ms),
                  
                  // Contextual Prompt
                  if (!_hasPlaneFocus)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Find a surface',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ).animate().fadeIn().slideY(begin: 0.2),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          '${(_imageRotationZ * 57.3).toStringAsFixed(0)}°',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
                if (_imageFile != null || _libraryAssetPath != null) ...[
                  const SizedBox(height: 20),
                  _buildSideButton(
                    icon: Icons.close,
                    onTap: _cancelSelection,
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 20),
                  _buildSideButton(
                    icon: Icons.refresh,
                    onTap: _resetWorkspace,
                  ),
                ],
                ...[
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
                
                if (_imageFile == null && _libraryAssetPath == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildActionPill(
                            label: 'Gallery',
                            icon: Icons.photo_library_outlined,
                            onTap: _pickImage,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildActionPill(
                            label: 'Library',
                            icon: Icons.auto_awesome_motion_outlined,
                            onTap: _showLibraryBottomSheet,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Transparency Button + Vertical Slider Stack
                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.bottomCenter,
                          children: [
                            if (_showOpacitySlider)
                              Positioned(
                                bottom: 80,
                                child: _buildVerticalOpacitySlider(),
                              ),
                            _buildSnapIcon(
                              icon: Icons.opacity,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _showOpacitySlider = !_showOpacitySlider);
                              },
                              isActive: _showOpacitySlider,
                            ),
                          ],
                        ),
                        
                        // Main Super Button (Now only for Placement)
                        _buildSuperButton(),
                        
                        _buildSnapIcon(
                          icon: _isLocked ? Icons.lock : Icons.lock_open,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            setState(() => _isLocked = !_isLocked);
                          },
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

  Widget _buildSideButton({
    required IconData icon,
    required VoidCallback onTap,
    Color backgroundColor = Colors.black38,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
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
          color: Colors.black38,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Icon(
          icon,
          color: isActive ? (activeColor ?? AppColors.appleYellow) : Colors.white,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildSuperButton() {
    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hasPlaneFocus ? AppColors.appleYellow : Colors.grey[900],
          ),
          child: const Icon(
            Icons.check,
            color: Colors.black87,
            size: 32,
          ),
        ),
      ).animate().scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), curve: Curves.elasticOut),
    );
  }

  Widget _buildActionPill({required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black87, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  void _showLibraryBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildLibraryMenu(),
    );
  }

  Widget _buildLibraryMenu() {
    final categories = ['All', 'Anime', 'Architecture', 'Nature', 'Portraits'];
    
    final libraryItems = [
      {'name': 'Anime', 'category': 'Anime', 'asset': 'assets/library/anime.png'},
      {'name': 'Architecture', 'category': 'Architecture', 'asset': 'assets/library/architecture.png'},
      {'name': 'Nature 1', 'category': 'Nature', 'asset': 'assets/library/nature.png'},
      {'name': 'Nature 2', 'category': 'Nature', 'asset': 'assets/library/nature_2.png'},
      {'name': 'Nature 3', 'category': 'Nature', 'asset': 'assets/library/nature_3.png'},
      {'name': 'Nature 4', 'category': 'Nature', 'asset': 'assets/library/nature_4.png'},
      {'name': 'Nature 5', 'category': 'Nature', 'asset': 'assets/library/nature_5.png'},
      {'name': 'Portraits', 'category': 'Portraits', 'asset': 'assets/library/portrait.png'},
      // Repeated for better grid visualization
      {'name': 'Anime Var', 'category': 'Anime', 'asset': 'assets/library/anime.png'},
    ];

    return StatefulBuilder(
      builder: (context, setModalState) {
        final filteredItems = _selectedLibraryCategory == 'All' 
            ? libraryItems 
            : libraryItems.where((item) => item['category'] == _selectedLibraryCategory).toList();

        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Inspiration Library',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 20),
              
              // Category Pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: categories.map((cat) {
                    final isSelected = _selectedLibraryCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setModalState(() {
                            _selectedLibraryCategory = cat;
                          });
                          HapticFeedback.selectionClick();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.appleYellow : Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? AppColors.appleYellow : Colors.white24,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Masonry Grid
              Expanded(
                child: MasonryGridView.count(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _libraryAssetPath = item['asset'];
                          _imageFile = null;
                          _isFloating = true;
                          _isLocked = false;
                          _opacity = 0.5; // Reset to 50% on selection
                        });
                        HapticFeedback.lightImpact();
                        _startPreviewTracking();
                        _addARImageNode(); // Fix: Show preview immediately
                        Navigator.pop(context);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          child: Image.asset(
                            item['asset']!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
                    color: AppColors.appleYellow,
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
                      color: AppColors.appleYellow,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Text(
                      'Start Creating', 
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                    ),
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
                activeTrackColor: AppColors.appleYellow,
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
            color: AppColors.appleYellow.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.appleYellow, size: 24),
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

  void _cancelSelection() {
    _previewTimer?.cancel();
    _removeARImageNode();
    setState(() {
      _imageFile = null;
      _libraryAssetPath = null;
      _isFloating = false;
      _hasPlaneFocus = false;
      _imageTransform = null;
    });
    HapticFeedback.mediumImpact();
  }
}
