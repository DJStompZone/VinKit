import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/screens/scanner_screen.dart';
import 'package:vinkit_app/services/scanner_feedback_service.dart';
import 'package:vinkit_app/services/stomp_zone_vin_service.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';
import 'package:vinkit_app/services/vin_lookup_service.dart';
import 'package:vinkit_app/services/vin_ocr_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/theme/app_theme.dart';
import 'package:vinkit_app/widgets/startup_splash_overlay.dart';

/// Application entry point initializing Flutter bindings and launching [VinKitApp].
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VinKitApp());
}

/// Root Material 3 application widget configuring themes, startup splash flair,
/// and VIN services.
class VinKitApp extends StatefulWidget {
  /// Creates a [VinKitApp] with optional dependency overrides for testing.
  const VinKitApp({
    super.key,
    this.vinLookupService,
    this.validator = const VinValidator(),
    this.feedbackService = const PlatformScannerFeedbackService(),
    this.ocrService,
    this.initialThemeMode = ThemeMode.system,
    this.showStartupSplash = true,
  });

  /// Optional [VinLookupService] override; defaults to [StompZoneVinService].
  final VinLookupService? vinLookupService;

  /// Validator instance shared across scanner, OCR, and manual VIN entry flows.
  final VinValidator validator;

  /// Service playing audible beep and haptic feedback on valid VIN scans.
  final ScannerFeedbackService feedbackService;

  /// Optional on-device OCR service override (defaults to `mobile_ocr` on Android/iOS).
  final VinOcrService? ocrService;

  /// Initial Material theme mode.
  final ThemeMode initialThemeMode;

  /// Whether to show the animated branded startup splash overlay on launch.
  final bool showStartupSplash;

  @override
  State<VinKitApp> createState() => _VinKitAppState();
}

class _VinKitAppState extends State<VinKitApp> {
  late final VinLookupService _service;
  late final bool _ownsService;
  late final VinLookupController _vinController;
  late ThemeMode _themeMode;
  late bool _showSplash;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.vinLookupService == null;
    _service =
        widget.vinLookupService ?? StompZoneVinService(validator: widget.validator);
    _vinController = VinLookupController(
      service: _service,
      validator: widget.validator,
    );
    _themeMode = widget.initialThemeMode;
    _showSplash = widget.showStartupSplash;
  }

  void _cycleThemeMode() {
    setState(() {
      _themeMode = switch (_themeMode) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      };
    });
  }

  @override
  void dispose() {
    _vinController.dispose();
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VinKit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ScannerScreen(
            vinController: _vinController,
            validator: widget.validator,
            themeMode: _themeMode,
            onCycleThemeMode: _cycleThemeMode,
            feedbackService: widget.feedbackService,
            ocrService: widget.ocrService,
            deferCameraPermissionPrompt: _showSplash,
          ),
          if (_showSplash)
            StartupSplashOverlay(
              onFinished: () {
                if (mounted) {
                  setState(() => _showSplash = false);
                }
              },
            ),
        ],
      ),
    );
  }
}
