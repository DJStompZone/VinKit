import 'package:material_ui/material_ui.dart';

/// Renders a semi-transparent scanner mask with a horizontal barcode cutout,
/// corner reticles, and status caption over the camera preview.
class ScannerOverlay extends StatelessWidget {
  /// Creates a [ScannerOverlay] aligned with [scanWindow].
  const ScannerOverlay({
    super.key,
    required this.scanWindow,
    required this.isPaused,
    this.statusMessage,
  });

  /// Coordinates of the transparent barcode detection region.
  final Rect scanWindow;

  /// Whether barcode scanning is currently paused while showing results.
  final bool isPaused;

  /// Optional transient status or feedback message shown beneath the cutout.
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = isPaused ? Colors.white60 : colorScheme.primary;

    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          CustomPaint(
            painter: ScannerOverlayPainter(
              scanWindow: scanWindow,
              borderColor: accentColor,
              showScanLine: !isPaused,
            ),
            child: const SizedBox.expand(),
          ),
          Positioned(
            top: (scanWindow.top - 44).clamp(16.0, double.infinity),
            left: 24,
            right: 24,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
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
                    isPaused
                        ? 'Scanner paused'
                        : 'Align Code 39 / Code 128 VIN barcode',
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
          if (statusMessage != null)
            Positioned(
              top: scanWindow.bottom + 14,
              left: 24,
              right: 24,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      statusMessage!,
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the darkened mask, rounded rectangular cutout, corner brackets, and
/// horizontal laser alignment guide for [ScannerOverlay].
class ScannerOverlayPainter extends CustomPainter {
  /// Creates a [ScannerOverlayPainter] for the given [scanWindow].
  const ScannerOverlayPainter({
    required this.scanWindow,
    required this.borderColor,
    required this.showScanLine,
  });

  /// Region left transparent for barcode alignment.
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
