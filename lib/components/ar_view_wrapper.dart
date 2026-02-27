import 'dart:io';
import 'package:flutter/material.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';

class ARViewWrapper extends StatefulWidget {
  final Function(dynamic controller) onARViewCreated;

  const ARViewWrapper({super.key, required this.onARViewCreated});

  @override
  State<ARViewWrapper> createState() => _ARViewWrapperState();
}

class _ARViewWrapperState extends State<ARViewWrapper> {
  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return ARKitSceneView(
        onARKitViewCreated: widget.onARViewCreated,
        planeDetection: ARPlaneDetection.horizontal,
        showFeaturePoints: false,
        autoenablesDefaultLighting: true,
      );
    } else if (Platform.isAndroid) {
      return ArCoreView(
        onArCoreViewCreated: widget.onARViewCreated,
        enableUpdateListener: true,
        enableTapRecognizer: true,
        enablePlaneRenderer: true,
        // ArCore typically handles both by default when enabled, 
        // but we'll ensure the renderer is on for visualization.
        // Enabling lighting estimation for ArCore
      );
    } else {
      return const Center(child: Text('AR Not Supported on this Platform'));
    }
  }
}
