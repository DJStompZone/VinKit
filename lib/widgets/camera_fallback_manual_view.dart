import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/services/camera_permission_service.dart';
import 'package:vinkit_app/services/vin_validator.dart';
import 'package:vinkit_app/theme/app_theme.dart';

/// Graceful inline manual VIN entry view shown while waiting for camera
/// permission, when camera permission is denied, or if the camera hardware is
/// temporarily unavailable.
///
/// Leaves space at the top for the scanner HUD (where camera-only controls are
/// visibly greyed out) and displays a calm tooltip banner with an option to
/// allow camera access or open system settings.
class CameraFallbackManualView extends StatefulWidget {
  /// Creates a [CameraFallbackManualView].
  const CameraFallbackManualView({
    super.key,
    required this.validator,
    required this.strictness,
    required this.permissionState,
    required this.onSubmitVin,
    this.cameraHardwareError,
    this.onRequestPermission,
    this.onOpenSettings,
    this.onRetryCamera,
    this.topHudInset = 132.0,
  });

  /// Validator used to normalize and validate VIN entries.
  final VinValidator validator;

  /// Active VIN matching strictness (`Normal` or `Strict`).
  final VinScanStrictness strictness;

  /// Active camera permission state.
  final CameraPermissionState permissionState;

  /// Optional sanitized hardware error message when permission is granted but
  /// the camera failed to initialize.
  final String? cameraHardwareError;

  /// Invoked with a validated 17-character VIN when submitted.
  final ValueChanged<String> onSubmitVin;

  /// Invoked when the user taps to re-request camera permission.
  final VoidCallback? onRequestPermission;

  /// Invoked when the user taps the Settings link to enable camera access.
  final VoidCallback? onOpenSettings;

  /// Invoked when the user taps Retry after a camera hardware error.
  final VoidCallback? onRetryCamera;

  /// Clearance below the safe area reserved for the overlaid scanner top HUD.
  final double topHudInset;

  @override
  State<CameraFallbackManualView> createState() =>
      _CameraFallbackManualViewState();
}

class _CameraFallbackManualViewState extends State<CameraFallbackManualView> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String? _resolveValidVin(String raw) {
    final direct = widget.validator.validate(raw);
    if (direct.isValid) {
      return direct.normalizedVin;
    }
    return widget.validator.extractFromBarcode(
      raw,
      strictness: widget.strictness,
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (!mounted || raw == null || raw.trim().isEmpty) {
      return;
    }
    final extracted = widget.validator.extractFromBarcode(
      raw,
      strictness: widget.strictness,
    );
    final normalized = extracted ?? widget.validator.normalizeManualInput(raw);
    _controller.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  void _submit() {
    final validVin = _resolveValidVin(_controller.text);
    if (validVin == null) {
      return;
    }
    _focusNode.unfocus();
    _controller.clear();
    widget.onSubmitVin(validVin);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildCameraStatusTooltip(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = widget.permissionState;
    final hasHardwareError =
        state == CameraPermissionState.granted &&
        widget.cameraHardwareError != null;

    final IconData icon;
    final String headline;
    final String subtitle;

    if (hasHardwareError) {
      icon = Icons.videocam_off_outlined;
      headline = 'Camera scanning unavailable';
      subtitle = widget.cameraHardwareError!;
    } else if (state == CameraPermissionState.checking ||
        state == CameraPermissionState.requesting) {
      icon = Icons.photo_camera_outlined;
      headline = 'Waiting for camera access';
      subtitle =
          'Allow camera permission to scan VIN barcodes and printed text, or enter a VIN manually below.';
    } else if (state == CameraPermissionState.permanentlyDenied) {
      icon = Icons.no_photography_outlined;
      headline = 'Camera scanning disabled';
      subtitle =
          'Allow camera access in Settings to enable barcode and OCR scanning.';
    } else {
      icon = Icons.no_photography_outlined;
      headline = 'Camera scanning disabled';
      subtitle =
          'Allow camera access to scan VIN barcodes and printed text, or keep using manual entry below.';
    }

    final isWaiting =
        state == CameraPermissionState.checking ||
        state == CameraPermissionState.requesting;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.brandAmber.withValues(alpha: 0.34),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.brandAmber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: isWaiting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                      : Icon(
                          icon,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        headline,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isWaiting) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  if (hasHardwareError && widget.onRetryCamera != null)
                    FilledButton.tonalIcon(
                      onPressed: widget.onRetryCamera,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry Camera'),
                    ),
                  if (!hasHardwareError &&
                      state == CameraPermissionState.denied &&
                      widget.onRequestPermission != null)
                    FilledButton.tonalIcon(
                      onPressed: widget.onRequestPermission,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.camera_alt_outlined, size: 16),
                      label: const Text('Allow Camera'),
                    ),
                  if (!hasHardwareError && widget.onOpenSettings != null)
                    TextButton.icon(
                      onPressed: widget.onOpenSettings,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: Text(
                        state == CameraPermissionState.permanentlyDenied
                            ? 'Open Settings'
                            : 'Settings',
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rawText = _controller.text;
    final validVin = _resolveValidVin(rawText);
    final normalized = validVin ?? widget.validator.normalizeManualInput(rawText);
    final validation = widget.validator.validate(normalized);
    final showValidationError = rawText.trim().isNotEmpty && validVin == null;

    return ColoredBox(
      color: colorScheme.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                18,
                widget.topHudInset,
                18,
                24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - widget.topHudInset - 24)
                      .clamp(0.0, double.infinity),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildCameraStatusTooltip(context),
                        const SizedBox(height: 16),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          margin: EdgeInsets.zero,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Container(
                                height: 3,
                                decoration: const BoxDecoration(
                                  gradient: AppTheme.brandGradient,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Icon(
                                          Icons.keyboard_alt_outlined,
                                          size: 20,
                                          color: colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Manual VIN Entry',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Type or paste a 17-character VIN to look up specs.',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextField(
                                      controller: _controller,
                                      focusNode: _focusNode,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      textInputAction: TextInputAction.search,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.3,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: '17-Character VIN',
                                        hintText: '1FM5K8GCXNGA77516',
                                        errorText: showValidationError
                                            ? validation.errorMessage
                                            : null,
                                        errorMaxLines: 2,
                                        suffixIcon: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            if (rawText.isNotEmpty)
                                              IconButton(
                                                tooltip: 'Clear VIN',
                                                onPressed: _controller.clear,
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                ),
                                              ),
                                            IconButton(
                                              tooltip: 'Paste from clipboard',
                                              onPressed: () => unawaited(
                                                _pasteFromClipboard(),
                                              ),
                                              icon: const Icon(
                                                Icons.content_paste_rounded,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      onSubmitted: (_) => _submit(),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            validVin != null
                                                ? 'Valid 17-character VIN ready'
                                                : 'Alphanumeric (no I, O, Q)',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                              color: validVin != null
                                                  ? colorScheme.primary
                                                  : colorScheme
                                                      .onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${normalized.length} / ${VinValidator.vinLength}',
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w700,
                                            color: validVin != null
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed:
                                          validVin != null ? _submit : null,
                                      icon: const Icon(Icons.search_rounded),
                                      label: const Text(
                                        'Look Up Vehicle Specs',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
