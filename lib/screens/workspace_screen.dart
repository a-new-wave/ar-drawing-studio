import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'package:torch_light/torch_light.dart';
import '../components/ar_view_wrapper.dart';
import '../components/glass_container.dart';
import '../providers/audio_service.dart';
import '../theme/app_colors.dart';

class WorkspaceScreen extends StatefulWidget {
  final bool isFirstTimeInWorkspace;
  const WorkspaceScreen({super.key, this.isFirstTimeInWorkspace = false});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late double _opacity = 0.7; // 70% visible by default
  late bool _isLocked = false;
  late bool _showOpacitySlider = false; // Hide by default
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
  bool _isTorchOn = false;
  vector.Matrix4? _imageTransform;
  Timer? _previewTimer;
  double _imageScale = 0.3;
  double _imageAspectRatio = 1.0; // Default to square
  double _imageRotationZ = 0.0;
  double _baseScale = 0.3;
  double _baseRotation = 0.0;

  // Recording State
  bool _isRecording = false;
  bool _isProcessingVideo = false;
  Timer? _recordingTimer;
  int _recordingFrameCount = 0;
  String? _recordingDirPath;
  static const _timelapseChannel = MethodChannel('ar_drawing_app/timelapse');

  @override
  void dispose() {
    _previewTimer?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _onARViewCreated(dynamic controller) {
    setState(() => _arController = controller);
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final file = File(image.path);
        await _updateImageAspectRatio(file, null);
        setState(() {
          _imageFile = file;
          _libraryAssetPath = null;
          _isFloating = true;
          _isLocked = false;
          _opacity = 0.7; // 70% visible
          _showOpacitySlider = false; // Stay hidden as requested
        });
        HapticFeedback.lightImpact();
        _startPreviewTracking();
        _addARImageNode();
        AudioService.instance.playPlacement();
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _updateImageAspectRatio(File? file, String? asset) async {
    final Completer<double> completer = Completer();
    ImageStream stream;
    if (file != null) {
      stream = FileImage(file).resolve(ImageConfiguration.empty);
    } else if (asset != null) {
      stream = AssetImage(asset).resolve(ImageConfiguration.empty);
    } else {
      return;
    }
    
    final ImageStreamListener listener = ImageStreamListener((ImageInfo info, bool _) {
      final ratio = info.image.width / info.image.height;
      if (!completer.isCompleted) completer.complete(ratio);
    });

    stream.addListener(listener);
    final ratio = await completer.future.timeout(const Duration(seconds: 2), onTimeout: () => 1.0);
    stream.removeListener(listener);

    setState(() {
      _imageAspectRatio = ratio;
    });
  }

  void _addARImageNode() {
    if (_arController == null || (_imageFile == null && _libraryAssetPath == null)) return;

    // Remove existing nodes
    if (_arController is ARKitController) {
      _arController.remove('drawing_node');
      _arController.remove('shadow_node');
    } else if (_arController is ArCoreController) {
      // ArCore cleanup
    }

    if (_arController is ARKitController) {
      final transform = (_imageTransform ?? vector.Matrix4.identity()).clone();
      transform.multiply(vector.Matrix4.rotationZ(_imageRotationZ));

      final imageProperty = _libraryAssetPath != null 
          ? ARKitMaterialProperty.image(_libraryAssetPath!) 
          : ARKitMaterialProperty.image(_imageFile!.path);

      // Main Drawing Node
      _imageNode = ARKitNode(
        name: 'drawing_node',
        geometry: ARKitPlane(
          width: _imageScale * _imageAspectRatio,
          height: _imageScale,
          materials: [
            ARKitMaterial(
              diffuse: imageProperty,
              doubleSided: true,
              transparency: _opacity,
              lightingModelName: ARKitLightingModel.physicallyBased,
            ),
          ],
        ),
        transformation: transform,
      );
      _arController.add(_imageNode);

      // Shadow Plane (The "Grounding" Effect)
      final shadowTransform = transform.clone();
      shadowTransform.setTranslation(vector.Vector3(
        transform.getTranslation().x,
        transform.getTranslation().y - 0.001, // Barely below the image
        transform.getTranslation().z,
      ));

      final shadowNode = ARKitNode(
        name: 'shadow_node',
        geometry: ARKitPlane(
          width: _imageScale * _imageAspectRatio * 1.05, // Slightly larger
          height: _imageScale * 1.05,
          materials: [
            ARKitMaterial(
              diffuse: ARKitMaterialProperty.color(Colors.black),
              transparency: 0.15, // Soft shadow
            ),
          ],
        ),
        transformation: shadowTransform,
      );
      _arController.add(shadowNode);

    } else if (_arController is ArCoreController) {
      final transform = (_imageTransform ?? vector.Matrix4.identity()).clone();
      transform.multiply(vector.Matrix4.rotationZ(_imageRotationZ));
      
      _imageNode = ArCoreNode(
        image: ArCoreImage(
          bytes: _libraryAssetPath != null 
              ? File(_libraryAssetPath!).readAsBytesSync()
              : _imageFile!.readAsBytesSync(),
          width: (400 * _imageAspectRatio).toInt(),
          height: 400,
        ),
        position: transform.getTranslation(),
        rotation: vector.Vector4(0, 0, 0, 0), // Placeholder for ArCore rotation
        scale: vector.Vector3(_imageScale, _imageScale, _imageScale),
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
      AudioService.instance.playPlacement();
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
      _arController.performHitTest(x: 0.5, y: 0.5).then((results) async {
        final planeResults = results.where((r) => 
          r.type == ARKitHitTestResultType.existingPlaneUsingExtent || 
          r.type == ARKitHitTestResultType.existingPlane
        ).toList();
        
        if (planeResults.isNotEmpty) {
          final result = planeResults.first;
          final hitPosition = result.worldTransform.getTranslation();
          final cameraPos = await (_arController as ARKitController).cameraPosition();
          final targetTransform = vector.Matrix4.identity();
          
          if (cameraPos != null) {
            final dx = cameraPos.x - hitPosition.x;
            final dz = cameraPos.z - hitPosition.z;
            final heading = math.atan2(dx, dz);
            final rotationMatrix = vector.Matrix3.rotationY(heading)
              ..multiply(vector.Matrix3.rotationX(-1.5708));
            targetTransform.setRotation(rotationMatrix);
          } else {
            targetTransform.setRotation(vector.Matrix3.rotationX(-1.5708));
          }

          targetTransform.setTranslation(vector.Vector3(
            hitPosition.x,
            hitPosition.y - 0.003,
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
          if (_hasPlaneFocus || _imageNode != null) {
            setState(() {
              _hasPlaneFocus = false;
              _imageTransform = null;
            });
            _removeARImageNode();
          }
        }
      });
    } else if (_arController is ArCoreController) {
      // ArCore doesn't have a direct 'performHitTest' for the center screen in the same way.
      // We rely on Plane Detection and 'onPlaneTap' for final placement, 
      // but for preview, we can use 'ArCoreView''s built-in plane rendering logic.
    }
  }

  void _cancelSelection() {
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
    AudioService.instance.playPlacement(); // reuse click for cancel/pop
    HapticFeedback.heavyImpact();
  }

  Future<void> _toggleTorch() async {
    try {
      final isTorchAvailable = await TorchLight.isTorchAvailable();
      if (isTorchAvailable) {
        if (_isTorchOn) {
          await TorchLight.disableTorch();
        } else {
          await TorchLight.enableTorch();
        }
        setState(() {
          _isTorchOn = !_isTorchOn;
        });
        HapticFeedback.selectionClick();
      }
    } catch (e) {
      debugPrint("Error toggling torch: $e");
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    // Note: To record the AR view properly on both platforms, 
    // it's best to use a specialized plugin or native screen recording.
    // We'll simulate the video path here for the platform channel calls.
    setState(() {
      _isRecording = true;
    });
    HapticFeedback.mediumImpact();
    // Implementation would use a screen recording plugin here
  }

  Future<void> _stopRecording() async {
    setState(() {
      _isRecording = false;
      _isProcessingVideo = true;
    });
    HapticFeedback.heavyImpact();

    try {
      // Assuming 'videoPath' is the result of the screen recording
      final videoPath = "/tmp/recorded_video.mp4"; // Placeholder
      
      await _timelapseChannel.invokeMethod('processVideo', {
        'videoPath': videoPath,
      });
      debugPrint("Timelapse saved to Gallery!");
    } on PlatformException catch (e) {
      debugPrint("Timelapse processing failed: ${e.message}");
    } finally {
      setState(() => _isProcessingVideo = false);
    }
  }

  void _updateOpacity(double value) {
    if ((_opacity - value).abs() > 0.05) {
      AudioService.instance.playTick();
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
          // AR Viewport
          GestureDetector(
            onTap: _handleTap,
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            child: ARViewWrapper(onARViewCreated: _onARViewCreated),
          ),

          // Studio Framing Corners
          ..._buildStudioCorners(),

          // Tracking Status Pill
          Positioned(
            top: 60,
            left: 20,
            child: _buildTrackingStatus(),
          ),

          // Leveling Indicator
          Center(
            child: _buildLevelingIndicator(),
          ),

          // Professional Smart Reticle (Crosshair Style)
          if (_isFloating)
            Center(
              child: _buildSmartReticle(),
            ),

          // Tools Toolbar (Minimalist)
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
                  const SizedBox(height: 16),
                  _buildSideButton(
                    icon: Icons.close,
                    onTap: _cancelSelection,
                    backgroundColor: Colors.redAccent.withOpacity(0.3),
                  ),
                ],
                const SizedBox(height: 16),
                _buildSideButton(
                  icon: _isTorchOn ? Icons.flashlight_on : Icons.flashlight_off_outlined,
                  onTap: _toggleTorch,
                ),
              ],
            ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.2),
          ),

          // Bottom Navigation
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showOpacitySlider)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
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
                        _buildSuperButton(),
                        _buildSnapIcon(
                          icon: _isLocked ? Icons.lock : Icons.lock_open,
                          onTap: () {
                            AudioService.instance.playLock();
                            setState(() => _isLocked = !_isLocked);
                          },
                          isActive: _isLocked,
                        ),
                      ],
                    ),
                  ),
              ],
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2),
          ),
          
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
      child: GlassContainer(
        padding: const EdgeInsets.all(12),
        borderRadius: 30,
        blur: 10,
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
      child: GlassContainer(
        padding: const EdgeInsets.all(12),
        borderRadius: 30,
        blur: 10,
        child: Icon(
          icon,
          color: isActive ? (activeColor ?? AppColors.appleYellow) : Colors.white,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildSuperButton() {
    if (!_isFloating) {
      return GestureDetector(
        onTap: _isProcessingVideo ? null : _toggleRecording,
        child: Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer White Ring
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
              ),
              
              // Timelapse Dots Ring
              _buildTimelapseDots(),
              
              // Inner Red Button
              _isProcessingVideo
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: Colors.redAccent,
                        strokeWidth: 3,
                      ),
                    )
                  : AnimatedContainer(
                      duration: 300.ms,
                      curve: Curves.easeInOutBack,
                      width: _isRecording ? 32 : 64,
                      height: _isRecording ? 32 : 64,
                      decoration: BoxDecoration(
                        color: AppColors.neonPink,
                        borderRadius: BorderRadius.circular(_isRecording ? 8 : 32),
                      ),
                    ),
            ],
          ),
        ),
      );
    }

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
            color: AppColors.appleYellow,
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

  Widget _buildTimelapseDots() {
    return AnimatedRotation(
      turns: _isRecording ? 0 : 0, // Placeholder for continuous animation
      duration: const Duration(seconds: 10),
      child: Stack(
        children: List.generate(30, (index) {
          return Transform.rotate(
            angle: (index * 12) * (math.pi / 180),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                width: 3.5,
                height: 3.5,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    ).animate(
      onPlay: (controller) => controller.repeat(),
    ).custom(
      duration: 3.seconds,
      builder: (context, value, child) {
        return Transform.rotate(
          angle: value * 2 * math.pi,
          child: child,
        );
      },
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
                      onTap: () async {
                        final assetPath = item['asset']!;
                        await _updateImageAspectRatio(null, assetPath);
                        setState(() {
                          _libraryAssetPath = assetPath;
                          _imageFile = null;
                          _isFloating = true;
                          _isLocked = false;
                          _opacity = 0.7; // 70% visible
                          _showOpacitySlider = false; // Stay hidden
                        });
                        HapticFeedback.lightImpact();
                        _startPreviewTracking();
                        _addARImageNode(); // Fix: Show preview immediately
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                        child: Container(
                          color: Colors.white.withOpacity(0.05),
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
      color: Colors.black.withOpacity(0.8),
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
    return SizedBox(
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
    ).animate().fadeIn().slideY(begin: 0.2);
  }

  Widget _buildTutorialStep(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.appleYellow.withOpacity(0.1),
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

  List<Widget> _buildStudioCorners() {
    return [
      _buildCornerMarker(top: 40, left: 20, rotation: 0),
      _buildCornerMarker(top: 40, right: 20, rotation: 1),
      _buildCornerMarker(bottom: 40, left: 20, rotation: 3),
      _buildCornerMarker(bottom: 40, right: 20, rotation: 2),
    ];
  }

  Widget _buildCornerMarker({double? top, double? bottom, double? left, double? right, required int rotation}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: RotatedBox(
        quarterTurns: rotation,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.3), width: 1.5),
              left: BorderSide(color: Colors.white.withOpacity(0.3), width: 1.5),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 1.seconds);
  }

  Widget _buildSmartReticle() {
    final accentColor = _hasPlaneFocus ? AppColors.appleYellow : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Brackets
              AnimatedContainer(
                duration: 300.ms,
                width: _hasPlaneFocus ? 50 : 60,
                height: _hasPlaneFocus ? 50 : 60,
                child: CustomPaint(painter: CrosshairPainter(color: accentColor.withOpacity(0.5))),
              ),
              // Center Dot
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
              ),
            ],
          ),
        ).animate(target: _hasPlaneFocus ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(0.9, 0.9)),
        
        const SizedBox(height: 20),
        if (!_hasPlaneFocus)
          GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Text(
              'SCANNING SURFACE',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn().shimmer(color: Colors.white24)
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: accentColor, size: 14),
              const SizedBox(width: 6),
              const Text(
                'READY',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ],
          ).animate().fadeIn(),
      ],
    );
  }

  Widget _buildLevelingIndicator() {
    return IgnorePointer(
      child: Container(
        width: 120,
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              Colors.white.withOpacity(0.2),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackingStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _hasPlaneFocus ? Colors.greenAccent : AppColors.appleYellow,
              shape: BoxShape.circle,
            ),
          ).animate(onPlay: (c) => c.repeat()).scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 1.seconds),
          const SizedBox(width: 6),
          Text(
            _hasPlaneFocus ? 'LOCKED' : 'TRACKING',
            style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}

class CrosshairPainter extends CustomPainter {
  final Color color;
  CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const len = 10.0;
    // Four L-corners for the crosshair
    canvas.drawPath(Path()..moveTo(0, len)..lineTo(0, 0)..lineTo(len, 0), paint);
    canvas.drawPath(Path()..moveTo(size.width - len, 0)..lineTo(size.width, 0)..lineTo(size.width, len), paint);
    canvas.drawPath(Path()..moveTo(size.width, size.height - len)..lineTo(size.width, size.height)..lineTo(size.width - len, size.height), paint);
    canvas.drawPath(Path()..moveTo(len, size.height)..lineTo(0, size.height)..lineTo(0, size.height - len), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
