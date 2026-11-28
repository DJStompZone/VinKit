import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/services/camera_permission_service.dart';
import 'package:vinkit_app/services/crash_reporting_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/theme/app_theme.dart';

/// Modal bottom sheet providing opt-in Firebase Crashlytics controls, manual
/// bug report and feedback submission, camera permission management, and
/// internal cache/state reset actions.
class SettingsSheet extends StatefulWidget {
  /// Creates a [SettingsSheet].
  const SettingsSheet({
    super.key,
    required this.crashReportingService,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.strictness,
    required this.onStrictnessChanged,
    required this.onResetStateAndCache,
    this.cameraPermissionState,
    this.supportsNativePermissions = false,
    this.onRequestCameraPermission,
    this.onOpenSystemSettings,
    this.onRecheckPermissions,
    this.onResetOcrModelCache,
    this.extraDiagnostics = const <String, String>{},
    this.initialFeedbackVin,
  });

  /// Service managing opt-in Crashlytics collection and user feedback reports.
  final CrashReportingService crashReportingService;

  /// Active Material theme mode.
  final ThemeMode themeMode;

  /// Callback invoked when the user selects a specific [ThemeMode].
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// Active VIN matching strictness (`Normal` or `Strict`).
  final VinScanStrictness strictness;

  /// Callback invoked when the user changes VIN matching strictness.
  final ValueChanged<VinScanStrictness> onStrictnessChanged;

  /// Resets scanner state, lighting, lookup cache, and temporary image files.
  /// Returns the number of temporary cache files removed.
  final Future<int> Function() onResetStateAndCache;

  /// Current runtime camera permission state, if applicable.
  final CameraPermissionState? cameraPermissionState;

  /// Whether the active platform uses runtime OS permissions (`Android`/`iOS`).
  final bool supportsNativePermissions;

  /// Requests runtime camera permission from the OS.
  final Future<CameraPermissionState> Function()? onRequestCameraPermission;

  /// Opens the OS application settings screen.
  final Future<bool> Function()? onOpenSystemSettings;

  /// Re-queries the current OS camera permission state.
  final Future<CameraPermissionState> Function()? onRecheckPermissions;

  /// Optional callback to purge cached on-device PaddleOCR v5 ONNX models so
  /// they can be freshly verified and re-downloaded.
  final Future<bool> Function()? onResetOcrModelCache;

  /// Snapshot of active scanner/app diagnostic key-values to attach to reports.
  final Map<String, String> extraDiagnostics;

  /// Optional prefilled VIN for the bug report form (e.g. last scanned VIN).
  final String? initialFeedbackVin;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late ThemeMode _themeMode;
  late VinScanStrictness _strictness;
  CameraPermissionState? _permissionState;

