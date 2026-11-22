# VinKit

A production-ready multiplatform Flutter application (Android, iOS, Web, and Windows/desktop) for scanning automotive VIN barcodes and reading plaintext printed VINs via on-device OCR, validating 17-character VINs, and immediately displaying vehicle specs, motor oil, filters, wipers, and maintenance fluid codes.

## Features

- **Automotive VIN Barcode Scanner:** Live full-screen camera preview powered by `mobile_scanner`, supporting linear and 2D vehicle sticker formats (`Code 39`, `Code 128`, `Code 93`, `DataMatrix`, `PDF417`, and `QR`) with a horizontal viewfinder cutout.
- **Scan Strictness Selector (`Normal` / `Strict`):**
  - **Normal (default):** Recognizes a wider range of real-world automotive barcodes—including manufacturer suffix/prefix characters (such as Hyundai Elantra's 18-character barcode with an appended `A`) and embedded VINs inside multi-field 2D stickers—ranking candidates with ISO 3779 check-digit and structural scoring. In OCR mode, also normalizes forbidden VIN letters (`I`/`l`/`|` → `1`, `O`/`Q` → `0`) and performs check-digit-verified single-character repair on ambiguous glyphs.
  - **Strict:** Enforces exact 17-character VIN matching (stripping only whitespace/hyphens, Code 39 `*` sentinels, and legacy 18-character leading `I`) with no fuzzy substitutions. If a barcode fails Strict mode due to extra characters, VinKit offers a one-tap **Use Normal** shortcut right in the scanner banner.
- **On-Device Plaintext VIN OCR Mode (`Barcode` / `OCR`):**
  - Powered by `mobile_ocr` using **ONNX Runtime Mobile (PaddleOCR v5)** on Android (models ~20 MB downloaded once on first use and cached locally with SHA-256 verification) and **Apple Vision** on iOS.
  - Includes native viewfinder ROI cropping & resolution capping (`zone.stomp.vinkit/ocr_image_prep`) so cluttered scenes never exhaust memory, plus collapsible **Exposure (EV) & Gamma** controls (`Auto`, `Glare`, `Dark` presets + fine sliders with live gamma preview) for harsh windshield glare or shadowed door jambs.
  - Designed for vehicles where the VIN is printed in plaintext on the windshield or door jamb without a barcode. Includes tap-to-focus, zoom presets/slider, flashlight toggle, and one-tap **Edit** prefill into manual entry if glare causes a partial read.
- **Instant Scan Lock & Confirmation Beep:** The instant a valid 17-character VIN is detected (via barcode or OCR), VinKit plays a crisp 3.4 kHz square-wave scanner beep + haptic pulse, stops the scanner immediately, and opens the full-screen Vehicle Spec Sheet.
- **High-Density Full-Screen Vehicle Spec Sheet:** Queries `https://vin.stomp.zone/api/v1/vin/{VIN}` via `dio` and immediately displays Year, Make, Model, Trim, Engine, VIN, Recommended Oil viscosity/capacity, Filters, and Wiper Blade sizes/connectors above the fold, followed by Battery specs, all oil options, fluid services with copyable product codes, powertrain/catalog match details, and one-tap **Copy All Specs**.
- **Web & Desktop Support:** Web runs live camera scanning with Web Audio API beep feedback; Windows/Linux desktop uses `DesktopVinEntryView` with full keyboard, clipboard, and USB barcode scanner support (including `Normal`/`Strict` strictness).
- **Branded Sunset Theme & Animated Splash:** Custom VinKit app icons across Android (adaptive + monochrome + Android 12+ splash), iOS, Web, and Windows, paired with a sunset amber-to-magenta Material 3 palette and an animated VIN scanline startup splash.

## Project Structure

```text
lib/
├── main.dart                         # App entry point and dependency wiring
├── models/
│   ├── json_parsers.dart             # Defensive JSON parsing and unit formatting helpers
│   ├── matched_parts_vehicle.dart    # Secondary catalog-matched vehicle model
│   ├── oil_spec.dart                 # Motor oil viscosity, type, and quart capacity model
│   ├── vehicle_info.dart             # Core decoded vehicle identity model
│   ├── vehicle_part.dart             # Categorized replacement part fitment model
│   ├── vehicle_service_item.dart     # Fluid and maintenance service item model
│   ├── vf_match.dart                 # Product Finder engine match metadata model
│   ├── vin_lookup_exception.dart     # Classified lookup error categories and exception
│   ├── vin_lookup_result.dart        # Aggregated API response model
│   └── vin_lookup_state.dart         # Sealed idle/loading/success/failure states
├── screens/
│   ├── scanner_screen.dart           # Barcode/OCR scanner, Normal/Strict toggle, instant beep/stop
│   └── vehicle_result_screen.dart    # Full-screen high-density vehicle spec sheet
├── services/
│   ├── ocr_image_preprocessor.dart   # Native ROI crop & gamma preprocessing + preview LUT matrix
│   ├── scanner_feedback_service.dart # Native/Web 3.4 kHz scanner beep & haptic feedback service
│   ├── stomp_zone_vin_service.dart   # Dio-backed vin.stomp.zone API service
│   ├── vin_lookup_controller.dart    # ChangeNotifier coordinating validation & lookups
│   ├── vin_lookup_service.dart       # Abstract interface for swapping VIN backends
│   ├── vin_ocr_service.dart          # Cross-platform on-device OCR interface & row grouping
│   ├── vin_ocr_service_io.dart       # mobile_ocr (ONNX Runtime PaddleOCR v5 / Apple Vision)
│   ├── vin_ocr_service_stub.dart     # Web/Wasm stub for OCR service
│   └── vin_validator.dart            # Strict/Normal barcode extraction, ISO 3779 check digit, OCR extraction
├── theme/
│   └── app_theme.dart                # Sunset amber-coral-magenta Material 3 light & dark themes
└── widgets/
    ├── camera_permission_view.dart   # Camera denial/error UI with Settings shortcut
    ├── desktop_vin_entry_view.dart   # Windows/Linux desktop keyboard & USB scanner view
    ├── manual_vin_sheet.dart         # Manual VIN entry & clipboard paste modal sheet
    ├── ocr_camera_view.dart          # Live camera capture view with Exposure/Gamma & PaddleOCR v5
    ├── scanner_controls.dart         # Zoom, torch, collapsible EV/Gamma lighting, OCR/manual triggers
    ├── scanner_overlay.dart          # CustomPainter horizontal cutout mask, gradient scanline & banner
    └── startup_splash_overlay.dart   # Animated branded VIN scanline startup splash overlay
```

## Swapping the VIN Backend

All network calls go through the `VinLookupService` interface (`lib/services/vin_lookup_service.dart`). To point to another environment or swap in a different VIN API:

1. Pass a custom `baseUrl` to `StompZoneVinService(baseUrl: 'https://your-host/api/v1/vin')`, **or**
2. Implement `VinLookupService` and inject your implementation into `VinKitApp(vinLookupService: ...)`.

## Platform Configuration

- **Android (`android/app/src/main/AndroidManifest.xml` & `android/app/build.gradle.kts`):**
  - Declares `android.permission.CAMERA` and `android.permission.INTERNET`.
  - Configures `compileSdk = 37`, `minSdk = flutter.minSdkVersion` (API 24+, matching `mobile_ocr` ONNX Runtime Mobile requirements), and Java 17 toolchain targets.
- **iOS (`ios/Runner/Info.plist`):**
  - Configures `NSCameraUsageDescription` explaining VIN barcode & OCR scanning.

## Getting Started & Verification

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build web
flutter build windows --debug
```
