import 'dart:js_interop';

@JS('vinkitPlayScanBeep')
external JSBoolean? _vinkitPlayScanBeep();

/// Triggers the Web Audio API confirmation beep defined in `web/index.html`.
bool playWebScanBeep() {
  try {
    return _vinkitPlayScanBeep()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
