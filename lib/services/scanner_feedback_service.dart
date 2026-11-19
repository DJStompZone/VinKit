import 'dart:async';

import 'package:flutter/services.dart';

/// Plays immediate audible and tactile confirmation when a valid VIN barcode is
/// scanned.
abstract interface class ScannerFeedbackService {
  /// Fires the scanner confirmation beep and haptic pulse.
  Future<void> playValidScanFeedback();
}

/// Platform-backed [ScannerFeedbackService] that triggers a low-latency native
/// barcode scanner beep alongside haptic feedback.
class PlatformScannerFeedbackService implements ScannerFeedbackService {
  /// Creates a [PlatformScannerFeedbackService] using [channel].
  const PlatformScannerFeedbackService({
    MethodChannel channel = defaultChannel,
  }) : _channel = channel;

  /// Method channel implemented on Android and iOS for scanner confirmation tones.
  static const MethodChannel defaultChannel = MethodChannel(
    'zone.stomp.vinkit/scanner_feedback',
  );

  final MethodChannel _channel;

  @override
  Future<void> playValidScanFeedback() async {
    await Future.wait<void>(<Future<void>>[
      _playBeep(),
      _playHaptic(),
    ]);
  }

  Future<void> _playBeep() async {
    try {
      await _channel.invokeMethod<void>('playScanBeep');
    } on MissingPluginException {
      await _fallbackSystemSound();
    } on PlatformException {
      await _fallbackSystemSound();
    }
  }

  Future<void> _fallbackSystemSound() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // Ignore audio errors on platforms or test bindings without sound output.
    }
  }

  Future<void> _playHaptic() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // Ignore haptic errors on platforms without vibration hardware.
    }
  }
}
