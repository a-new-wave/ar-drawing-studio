import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class AudioService {
  static final AudioService instance = AudioService._internal();
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  
  // Pre-load common sound effects
  // Note: These assets should be added to pubspec.yaml and assets/audio/ folder
  static const String placementClick = 'audio/placement_click.mp3';
  static const String sliderTick = 'audio/slider_tick.mp3';
  static const String lockHum = 'audio/lock_hum.mp3';
  static const String undoPop = 'audio/undo_pop.mp3';

  Future<void> playPlacement() async {
    await _player.play(AssetSource(placementClick));
    await HapticFeedback.mediumImpact();
  }

  Future<void> playTick() async {
    // Low latency tick for sliders
    await _player.play(AssetSource(sliderTick), volume: 0.3);
    await HapticFeedback.selectionClick();
  }

  Future<void> playLock() async {
    await _player.play(AssetSource(lockHum));
    await HapticFeedback.heavyImpact();
  }
}
