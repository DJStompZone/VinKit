# VinKit

A production-ready multiplatform Flutter mobile application (targeting Android and iOS) for scanning automotive VIN barcodes, validating 17-character VINs, and looking up vehicle details, replacement parts, motor oil specifications, and fluid maintenance services.

## Features

- **Automotive VIN Barcode Scanner:** Live full-screen camera preview powered by `mobile_scanner`, tuned for `BarcodeFormat.code39` and `BarcodeFormat.code128` linear barcodes with a semi-transparent horizontal viewfinder cutout.
- **Legacy Code 39 Prefix Handling:** Automatically strips Code 39 `*` sentinels and the 18-character leading `I` prefix emitted by older automotive VIN barcodes before validation.
- **Scanner Controls:** Flashlight/torch toggle, `1x` / `2x` zoom presets plus continuous zoom slider for small windshield stickers, haptic feedback (`HapticFeedback.mediumImpact()`), and automatic scanner pause/resume across result sheets and app lifecycle transitions.
- **Manual VIN Entry Fallback:** Modal bottom sheet with auto-uppercasing, live `X / 17` character counter, one-tap clipboard paste, and instant inline validation.
- **Pre-Request VIN Validation:** Enforces exact 17-character alphanumeric format excluding `I`, `O`, and `Q` before issuing network requests.
- **Custom VIN Backend Integration:** Queries `https://vin.stomp.zone/api/v1/vin/{VIN}` via `dio` and presents decoded vehicle summaries, one-tap copyable raw VIN and part numbers, categorized parts (oil/air/cabin/fuel filters, battery, wiper blades), oil viscosity and quart capacity options, and fluid service schedules in Material 3 cards.
- **Resilient Error & Permission Handling:** Graceful handling for network failures, timeouts, HTTP 400/404 unrecognized VINs, and runtime camera permission denials with an **Open App Settings** prompt (`permission_handler`) plus retry and manual-entry fallbacks.
- **Material 3 Light & Dark Themes:** Full `useMaterial3: true` support with system default and an in-app theme toggle.

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
│   └── scanner_screen.dart           # Camera scanner screen, lifecycle, and sheet flow
├── services/
│   ├── stomp_zone_vin_service.dart   # Dio-backed vin.stomp.zone API service
│   ├── vin_lookup_controller.dart    # ChangeNotifier coordinating validation & lookups
│   ├── vin_lookup_service.dart       # Abstract interface for swapping VIN backends
│   └── vin_validator.dart            # Normalization, validation, and barcode extraction
├── theme/
│   └── app_theme.dart                # Material 3 light and dark theme definitions
└── widgets/
    ├── camera_permission_view.dart   # Camera denial/error UI with Settings shortcut
    ├── manual_vin_sheet.dart         # Manual VIN entry & clipboard paste modal sheet
    ├── scanner_controls.dart         # Zoom slider, 1x/2x presets, torch, manual trigger
    ├── scanner_overlay.dart          # CustomPainter horizontal barcode cutout mask
    └── vehicle_result_sheet.dart     # Scrollable Material 3 vehicle & parts result sheet
```

## Swapping the VIN Backend

All network calls go through the `VinLookupService` interface (`lib/services/vin_lookup_service.dart`). To point to another environment or swap in a different VIN API:

1. Pass a custom `baseUrl` to `StompZoneVinService(baseUrl: 'https://your-host/api/v1/vin')`, **or**
2. Implement `VinLookupService` and inject your implementation into `VinKitApp(vinLookupService: ...)`.

## Platform Configuration

- **Android (`android/app/src/main/AndroidManifest.xml` & `android/app/build.gradle.kts`):**
  - Declares `android.permission.CAMERA` and `android.permission.INTERNET` (plus optional camera/autofocus hardware features).
  - Configures `compileSdk = 37` (for `permission_handler_android`), `minSdk = flutter.minSdkVersion` (API 24 in Flutter 3.50, exceeding both API 21+ and `mobile_scanner` 7.x API 23+ requirements), and Java 17 toolchain targets.
- **iOS (`ios/Runner/Info.plist`):**
  - Configures `NSCameraUsageDescription` explaining VIN barcode scanning.

## Getting Started & Verification

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

To run on a connected Android or iOS device:

```bash
flutter run
```
