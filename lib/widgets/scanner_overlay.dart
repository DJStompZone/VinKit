import 'package:material_ui/material_ui.dart';

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = isPaused ? Colors.white60 : colorScheme.primary;
    final caption = isPaused
        ? 'Scanner paused'
        : (promptText ?? 'Align VIN barcode inside frame');

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
        if (statusMessage != null)
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
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    canvas.drawRRect(cutout, outlinePaint);

    if (showScanLine) {
      final linePaint = Paint()
        ..color = borderColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      final midY = scanWindow.center.dy;
      canvas.drawLine(
        Offset(scanWindow.left + 16, midY),
        Offset(scanWindow.right - 16, midY),
        linePaint,
      );
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
