import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/services/vin_frame_assembler.dart';
import 'package:vinkit_app/theme/app_theme.dart';

/// Renders a semi-transparent scanner mask with a horizontal VIN cutout,
/// corner reticles, prompt pill, and optional status banner over the camera preview.
class ScannerOverlay extends StatelessWidget {
  /// Creates a [ScannerOverlay] aligned with [scanWindow].
  const ScannerOverlay({
    super.key,
    required this.scanWindow,
    required this.isPaused,
    this.promptText,
    this.showScanLine = true,
    this.statusMessage,
    this.statusIsError = true,
    this.statusActionLabel,
    this.onStatusAction,
    this.assemblyProgress,
    this.onResetAssembly,
    this.onEditAssembly,
  });

  /// Coordinates of the transparent detection/alignment region.
  final Rect scanWindow;

  /// Whether scanning is currently paused while showing results.
  final bool isPaused;

  /// Optional caption displayed above the cutout.
  final String? promptText;

  /// Whether to draw the center horizontal laser alignment line.
  final bool showScanLine;

  /// Optional transient status or feedback message shown beneath the cutout.
  final String? statusMessage;

  /// Whether [statusMessage] should be styled as an error banner (`true`) or
  /// neutral informational banner (`false`).
  final bool statusIsError;

  /// Optional quick-action button label inside the status banner.
  final String? statusActionLabel;

  /// Callback invoked when the status banner's quick-action button is tapped.
  final VoidCallback? onStatusAction;

  /// Optional live multi-frame OCR VIN assembly progress strip shown beneath
  /// the cutout while piecing together glare-obstructed fragments.
  final VinAssemblyProgress? assemblyProgress;

  /// Callback invoked to clear the active multi-frame OCR assembly buffer.
  final VoidCallback? onResetAssembly;

  /// Callback invoked to open manual entry prefilled with assembled characters.
  final ValueChanged<String>? onEditAssembly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = isPaused ? Colors.white60 : colorScheme.primary;
    final caption = isPaused
        ? 'Scanner paused'
        : (promptText ?? 'Align VIN barcode inside frame');
    final showAssemblyStrip = !isPaused && assemblyProgress != null;

