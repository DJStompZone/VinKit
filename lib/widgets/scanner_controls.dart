import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vinkit_app/theme/app_theme.dart';

/// Floating bottom camera HUD providing zoom controls, torch toggle,
/// optional collapsible Exposure (EV) & Gamma lighting controls,
/// optional OCR capture trigger, and manual VIN entry button.
class ScannerControls extends StatelessWidget {
  /// Creates a [ScannerControls] bar.
  const ScannerControls({
    super.key,
    required this.zoomScale,
    required this.torchState,
    required this.isCameraRunning,
    required this.onZoomChanged,
    required this.onToggleTorch,
    required this.onManualEntryTap,
    this.supportsZoom = true,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryActionTap,
    this.isPrimaryBusy = false,
    this.showLightingControls = false,
    this.isLightingExpanded = false,
    this.onToggleLightingPanel,
    this.supportsExposureOffset = false,
    this.exposureOffset = 0.0,
    this.minExposureOffset = -2.0,
    this.maxExposureOffset = 2.0,
    this.onExposureChanged,
    this.gamma = 1.0,
    this.onGammaChanged,
    this.onResetLighting,
    this.onApplyLightingPreset,
  });

  /// Normalized linear zoom scale between `0.0` (`1x`) and `1.0`.
  final double zoomScale;

  /// Current hardware torch state.
  final TorchState torchState;

  /// Whether the camera preview is currently active.
  final bool isCameraRunning;

  /// Whether camera zoom controls are supported on the active platform.
  final bool supportsZoom;

  /// Invoked when the user adjusts the zoom slider or selects a zoom preset.
  final ValueChanged<double> onZoomChanged;

  /// Invoked when the user taps the flashlight toggle button.
  final VoidCallback onToggleTorch;

  /// Invoked when the user taps the manual VIN entry trigger.
  final VoidCallback onManualEntryTap;

  /// Optional primary capture action label (used in OCR mode).
  final String? primaryActionLabel;

  /// Optional icon for the primary capture action.
  final IconData? primaryActionIcon;

  /// Invoked when the optional primary action button is tapped.
  final VoidCallback? onPrimaryActionTap;

  /// Whether the primary action button is currently busy running inference.
  final bool isPrimaryBusy;

  /// Whether to expose the Exposure/Gamma lighting toggle button and panel.
  final bool showLightingControls;

  /// Whether the collapsible Exposure/Gamma lighting panel is expanded.
  final bool isLightingExpanded;

  /// Invoked when the user toggles the lighting panel.
  final VoidCallback? onToggleLightingPanel;

  /// Whether hardware exposure compensation (`EV`) is supported by the lens.
  final bool supportsExposureOffset;

  /// Current exposure compensation offset in EV stops.
  final double exposureOffset;

  /// Minimum supported exposure compensation in EV stops.
  final double minExposureOffset;

  /// Maximum supported exposure compensation in EV stops.
  final double maxExposureOffset;

  /// Invoked when the user drags the exposure slider.
  final ValueChanged<double>? onExposureChanged;

  /// Current gamma curve value (`0.45..2.0`, default `1.0`).
  final double gamma;

  /// Invoked when the user drags the gamma slider.
  final ValueChanged<double>? onGammaChanged;

  /// Invoked when the user resets Exposure and Gamma back to neutral.
  final VoidCallback? onResetLighting;

  /// Invoked when the user taps a quick lighting preset (`ev`, `gamma`).
  final void Function(double ev, double gamma)? onApplyLightingPreset;

  bool get _hasCustomLighting =>
      exposureOffset.abs() >= 0.05 || (gamma - 1.0).abs() >= 0.03;

