import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/theme/app_theme.dart';

/// Branded startup splash overlay that seamlessly transitions out of the
/// native launch window with an animated VIN laser sweep across the VinKit
/// icon while the scanner initializes underneath.
class StartupSplashOverlay extends StatefulWidget {
  /// Creates a [StartupSplashOverlay].
  const StartupSplashOverlay({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 1150),
  });

  /// Invoked once the splash fade-out completes so the parent can unmount it.
  final VoidCallback onFinished;

  /// Total duration of the splash animation including fade-out.
  final Duration duration;

  @override
  State<StartupSplashOverlay> createState() => _StartupSplashOverlayState();
}

class _StartupSplashOverlayState extends State<StartupSplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconScale;
  late final Animation<double> _textOpacity;
  late final Animation<double> _scanProgress;
  late final Animation<double> _overlayOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _iconScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.36, curve: Curves.easeOutBack),
      ),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.14, 0.45, curve: Curves.easeOut),
      ),
    );
    _scanProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.18, 0.76, curve: Curves.easeInOut),
      ),
    );
    _overlayOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.76, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onFinished();
      }
    });
    unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = _overlayOpacity.value;
        return IgnorePointer(
          ignoring: opacity < 0.85,
          child: Opacity(
            opacity: opacity,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppTheme.splashBackground,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // Ambient brand corner glows echoing the VinKit gradient.
                  Positioned(
                    top: -90,
                    left: -80,
                    child: _AmbientGlow(
                      size: 300,
                      color: AppTheme.brandAmber.withValues(alpha: 0.22),
                    ),
                  ),
                  Positioned(
                    bottom: -110,
                    right: -90,
                    child: _AmbientGlow(
                      size: 340,
                      color: AppTheme.brandMagenta.withValues(alpha: 0.24),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Transform.scale(
                          scale: _iconScale.value,
                          child: _SplashIconBadge(
                            scanProgress: _scanProgress.value,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Opacity(
                          opacity: _textOpacity.value,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    AppTheme.brandGradient.createShader(bounds),
                                child: const Text(
                                  'VinKit',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    height: 1.05,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'VIN BARCODE  •  OCR  •  INSTANT SPECS',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.68),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
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
        );
      },
    );
  }
}

class _SplashIconBadge extends StatelessWidget {
  const _SplashIconBadge({required this.scanProgress});

  final double scanProgress;

  @override
  Widget build(BuildContext context) {
    const size = 112.0;
    final sweepVisible = scanProgress > 0.02 && scanProgress < 0.98;
    final lineY = 12.0 + (size - 24.0) * scanProgress;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.brandCoral.withValues(alpha: 0.42),
            blurRadius: 34,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: AppTheme.brandMagenta.withValues(alpha: 0.25),
            blurRadius: 52,
            offset: const Offset(10, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              'assets/images/vinkit_icon.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const DecoratedBox(
                decoration: BoxDecoration(gradient: AppTheme.brandGradient),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 54,
                  color: Colors.black,
                ),
              ),
            ),
            if (sweepVisible)
              Positioned(
                top: lineY,
                left: 6,
                right: 6,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                      colors: <Color>[
                        Color(0x00FFFFFF),
                        Color(0xFFFFF4D2),
                        Colors.white,
                        Color(0xFFFFF4D2),
                        Color(0x00FFFFFF),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppTheme.brandAmber.withValues(alpha: 0.9),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}
