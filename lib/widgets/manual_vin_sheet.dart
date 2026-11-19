import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/services/vin_validator.dart';

/// Modal bottom sheet allowing users to type or paste a 17-character VIN
/// with live validation before initiating a lookup.
class ManualVinSheet extends StatefulWidget {
  /// Creates a [ManualVinSheet].
  const ManualVinSheet({
    super.key,
    this.validator = const VinValidator(),
    this.initialVin,
  });

  /// Validator used for normalizing and validating manual input.
  final VinValidator validator;

  /// Optional prefilled VIN string.
  final String? initialVin;

  @override
  State<ManualVinSheet> createState() => _ManualVinSheetState();
}

class _ManualVinSheetState extends State<ManualVinSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialVin == null
        ? ''
        : widget.validator.normalizeManualInput(widget.initialVin!);
    _controller = TextEditingController(text: initial);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (!mounted || raw == null || raw.trim().isEmpty) {
      return;
    }
    final normalized = widget.validator.normalizeManualInput(raw);
    _controller.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  void _submit() {
    final validation = widget.validator.validate(_controller.text);
    if (!validation.isValid) {
      return;
    }
    Navigator.of(context).pop(validation.normalizedVin);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final normalized = widget.validator.normalizeManualInput(_controller.text);
    final validation = widget.validator.validate(normalized);
    final showValidationError = normalized.isNotEmpty && !validation.isValid;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Enter VIN Manually',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Type or paste a 17-character Vehicle Identification Number (letters I, O, and Q are not used).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: <TextInputFormatter>[
                _VinTextInputFormatter(widget.validator),
              ],
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
              decoration: InputDecoration(
                labelText: '17-Character VIN',
                hintText: '1FM5K8GCXNGA77516',
                errorText: showValidationError ? validation.errorMessage : null,
                errorMaxLines: 2,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (normalized.isNotEmpty)
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
                  validation.isValid
                      ? 'Valid 17-character VIN'
                      : 'Alphanumeric (no I, O, Q)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: validation.isValid
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${normalized.length} / ${VinValidator.vinLength}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: validation.isValid
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: validation.isValid ? _submit : null,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Look Up Vehicle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VinTextInputFormatter extends TextInputFormatter {
  const _VinTextInputFormatter(this.validator);

  final VinValidator validator;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = validator.normalizeManualInput(newValue.text);
    final rawCursor = newValue.selection.extentOffset.clamp(
      0,
      newValue.text.length,
    );
    final normalizedCursor =
        validator.normalizeManualInput(newValue.text.substring(0, rawCursor)).length;

    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(
        offset: normalizedCursor.clamp(0, normalized.length),
      ),
    );
  }
}