  String _formatEv(double ev) {
    if (ev.abs() < 0.05) {
      return '0.0';
    }
    final sign = ev > 0 ? '+' : '';
    return '$sign${ev.toStringAsFixed(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final clampedZoom = zoomScale.clamp(0.0, 1.0);
    final isOneXSelected = clampedZoom < 0.25;
    final isTwoXSelected = clampedZoom >= 0.45 && clampedZoom <= 0.65;
    final torchAvailable =
        isCameraRunning && torchState != TorchState.unavailable;
    final isTorchOn = torchState == TorchState.on;
    final hasPrimaryAction = primaryActionLabel != null;

    final hasValidExposureRange =
        supportsExposureOffset && maxExposureOffset > minExposureOffset + 0.05;
    final clampedEv = hasValidExposureRange
        ? exposureOffset.clamp(minExposureOffset, maxExposureOffset)
        : 0.0;
    final clampedGamma = gamma.clamp(0.45, 2.0);

    final isAutoPreset = !_hasCustomLighting;
    final isGlarePreset =
        (clampedGamma - 0.75).abs() <= 0.08 &&
        (!hasValidExposureRange || clampedEv <= -0.6);
    final isDarkPreset =
        (clampedGamma - 1.45).abs() <= 0.12 &&
        (!hasValidExposureRange || clampedEv >= 0.6);

    final compactSliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: 3,
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.24),
      thumbColor: Colors.white,
      overlayColor: colorScheme.primary.withValues(alpha: 0.24),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.76),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _hasCustomLighting
                    ? AppTheme.brandAmber.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (showLightingControls && isLightingExpanded) ...<Widget>[
                    _LightingAdjustmentPanel(
                      sliderTheme: compactSliderTheme,
                      isCameraRunning: isCameraRunning,
                      hasCustomLighting: _hasCustomLighting,
                      isAutoPreset: isAutoPreset,
                      isGlarePreset: isGlarePreset,
                      isDarkPreset: isDarkPreset,
                      hasValidExposureRange: hasValidExposureRange,
                      exposureOffset: clampedEv,
                      minExposureOffset: minExposureOffset,
                      maxExposureOffset: maxExposureOffset,
                      exposureLabel: '${_formatEv(clampedEv)} EV',
                      gamma: clampedGamma,
                      onExposureChanged: onExposureChanged,
                      onGammaChanged: onGammaChanged,
                      onResetLighting: onResetLighting,
                      onApplyLightingPreset: onApplyLightingPreset,
                    ),
                    Divider(
                      height: 16,
                      thickness: 1,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ],
                  if (supportsZoom) ...<Widget>[
                    Row(
                      children: <Widget>[
                        _HudChip(
                          label: '1x',
                          selected: isOneXSelected,
                          enabled: isCameraRunning,
                          onTap: () => onZoomChanged(0.0),
                        ),
                        const SizedBox(width: 8),
                        _HudChip(
                          label: '2x',
                          selected: isTwoXSelected,
                          enabled: isCameraRunning,
                          onTap: () => onZoomChanged(0.5),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: compactSliderTheme,
                            child: Slider(
                              value: clampedZoom,
                              min: 0.0,
                              max: 1.0,
                              onChanged: isCameraRunning ? onZoomChanged : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: <Widget>[
                      if (supportsZoom || torchAvailable) ...<Widget>[
                        IconButton.filledTonal(
                          onPressed: torchAvailable ? onToggleTorch : null,
                          tooltip: torchAvailable
                              ? (isTorchOn
                                  ? 'Turn flashlight off'
                                  : 'Turn flashlight on')
                              : 'Flashlight unavailable',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            backgroundColor: isTorchOn
                                ? colorScheme.primary
                                : Colors.white.withValues(alpha: 0.14),
                            foregroundColor: isTorchOn
                                ? colorScheme.onPrimary
                                : Colors.white,
                            disabledBackgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            disabledForegroundColor: Colors.white38,
                          ),
                          icon: Icon(
                            switch (torchState) {
                              TorchState.on => Icons.flashlight_on_rounded,
                              TorchState.unavailable => Icons.flash_off_rounded,
                              TorchState.off ||
                              TorchState.auto =>
                                Icons.flashlight_off_rounded,
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (showLightingControls) ...<Widget>[
                        Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            IconButton.filledTonal(
                              onPressed: onToggleLightingPanel,
                              tooltip: isLightingExpanded
                                  ? 'Hide exposure & gamma controls'
                                  : 'Adjust exposure & gamma',
                              style: IconButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                backgroundColor: isLightingExpanded
                                    ? colorScheme.primary
                                    : (_hasCustomLighting
                                        ? AppTheme.brandAmber
                                            .withValues(alpha: 0.28)
                                        : Colors.white
                                            .withValues(alpha: 0.14)),
                                foregroundColor: isLightingExpanded
                                    ? colorScheme.onPrimary
                                    : Colors.white,
                              ),
                              icon: const Icon(Icons.exposure_rounded),
                            ),
                            if (_hasCustomLighting && !isLightingExpanded)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.brandAmber,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (hasPrimaryAction) ...<Widget>[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                isPrimaryBusy ? null : onPrimaryActionTap,
                            icon: isPrimaryBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Icon(
                                    primaryActionIcon ??
                                        Icons.document_scanner_rounded,
                                  ),
                            label: Text(
                              primaryActionLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: onManualEntryTap,
                          tooltip: 'Enter VIN Manually',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.14),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.keyboard_alt_outlined),
                        ),
                      ] else
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onManualEntryTap,
                            icon: const Icon(Icons.keyboard_alt_outlined),
                            label: const Text('Enter VIN Manually'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LightingAdjustmentPanel extends StatelessWidget {
  const _LightingAdjustmentPanel({
    required this.sliderTheme,
    required this.isCameraRunning,
    required this.hasCustomLighting,
    required this.isAutoPreset,
    required this.isGlarePreset,
    required this.isDarkPreset,
    required this.hasValidExposureRange,
    required this.exposureOffset,
    required this.minExposureOffset,
    required this.maxExposureOffset,
    required this.exposureLabel,
    required this.gamma,
    required this.onExposureChanged,
    required this.onGammaChanged,
    required this.onResetLighting,
    required this.onApplyLightingPreset,
  });

  final SliderThemeData sliderTheme;
  final bool isCameraRunning;
  final bool hasCustomLighting;
  final bool isAutoPreset;
  final bool isGlarePreset;
  final bool isDarkPreset;
  final bool hasValidExposureRange;
  final double exposureOffset;
  final double minExposureOffset;
  final double maxExposureOffset;
  final String exposureLabel;
  final double gamma;
  final ValueChanged<double>? onExposureChanged;
  final ValueChanged<double>? onGammaChanged;
  final VoidCallback? onResetLighting;
  final void Function(double ev, double gamma)? onApplyLightingPreset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  _HudChip(
                    label: 'Auto',
                    selected: isAutoPreset,
                    enabled: true,
                    onTap: () => onApplyLightingPreset?.call(0.0, 1.0),
                  ),
                  _HudChip(
                    label: 'Glare',
                    selected: isGlarePreset,
                    enabled: true,
                    onTap: () => onApplyLightingPreset?.call(-1.2, 0.75),
                  ),
                  _HudChip(
                    label: 'Dark',
                    selected: isDarkPreset,
                    enabled: true,
                    onTap: () => onApplyLightingPreset?.call(1.2, 1.45),
                  ),
                ],
              ),
            ),
            if (hasCustomLighting && onResetLighting != null)
              TextButton(
                onPressed: onResetLighting,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.brandAmber,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Reset',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        if (hasValidExposureRange) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const SizedBox(
                width: 52,
                child: Text(
                  'EV',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: sliderTheme,
                  child: Slider(
                    value: exposureOffset,
                    min: minExposureOffset,
                    max: maxExposureOffset,
                    onChanged: isCameraRunning ? onExposureChanged : null,
                  ),
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  exposureLabel,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            const SizedBox(
              width: 52,
              child: Text(
                'Gamma',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: sliderTheme,
                child: Slider(
                  value: gamma,
                  min: 0.45,
                  max: 2.0,
                  onChanged: onGammaChanged,
                ),
              ),
            ),
            SizedBox(
              width: 54,
              child: Text(
                'γ ${gamma.toStringAsFixed(2)}',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colorScheme.primary
          : Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: enabled
                  ? (selected ? colorScheme.onPrimary : Colors.white)
                  : Colors.white38,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
