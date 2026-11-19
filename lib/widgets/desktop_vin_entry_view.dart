import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/services/vin_validator.dart';

/// Full-screen desktop VIN lookup view shown on platforms where live camera
/// barcode scanning is unavailable (such as Windows and Linux).
///
/// Supports direct typing, clipboard pasting, and USB/Bluetooth keyboard-wedge
/// barcode scanners (including Code 39 leading `I` and `*` sentinels).
class DesktopVinEntryView extends StatefulWidget {
  /// Creates a [DesktopVinEntryView].
  const DesktopVinEntryView({
    super.key,
    required this.validator,
    required this.onSubmitVin,
    required this.themeMode,
    required this.onCycleThemeMode,
  });

  /// Validator used to normalize and validate VIN entries and barcode payloads.
  final VinValidator validator;

  /// Invoked with a validated 17-character VIN when submitted.
  final ValueChanged<String> onSubmitVin;

  /// Active application theme mode shown in the top bar toggle.
  final ThemeMode themeMode;

  /// Callback cycling between system, light, and dark themes.
  final VoidCallback onCycleThemeMode;

  @override
  State<DesktopVinEntryView> createState() => _DesktopVinEntryViewState();
}

class _DesktopVinEntryViewState extends State<DesktopVinEntryView> {
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
    return widget.validator.extractFromBarcode(raw);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (!mounted || raw == null || raw.trim().isEmpty) {
      return;
    }
    final extracted = widget.validator.extractFromBarcode(raw);
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
    _controller.clear();
    widget.onSubmitVin(validVin);
    _focusNode.requestFocus();
  }

  IconData _themeIconFor(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
      ThemeMode.system => Icons.brightness_auto_rounded,
    };
  }

  String _themeTooltipFor(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'Theme: Light (tap to switch)',
      ThemeMode.dark => 'Theme: Dark (tap to switch)',
      ThemeMode.system => 'Theme: System (tap to switch)',
    };
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
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

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.qr_code_scanner_rounded, size: 22),
            SizedBox(width: 8),
            Text(
              'VinKit',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: widget.onCycleThemeMode,
            tooltip: _themeTooltipFor(widget.themeMode),
            icon: Icon(_themeIconFor(widget.themeMode)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.directions_car_filled_rounded,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'VIN Spec Lookup',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Type, paste, or scan with a USB barcode scanner',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
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
                                icon: const Icon(Icons.close_rounded),
                              ),
                            IconButton(
                              tooltip: 'Paste from clipboard',
                              onPressed: _pasteFromClipboard,
                              icon: const Icon(Icons.content_paste_rounded),
                            ),
                          ],
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          validVin != null
                              ? 'Valid 17-character VIN ready'
                              : 'Alphanumeric (no I, O, Q)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: validVin != null
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${normalized.length} / ${VinValidator.vinLength}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: validVin != null
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: validVin != null ? _submit : null,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Look Up Vehicle Specs'),
                    ),
                    const SizedBox(height: 14),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Live camera scanning is available on Android, iOS, and macOS. Desktop mode supports keyboard, clipboard, and USB barcode scanners.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
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
          ),
        ),
      ),
    );
  }
}
