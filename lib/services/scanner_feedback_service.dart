import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vinkit_app/services/web_beep_stub.dart'
    if (dart.library.js_interop) 'package:vinkit_app/services/web_beep_web.dart'
    as web_beep;

/// Plays immediate audible and tactile confirmation when a valid VIN barcode is
/// scanned.
abstract interface class ScannerFeedbackService {
  /// Fires the scanner confirmation beep and haptic pulse.
  Future<void> playValidScanFeedback();
}

/// Platform-backed [ScannerFeedbackService] that triggers a low-latency native
/// barcode scanner beep (or Web Audio beep on Web) alongside haptic feedback.
class PlatformScannerFeedbackService implements ScannerFeedbackService {
  /// Creates a [PlatformScannerFeedbackService] using [channel].
  const PlatformScannerFeedbackService({
    this.channel = defaultChannel,
  });

  /// Method channel implemented on Android and iOS for scanner confirmation tones.
  static const MethodChannel defaultChannel = MethodChannel(
    'zone.stomp.vinkit/scanner_feedback',
  );

  /// Platform method channel invoked for scanner confirmation tones.
  final MethodChannel channel;

  @override
  Future<void> playValidScanFeedback() async {
    await Future.wait<void>(<Future<void>>[
      _playBeep(),
      _playHaptic(),
    ]);
  }

  Future<void> _playBeep() async {
    if (kIsWeb) {
      if (web_beep.playWebScanBeep()) {
        return;
      }
      await _fallbackSystemSound();
      return;
    }

    try {
      await channel.invokeMethod<void>('playScanBeep');
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