  FeedbackCategory _selectedCategory = FeedbackCategory.bugOrCrash;
  late final TextEditingController _descriptionController;
  late final TextEditingController _vinController;
  bool _includeDiagnostics = true;
  bool _isSubmittingFeedback = false;
  bool _isResettingState = false;
  bool _isResettingOcrModels = false;
  String? _actionStatusBanner;
  bool _actionStatusIsSuccess = true;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _strictness = widget.strictness;
    _permissionState = widget.cameraPermissionState;
    _descriptionController = TextEditingController()
      ..addListener(_onFormChanged);
    _vinController = TextEditingController(
      text: widget.initialFeedbackVin ?? '',
    );
  }

  void _onFormChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showStatusBanner(String message, {bool isSuccess = true}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _actionStatusBanner = message;
      _actionStatusIsSuccess = isSuccess;
    });
  }

  Future<void> _handleResetStateAndCache() async {
    if (_isResettingState) {
      return;
    }
    setState(() => _isResettingState = true);
    try {
      final removedFiles = await widget.onResetStateAndCache();
      if (!mounted) {
        return;
      }
      setState(() {
        _strictness = VinScanStrictness.normal;
        _isResettingState = false;
      });
      final fileDetail =
          removedFiles > 0 ? ' ($removedFiles temp files cleared)' : '';
      _showStatusBanner(
        'Scanner state, lighting controls, and temporary cache reset$fileDetail.',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isResettingState = false);
      _showStatusBanner(
        'Reset completed with minor warnings.',
        isSuccess: false,
      );
    }
  }

  Future<void> _handleResetOcrModels() async {
    final resetter = widget.onResetOcrModelCache;
    if (resetter == null || _isResettingOcrModels) {
      return;
    }
    setState(() => _isResettingOcrModels = true);
    try {
      final cleared = await resetter();
      if (!mounted) {
        return;
      }
      setState(() => _isResettingOcrModels = false);
      _showStatusBanner(
        cleared
            ? 'On-device OCR model cache cleared. Models will re-download on next OCR use.'
            : 'OCR model cache is already clean.',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isResettingOcrModels = false);
      _showStatusBanner(
        'Could not clear OCR model cache.',
        isSuccess: false,
      );
    }
  }

  Future<void> _handleRequestPermission() async {
    final requester = widget.onRequestCameraPermission;
    if (requester == null) {
      return;
    }
    final nextState = await requester();
    if (!mounted) {
      return;
    }
    setState(() => _permissionState = nextState);
    _showStatusBanner(
      nextState == CameraPermissionState.granted
          ? 'Camera permission granted.'
          : 'Camera permission is ${ _permissionLabel(nextState).toLowerCase() }.',
      isSuccess: nextState == CameraPermissionState.granted,
    );
  }

  Future<void> _handleRecheckPermission() async {
    final checker = widget.onRecheckPermissions;
    if (checker == null) {
      return;
    }
    final nextState = await checker();
    if (!mounted) {
      return;
    }
    setState(() => _permissionState = nextState);
    _showStatusBanner(
      'Camera permission status: ${_permissionLabel(nextState)}.',
      isSuccess: nextState == CameraPermissionState.granted,
    );
  }

  Future<void> _handleOpenSystemSettings() async {
    final opener = widget.onOpenSystemSettings;
    if (opener == null) {
      return;
    }
    final opened = await opener();
    if (!mounted) {
      return;
    }
    if (!opened) {
      _showStatusBanner(
        'System settings could not be opened automatically on this platform.',
        isSuccess: false,
      );
    }
  }

  Future<void> _handleCopyDiagnostics() async {
    final summary = widget.crashReportingService.buildDiagnosticSummary(
      vin: _vinController.text,
      extraDiagnostics: widget.extraDiagnostics,
    );
    try {
      await Clipboard.setData(
        ClipboardData(text: summary),
      ).timeout(const Duration(milliseconds: 250));
      _showStatusBanner('Diagnostic summary copied to clipboard.');
    } catch (_) {
      _showStatusBanner('Diagnostic summary ready.');
    }
  }

  Future<void> _handleSubmitFeedback() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty || _isSubmittingFeedback) {
      return;
    }
    setState(() => _isSubmittingFeedback = true);
    try {
      final result = await widget.crashReportingService.submitUserFeedback(
        category: _selectedCategory,
        description: description,
        vin: _vinController.text,
        includeDiagnostics: _includeDiagnostics,
        copyToClipboard: true,
        extraDiagnostics: widget.extraDiagnostics,
      );
      if (!mounted) {
        return;
      }
      _descriptionController.clear();
      setState(() => _isSubmittingFeedback = false);

      if (result.sentToCrashlytics && result.copiedToClipboard) {
        _showStatusBanner(
          'Report sent to Crashlytics and copied to clipboard.',
        );
      } else if (result.sentToCrashlytics) {
        _showStatusBanner('Report sent to Crashlytics.');
      } else if (result.copiedToClipboard) {
        _showStatusBanner(
          'Report formatted with diagnostics and copied to clipboard.',
        );
      } else {
        _showStatusBanner('Report recorded in session diagnostics.');
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSubmittingFeedback = false);
      _showStatusBanner(
        'Failed to submit report. Try Copy Diagnostics instead.',
        isSuccess: false,
      );
    }
  }

  String _permissionLabel(CameraPermissionState? state) {
    return switch (state) {
      CameraPermissionState.granted => 'Granted',
      CameraPermissionState.denied => 'Denied',
      CameraPermissionState.permanentlyDenied => 'Blocked in OS Settings',
      CameraPermissionState.checking ||
      CameraPermissionState.requesting =>
        'Pending',
      null => kIsWeb ? 'Browser Managed' : 'Desktop Mode',
    };
  }

  @override
  void dispose() {
    _descriptionController
      ..removeListener(_onFormChanged)
      ..dispose();
    _vinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final canSubmitFeedback =
        _descriptionController.text.trim().isNotEmpty && !_isSubmittingFeedback;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: ListenableBuilder(
          listenable: widget.crashReportingService,
          builder: (context, _) {
            final isOptedIn = widget.crashReportingService.isOptedIn;
            final nativeSupported =
                widget.crashReportingService.isNativeCrashlyticsSupported;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.tune_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Settings & Diagnostics',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'VinKit v${CrashReportingService.appVersion} • Privacy, cache & feedback',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close Settings',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (_actionStatusBanner != null) ...<Widget>[
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _actionStatusIsSuccess
                          ? colorScheme.primaryContainer.withValues(alpha: 0.75)
                          : colorScheme.errorContainer.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _actionStatusIsSuccess
                            ? colorScheme.primary.withValues(alpha: 0.35)
                            : colorScheme.error.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            _actionStatusIsSuccess
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            size: 18,
                            color: _actionStatusIsSuccess
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _actionStatusBanner!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _actionStatusIsSuccess
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // 1. Privacy & Opt-In Crashlytics Card
                        Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.shield_outlined,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Privacy & Crash Reporting',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isOptedIn
                                    ? colorScheme.primaryContainer
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                isOptedIn ? 'Opted In' : 'Opt-In (Off)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isOptedIn
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile.adaptive(
                          key: const Key('settings_crashlytics_switch'),
                          contentPadding: EdgeInsets.zero,
                          value: isOptedIn,
                          onChanged: (enabled) => unawaited(
                            widget.crashReportingService.setOptIn(enabled),
                          ),
                          title: Text(
                            'Send Crash & Error Diagnostics',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            nativeSupported
                                ? 'Automatically report uncaught crashes and non-fatal OCR/API errors via Firebase Crashlytics. VIN serial numbers are masked (e.g. 1FM5K8GCXNG******). Turning this off deletes any unsent local reports.'
                                : 'Preference saved for this session. Native Firebase Crashlytics background upload is active on Android, iOS, and macOS builds.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Appearance & Scanner Preferences Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.palette_outlined,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Appearance & Scanner Defaults',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: <Widget>[
                            Text(
                              'Theme',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: const <ButtonSegment<ThemeMode>>[
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.system,
                                  label: Text('System'),
                                  icon: Icon(
                                    Icons.brightness_auto_rounded,
                                    size: 16,
                                  ),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.light,
                                  label: Text('Light'),
                                  icon: Icon(
                                    Icons.light_mode_rounded,
                                    size: 16,
                                  ),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.dark,
                                  label: Text('Dark'),
                                  icon: Icon(
                                    Icons.dark_mode_rounded,
                                    size: 16,
                                  ),
                                ),
                              ],
                              selected: <ThemeMode>{_themeMode},
                              onSelectionChanged: (selection) {
                                if (selection.isNotEmpty) {
                                  final next = selection.first;
                                  setState(() => _themeMode = next);
                                  widget.onThemeModeChanged(next);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: <Widget>[
                            Text(
                              'VIN Match Strictness',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SegmentedButton<VinScanStrictness>(
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: const <
                                  ButtonSegment<VinScanStrictness>>[
                                ButtonSegment<VinScanStrictness>(
                                  value: VinScanStrictness.normal,
                                  label: Text('Normal'),
                                ),
                                ButtonSegment<VinScanStrictness>(
                                  value: VinScanStrictness.strict,
                                  label: Text('Strict'),
                                ),
                              ],
                              selected: <VinScanStrictness>{_strictness},
                              onSelectionChanged: (selection) {
                                if (selection.isNotEmpty) {
                                  final next = selection.first;
                                  setState(() => _strictness = next);
                                  widget.onStrictnessChanged(next);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 3. Cache, State & Permissions Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.storage_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Cache, State & Permissions',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Camera Permission',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _permissionLabel(_permissionState),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _permissionState ==
                                              CameraPermissionState.granted
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_permissionState ==
                                    CameraPermissionState.denied &&
                                widget.onRequestCameraPermission != null)
                              FilledButton.tonal(
                                key: const Key(
                                  'settings_request_permission_button',
                                ),
                                onPressed: () =>
                                    unawaited(_handleRequestPermission()),
                                child: const Text('Grant Access'),
                              ),
                            if (widget.onRecheckPermissions != null) ...<Widget>[
                              const SizedBox(width: 8),
                              IconButton(
                                key: const Key(
                                  'settings_recheck_permission_button',
                                ),
                                onPressed: () =>
                                    unawaited(_handleRecheckPermission()),
                                tooltip: 'Recheck camera permission',
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                            if (widget.supportsNativePermissions &&
                                widget.onOpenSystemSettings != null) ...<Widget>[
                              const SizedBox(width: 4),
                              OutlinedButton.icon(
                                key: const Key(
                                  'settings_open_os_settings_button',
                                ),
                                onPressed: () =>
                                    unawaited(_handleOpenSystemSettings()),
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                ),
                                label: const Text('OS Settings'),
                              ),
                            ],
                          ],
                        ),
                        const Divider(height: 24),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            OutlinedButton.icon(
                              key: const Key('settings_reset_state_button'),
                              onPressed: _isResettingState
                                  ? null
                                  : () => unawaited(_handleResetStateAndCache()),
                              icon: _isResettingState
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.restart_alt_rounded,
                                      size: 18,
                                    ),
                              label: const Text(
                                'Reset Scanner State & Temp Cache',
                              ),
                            ),
                            if (widget.onResetOcrModelCache != null)
                              OutlinedButton.icon(
                                key: const Key(
                                  'settings_reset_ocr_models_button',
                                ),
                                onPressed: _isResettingOcrModels
                                    ? null
                                    : () => unawaited(_handleResetOcrModels()),
                                icon: _isResettingOcrModels
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.cleaning_services_outlined,
                                        size: 18,
                                      ),
                                label: const Text('Reset OCR Model Cache'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Manual Bug Report / Feedback Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.bug_report_outlined,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Submit Bug Report or Feedback',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              key: const Key(
                                'settings_copy_diagnostics_button',
                              ),
                              onPressed: () =>
                                  unawaited(_handleCopyDiagnostics()),
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy Diagnostics'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: FeedbackCategory.values.map((category) {
                            final selected = category == _selectedCategory;
                            return ChoiceChip(
                              label: Text(category.label),
                              selected: selected,
                              onSelected: (_) {
                                setState(() => _selectedCategory = category);
                              },
                            );
                          }).toList(growable: false),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('settings_feedback_description_field'),
                          controller: _descriptionController,
                          minLines: 2,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            labelText: 'Describe the issue or feedback',
                            hintText:
                                'What happened, or what vehicle/barcode had trouble?',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          key: const Key('settings_feedback_vin_field'),
                          controller: _vinController,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            letterSpacing: 1.1,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Related VIN (optional)',
                            hintText: '1FM5K8GCXNGA77516',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          value: _includeDiagnostics,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _includeDiagnostics = val);
                            }
                          },
                          title: Text(
                            'Include scanner mode, strictness & recent diagnostic logs',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const Key('settings_submit_feedback_button'),
                          onPressed: canSubmitFeedback
                              ? () => unawaited(_handleSubmitFeedback())
                              : null,
                          icon: _isSubmittingFeedback
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            nativeSupported
                                ? 'Submit Report & Copy to Clipboard'
                                : 'Generate & Copy Bug Report',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
