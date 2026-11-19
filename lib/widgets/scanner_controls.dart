import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Floating bottom camera HUD providing zoom controls, torch toggle,
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

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (supportsZoom) ...<Widget>[
                    Row(
                      children: <Widget>[
                        _ZoomPresetChip(
                          label: '1x',
                          selected: isOneXSelected,
                          enabled: isCameraRunning,
                          onTap: () => onZoomChanged(0.0),
                        ),
                        const SizedBox(width: 8),
                        _ZoomPresetChip(
                          label: '2x',
                          selected: isTwoXSelected,
                          enabled: isCameraRunning,
                          onTap: () => onZoomChanged(0.5),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: colorScheme.primary,
                              inactiveTrackColor:
                                  Colors.white.withValues(alpha: 0.24),
                              thumbColor: Colors.white,
                              overlayColor:
                                  colorScheme.primary.withValues(alpha: 0.24),
                            ),
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
                            minimumSize: const Size(52, 48),
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
                        const SizedBox(width: 10),
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
                            label: Text(primaryActionLabel!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: onManualEntryTap,
                          tooltip: 'Enter VIN Manually',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(52, 48),
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

class _ZoomPresetChip extends StatelessWidget {
  const _ZoomPresetChip({
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: enabled
                  ? (selected ? colorScheme.onPrimary : Colors.white)
                  : Colors.white38,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