    return Stack(
      children: <Widget>[
        IgnorePointer(
          child: CustomPaint(
            painter: ScannerOverlayPainter(
              scanWindow: scanWindow,
              borderColor: accentColor,
              showScanLine: showScanLine && !isPaused,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: (scanWindow.top - 44).clamp(16.0, double.infinity),
          left: 20,
          right: 20,
          child: IgnorePointer(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.66),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Text(
                    caption,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showAssemblyStrip)
          Positioned(
            top: scanWindow.bottom + 14,
            left: 16,
            right: 16,
            child: Center(
              child: _VinAssemblyStrip(
                progress: assemblyProgress!,
                accentColor: colorScheme.primary,
                onReset: onResetAssembly,
                onEdit: onEditAssembly,
              ),
            ),
          )
        else if (statusMessage != null)
          Positioned(
            top: scanWindow.bottom + 14,
            left: 20,
            right: 20,
            child: Center(
              child: Material(
                color: statusIsError
                    ? colorScheme.errorContainer.withValues(alpha: 0.95)
                    : Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          statusMessage!,
                          style: TextStyle(
                            color: statusIsError
                                ? colorScheme.onErrorContainer
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (statusActionLabel != null &&
                          onStatusAction != null) ...<Widget>[
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: onStatusAction,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: statusIsError
                                ? colorScheme.onErrorContainer
                                    .withValues(alpha: 0.14)
                                : colorScheme.primary.withValues(alpha: 0.28),
                            foregroundColor: statusIsError
                                ? colorScheme.onErrorContainer
                                : Colors.white,
                          ),
                          child: Text(
                            statusActionLabel!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VinAssemblyStrip extends StatelessWidget {
  const _VinAssemblyStrip({
    required this.progress,
    required this.accentColor,
    this.onReset,
    this.onEdit,
  });

  final VinAssemblyProgress progress;
  final Color accentColor;
  final VoidCallback? onReset;
  final ValueChanged<String>? onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.80),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Assembling VIN (${progress.filledCount}/17)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                if (onEdit != null &&
                    progress.bestPartialText.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => onEdit!(progress.bestPartialText),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: accentColor.withValues(alpha: 0.24),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (onReset != null) ...<Widget>[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: onReset,
                    tooltip: 'Clear assembled VIN',
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    icon: Icon(
                      Icons.refresh_rounded,
                      size: 15,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(17, (index) {
                  final char = progress.slots[index];
                  final isConfirmed = progress.confirmedSlots[index];
                  final hasChar = char != null;
                  return Container(
                    width: 17,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isConfirmed
                          ? accentColor.withValues(alpha: 0.28)
                          : hasChar
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isConfirmed
                            ? accentColor.withValues(alpha: 0.75)
                            : hasChar
                                ? Colors.white.withValues(alpha: 0.28)
                                : Colors.white.withValues(alpha: 0.12),
                        width: 0.9,
                      ),
                    ),
                    child: Text(
                      char ?? '_',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight:
                            isConfirmed ? FontWeight.w800 : FontWeight.w600,
                        color: isConfirmed
                            ? Colors.white
                            : hasChar
                                ? Colors.white.withValues(alpha: 0.78)
                                : Colors.white.withValues(alpha: 0.30),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the darkened mask, rounded rectangular cutout, corner brackets, and
/// optional horizontal laser alignment guide for [ScannerOverlay].
class ScannerOverlayPainter extends CustomPainter {
  /// Creates a [ScannerOverlayPainter] for the given [scanWindow].
  const ScannerOverlayPainter({
    required this.scanWindow,
    required this.borderColor,
    required this.showScanLine,
  });

  /// Region left transparent for VIN alignment.
  final Rect scanWindow;

  /// Color used for corner brackets and alignment accents.
  final Color borderColor;

  /// Whether to paint the center horizontal alignment guide.
  final bool showScanLine;

  static const double _cornerRadius = 14;
  static const double _bracketLength = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = RRect.fromRectAndRadius(
      scanWindow,
      const Radius.circular(_cornerRadius),
    );

    final maskPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(cutout)
      ..fillType = PathFillType.evenOdd;

    final maskPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.62)
      ..style = PaintingStyle.fill;
    canvas.drawPath(maskPath, maskPaint);

    final outlinePaint = Paint()
      ..shader = AppTheme.brandGradient.createShader(scanWindow)
      ..colorFilter = ColorFilter.mode(
        Colors.white.withValues(alpha: showScanLine ? 0.65 : 0.42),
        BlendMode.modulate,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(cutout, outlinePaint);

    if (showScanLine) {
      final midY = scanWindow.center.dy;
      final lineStart = Offset(scanWindow.left + 16, midY);
      final lineEnd = Offset(scanWindow.right - 16, midY);
      final lineRect = Rect.fromLTRB(
        lineStart.dx,
        midY - 2,
        lineEnd.dx,
        midY + 2,
      );
      final glowPaint = Paint()
        ..shader = AppTheme.brandGradient.createShader(lineRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
      canvas.drawLine(lineStart, lineEnd, glowPaint);

      final linePaint = Paint()
        ..shader = AppTheme.brandGradient.createShader(lineRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(lineStart, lineEnd, linePaint);
    }

    final bracketPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final left = scanWindow.left;
    final top = scanWindow.top;
    final right = scanWindow.right;
    final bottom = scanWindow.bottom;

    final bracketPath = Path()
      ..moveTo(left, top + _bracketLength)
      ..lineTo(left, top + _cornerRadius)
      ..quadraticBezierTo(left, top, left + _cornerRadius, top)
      ..lineTo(left + _bracketLength, top)
      ..moveTo(right - _bracketLength, top)
      ..lineTo(right - _cornerRadius, top)
      ..quadraticBezierTo(right, top, right, top + _cornerRadius)
      ..lineTo(right, top + _bracketLength)
      ..moveTo(right, bottom - _bracketLength)
      ..lineTo(right, bottom - _cornerRadius)
      ..quadraticBezierTo(right, bottom, right - _cornerRadius, bottom)
      ..lineTo(right - _bracketLength, bottom)
      ..moveTo(left + _bracketLength, bottom)
      ..lineTo(left + _cornerRadius, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - _cornerRadius)
      ..lineTo(left, bottom - _bracketLength);

    canvas.drawPath(bracketPath, bracketPaint);
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.showScanLine != showScanLine;
  }
}
