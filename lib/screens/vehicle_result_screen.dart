import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/models/json_parsers.dart';
import 'package:vinkit_app/models/oil_spec.dart';
import 'package:vinkit_app/models/vehicle_part.dart';
import 'package:vinkit_app/models/vehicle_service_item.dart';
import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/models/vin_lookup_result.dart';
import 'package:vinkit_app/models/vin_lookup_state.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';

/// Action returned when leaving [VehicleResultScreen].
enum VehicleResultAction {
  /// Return to the live barcode scanner for the next vehicle.
  scanNext,

  /// Return and open the manual VIN entry sheet.
  enterDifferentVin,
}

/// Full-screen, high-density vehicle specification sheet shown immediately
/// upon capturing a valid VIN.
///
/// Prioritizes immediate above-the-fold legibility for Year, Make, Model,
/// Engine, VIN, Recommended Oil, Filters, and Wiper Blades, followed by
/// exhaustive battery, oil options, fluids/services, and catalog match details.
class VehicleResultScreen extends StatelessWidget {
  /// Creates a [VehicleResultScreen] driven by [controller].
  const VehicleResultScreen({
    super.key,
    required this.controller,
    this.onScanNext,
    this.onEnterDifferentVin,
  });

  /// Controller orchestrating the active VIN lookup lifecycle.
  final VinLookupController controller;

  /// Optional override invoked when requesting to scan the next vehicle.
  final VoidCallback? onScanNext;

  /// Optional override invoked when requesting manual VIN entry.
  final VoidCallback? onEnterDifferentVin;

  void _handleScanNext(BuildContext context) {
    if (onScanNext != null) {
      onScanNext!();
    } else {
      Navigator.of(context).pop(VehicleResultAction.scanNext);
    }
  }

  void _handleEnterDifferentVin(BuildContext context) {
    if (onEnterDifferentVin != null) {
      onEnterDifferentVin!();
    } else {
      Navigator.of(context).pop(VehicleResultAction.enterDifferentVin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final result = state is VinLookupSuccess ? state.result : null;

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 50,
            titleSpacing: 0,
            leading: IconButton(
              onPressed: () => _handleScanNext(context),
              tooltip: 'Back to Scanner',
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: Text(
              result != null ? 'Vehicle Spec Sheet' : 'VIN Lookup',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            actions: <Widget>[
              if (result != null)
                _CopyAllActionButton(summaryText: result.toPlainTextSummary()),
              IconButton(
                onPressed: () => _handleEnterDifferentVin(context),
                tooltip: 'Enter Different VIN',
                icon: const Icon(Icons.keyboard_alt_outlined),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: switch (state) {
            VinLookupIdle() => _LoadingSpecView(
                vin: controller.lastVin ?? '',
              ),
            VinLookupLoading(:final vin) => _LoadingSpecView(vin: vin),
            VinLookupFailure(:final vin, :final error) => _ErrorSpecView(
                vin: vin,
                error: error,
                onRetry: error.isRetryable
                    ? () => unawaited(controller.retry())
                    : null,
                onEnterDifferentVin: () => _handleEnterDifferentVin(context),
              ),
            VinLookupSuccess(:final result) => _VehicleSpecBody(result: result),
          },
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.7),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: FilledButton.icon(
                onPressed: () => _handleScanNext(context),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text(
                  'Scan Next Vehicle',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CopyAllActionButton extends StatefulWidget {
  const _CopyAllActionButton({required this.summaryText});

  final String summaryText;

  @override
  State<_CopyAllActionButton> createState() => _CopyAllActionButtonState();
}

class _CopyAllActionButtonState extends State<_CopyAllActionButton> {
  bool _copied = false;
  Timer? _resetTimer;

  Future<void> _copySummary() async {
    await Clipboard.setData(ClipboardData(text: widget.summaryText));
    await HapticFeedback.lightImpact();
    _resetTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Copied vehicle spec summary to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _copySummary,
      tooltip: _copied ? 'Specs Copied' : 'Copy All Specs',
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_all_rounded,
      ),
    );
  }
}

class _LoadingSpecView extends StatelessWidget {
  const _LoadingSpecView({required this.vin});

  final String vin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Loading Vehicle Specifications',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            if (vin.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _InlineVinStrip(vin: vin),
            ],
            const SizedBox(height: 12),
            Text(
              'Fetching year, make, model, recommended oil, filters, wipers, battery, and fluid specs...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorSpecView extends StatelessWidget {
  const _ErrorSpecView({
    required this.vin,
    required this.error,
    required this.onRetry,
    required this.onEnterDifferentVin,
  });

  final String vin;
  final VinLookupException error;
  final VoidCallback? onRetry;
  final VoidCallback onEnterDifferentVin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (IconData icon, String title) = switch (error.kind) {
      VinLookupErrorKind.network => (
          Icons.wifi_off_rounded,
          'No Network Connection',
        ),
      VinLookupErrorKind.timeout => (
          Icons.schedule_rounded,
          'Request Timed Out',
        ),
      VinLookupErrorKind.notFound => (
          Icons.search_off_rounded,
          'Vehicle Not Found',
        ),
      VinLookupErrorKind.invalidVin => (
          Icons.warning_amber_rounded,
          'Invalid VIN',
        ),
      VinLookupErrorKind.serverError => (
          Icons.cloud_off_rounded,
          'VIN Server Error',
        ),
      VinLookupErrorKind.parseError || VinLookupErrorKind.unknown => (
          Icons.error_outline_rounded,
          'Lookup Failed',
        ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      children: <Widget>[
        Center(
          child: CircleAvatar(
            radius: 34,
            backgroundColor: colorScheme.errorContainer,
            foregroundColor: colorScheme.onErrorContainer,
            child: Icon(icon, size: 34),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          error.message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (vin.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          _InlineVinStrip(vin: vin),
        ],
        const SizedBox(height: 22),
        if (onRetry != null) ...<Widget>[
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry Lookup'),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: onEnterDifferentVin,
          icon: const Icon(Icons.keyboard_alt_outlined),
          label: const Text('Enter Different VIN'),
        ),
      ],
    );
  }
}

class _VehicleSpecBody extends StatelessWidget {
  const _VehicleSpecBody({required this.result});

  final VinLookupResult result;

  @override
  Widget build(BuildContext context) {
    final otherCategories = result.otherPartCategories;
    final groupedServices = result.servicesByName;
    final hasDetailedOilSection = result.oilSpecs.length > 1;
    final hasMatchMetadata = result.matchedPartsVehicle != null ||
        result.vfMatches.isNotEmpty ||
        result.uniqueSources.isNotEmpty ||
        (result.vehicle.id != null && result.vehicle.id! > 0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 20),
      children: <Widget>[
        // 1. Primary Identity: Year, Make, Model, Trim, Engine, VIN
        _VehicleIdentityBanner(result: result),
        const SizedBox(height: 8),

        // 2. Recommended Engine Oil (Immediately visible above the fold)
        _RecommendedOilBanner(result: result),
        const SizedBox(height: 8),

        // 3. Filters Spec Table (Oil, Engine Air, Cabin Air, Fuel)
        _FiltersSpecCard(result: result),
        const SizedBox(height: 8),

        // 4. Wiper Blades Spec Table (Driver, Passenger, Rear + lengths/connectors)
        _WipersSpecCard(result: result),

        // 5. Battery & Any Additional Part Categories
        for (final category in otherCategories) ...<Widget>[
          const SizedBox(height: 10),
          if (category == 'battery')
            _BatterySpecCard(parts: result.partsByCategory[category]!)
          else
            _GenericPartCategoryCard(
              category: category,
              parts: result.partsByCategory[category]!,
            ),
        ],

        // 6. Full Oil Options Breakdown (when multiple formulations/grades exist)
        if (hasDetailedOilSection) ...<Widget>[
          const SizedBox(height: 10),
          _AllOilOptionsCard(specs: result.oilSpecs),
        ],

        // 7. Fluids & Maintenance Services (with parsed copyable fluid codes)
        if (groupedServices.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _FluidsServicesCard(groupedServices: groupedServices),
        ],

        // 8. Complete Powertrain, Catalog Match & Source Details
        if (hasMatchMetadata) ...<Widget>[
          const SizedBox(height: 10),
          _CatalogAndPowertrainCard(result: result),
        ],
      ],
    );
  }
}

class _VehicleIdentityBanner extends StatelessWidget {
  const _VehicleIdentityBanner({required this.result});

  final VinLookupResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final vehicle = result.vehicle;
    final primaryMatch =
        result.vfMatches.isNotEmpty ? result.vfMatches.first : null;

    final yearText =
        vehicle.year != null && vehicle.year! > 0 ? '${vehicle.year}' : '';
    final makeModelTokens = <String>[
      if (yearText.isNotEmpty) yearText,
      if (vehicle.make.isNotEmpty) vehicle.make,
      if (vehicle.model.isNotEmpty) vehicle.model,
    ];
    final headline = makeModelTokens.isEmpty
        ? vehicle.displayTitle
        : makeModelTokens.join(' ');

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(
                      headline,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (vehicle.trim.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          vehicle.trim,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (vehicle.engine.isNotEmpty ||
              (primaryMatch != null &&
                  primaryMatch.engineRaw.isNotEmpty)) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(
                  Icons.engineering_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    vehicle.engine.isNotEmpty
                        ? vehicle.engine
                        : primaryMatch!.engineRaw,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          _InlineVinStrip(vin: result.vin),
        ],
      ),
    );
  }
}

class _InlineVinStrip extends StatelessWidget {
  const _InlineVinStrip({required this.vin});

  final String vin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      padding: const EdgeInsets.only(left: 10, right: 4, top: 2, bottom: 2),
      child: Row(
        children: <Widget>[
          Text(
            'VIN',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              vin,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          _CompactCopyTextButton(valueToCopy: vin),
        ],
      ),
    );
  }
}

class _RecommendedOilBanner extends StatelessWidget {
  const _RecommendedOilBanner({required this.result});

  final VinLookupResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viscosities = result.oilViscosities;
    final capacities = result.oilCapacities;
    final types = result.oilTypeLabels;
    final singleSpec =
        result.oilSpecs.length == 1 ? result.oilSpecs.first : null;
    final hasAnyOil = viscosities.isNotEmpty ||
        capacities.isNotEmpty ||
        result.oilSpecs.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.opacity_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'RECOMMENDED OIL',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (result.oilSpecs.length > 1)
                Text(
                  '${result.oilSpecs.length} options below',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (!hasAnyOil)
            Text(
              'No engine oil specification returned for this VIN.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else ...<Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                for (final grade in viscosities)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      grade,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onPrimary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                for (final cap in capacities)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      cap,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
            if (types.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                types.join(' • '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
            if (singleSpec != null && singleSpec.specNotes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                singleSpec.specNotes,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _FiltersSpecCard extends StatelessWidget {
  const _FiltersSpecCard({required this.result});

  final VinLookupResult result;

  static const Map<String, String> _compactLabels = <String, String>{
    'oil_filter': 'Oil Filter',
    'air_filter': 'Engine Air',
    'cabin_filter': 'Cabin Air',
    'fuel_filter': 'Fuel Filter',
  };

  IconData _iconFor(String category) {
    return switch (category) {
      'oil_filter' => Icons.oil_barrel_outlined,
      'air_filter' => Icons.air_rounded,
      'cabin_filter' => Icons.hvac_rounded,
      'fuel_filter' => Icons.local_gas_station_outlined,
      _ => Icons.filter_alt_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filterCategories = result.orderedFilterCategories;

    return _SpecSectionCard(
      icon: Icons.filter_alt_rounded,
      title: 'FILTERS',
      trailing: filterCategories.isNotEmpty
          ? '${filterCategories.length} listed'
          : null,
      child: filterCategories.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No filter catalog data returned for this VIN.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: <Widget>[
                for (var i = 0; i < filterCategories.length; i++) ...<Widget>[
                  _FilterCategoryRow(
                    icon: _iconFor(filterCategories[i]),
                    label: _compactLabels[filterCategories[i]] ??
                        VehiclePart.labelForCategory(filterCategories[i]),
                    parts: result.partsByCategory[filterCategories[i]]!,
                  ),
                  if (i < filterCategories.length - 1)
                    const Divider(height: 12),
                ],
              ],
            ),
    );
  }
}

class _FilterCategoryRow extends StatelessWidget {
  const _FilterCategoryRow({
    required this.icon,
    required this.label,
    required this.parts,
  });

  final IconData icon;
  final String label;
  final List<VehiclePart> parts;

  String _usefulDetailFor(VehiclePart part) {
    final labelLower = label.toLowerCase();
    final useful = part.detailSegments.where((seg) {
      final lower = seg.toLowerCase();
      return lower != labelLower &&
          lower != 'engine oil filter' &&
          lower != 'engine air filter' &&
          lower != 'cabin air filter' &&
          lower != 'fuel filter';
    }).toList();
    return useful.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 108,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < parts.length; i++) ...<Widget>[
                _CompactFilterEntry(
                  part: parts[i],
                  usefulDetail: _usefulDetailFor(parts[i]),
                ),
                if (i < parts.length - 1) const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactFilterEntry extends StatelessWidget {
  const _CompactFilterEntry({
    required this.part,
    required this.usefulDetail,
  });

  final VehiclePart part;
  final String usefulDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tier = part.brandTierLabel;
    final subTokens = <String>[
      if (tier.isNotEmpty) tier else if (part.brand.isNotEmpty) part.brand,
      if (usefulDetail.isNotEmpty) usefulDetail,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (part.partNumber.isNotEmpty)
              _CopyableCodePill(
                code: part.partNumber,
                muted: part.isNonServiceable,
                prominent: !part.isNonServiceable,
              ),
            if (part.verified)
              Icon(
                Icons.verified_rounded,
                size: 15,
                color: colorScheme.primary,
              ),
          ],
        ),
        if (subTokens.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            subTokens.join(' • '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _WipersSpecCard extends StatelessWidget {
  const _WipersSpecCard({required this.result});

  final VinLookupResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final grouped = result.wipersByPosition;

    return _SpecSectionCard(
      icon: Icons.waves_rounded,
      title: 'WIPER BLADES',
      trailing:
          grouped.isNotEmpty ? '${grouped.length} positions' : null,
      child: grouped.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No wiper blade catalog data returned for this VIN.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: <Widget>[
                for (var i = 0; i < grouped.length; i++) ...<Widget>[
                  _WiperPositionRow(
                    positionKey: grouped.keys.elementAt(i),
                    parts: grouped.values.elementAt(i),
                  ),
                  if (i < grouped.length - 1) const Divider(height: 12),
                ],
              ],
            ),
    );
  }
}

class _WiperPositionRow extends StatelessWidget {
  const _WiperPositionRow({
    required this.positionKey,
    required this.parts,
  });

  final String positionKey;
  final List<VehiclePart> parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final first = parts.first;
    final positionTitle = positionKey == 'other'
        ? 'Blade'
        : JsonParsers.titleCaseIdentifier(positionKey);
    final size = first.wiperLengthLabel;
    final connector = first.armConnectorLabel;
    final oem = first.oemTypeLabel;
    final metaTokens = <String>[
      if (connector != null) 'Connector: $connector',
      if (oem != null) 'OEM: $oem',
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 108,
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  positionTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (size != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      size,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final part in parts)
                    _CopyableCodePill(
                      code: part.partNumber,
                      suffixLabel: _compactBladeTier(part.brandTierLabel),
                      muted: part.isNonServiceable,
                      prominent: !part.isNonServiceable,
                    ),
                ],
              ),
              if (metaTokens.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  metaTokens.join(' • '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
              ] else if (first.detail.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  first.detailSegments.join(' • '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _compactBladeTier(String tier) {
    final lower = tier.toLowerCase();
    if (lower.contains('beam')) {
      return 'Beam';
    }
    if (lower.contains('standard')) {
      return 'Std';
    }
    if (lower.contains('rear')) {
      return 'Rear';
    }
    return tier;
  }
}

class _BatterySpecCard extends StatelessWidget {
  const _BatterySpecCard({required this.parts});

  final List<VehiclePart> parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _SpecSectionCard(
      icon: Icons.battery_charging_full_rounded,
      title: 'BATTERY',
      trailing: parts.length > 1 ? '${parts.length} options' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < parts.length; i++) ...<Widget>[
            _BatteryEntry(part: parts[i], theme: theme, colorScheme: colorScheme),
            if (i < parts.length - 1) const Divider(height: 16),
          ],
        ],
      ),
    );
  }
}

class _BatteryEntry extends StatelessWidget {
  const _BatteryEntry({
    required this.part,
    required this.theme,
    required this.colorScheme,
  });

  final VehiclePart part;
  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final keyValues = part.specKeyValues;
    final notes = part.proseDetailSegments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (part.partNumber.isNotEmpty)
              _CopyableCodePill(
                code: part.partNumber,
                muted: part.isNonServiceable,
                prominent: !part.isNonServiceable,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                part.brand,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (part.verified)
              Icon(
                Icons.verified_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
          ],
        ),
        if (keyValues.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final kv in keyValues)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                      ),
                      children: <TextSpan>[
                        TextSpan(
                          text: '${kv.key}: ',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        TextSpan(
                          text: kv.value,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '• ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _isWarningNote(note)
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _isWarningNote(note)
                            ? colorScheme.error
                            : colorScheme.onSurface,
                        fontWeight: _isWarningNote(note)
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  bool _isWarningNote(String note) {
    final lower = note.toLowerCase();
    return lower.contains('reset') ||
        lower.contains('registered') ||
        lower.contains('required');
  }
}

class _GenericPartCategoryCard extends StatelessWidget {
  const _GenericPartCategoryCard({
    required this.category,
    required this.parts,
  });

  final String category;
  final List<VehiclePart> parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _SpecSectionCard(
      icon: Icons.build_circle_outlined,
      title: VehiclePart.labelForCategory(category).toUpperCase(),
      trailing: '${parts.length} items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < parts.length; i++) ...<Widget>[
            Row(
              children: <Widget>[
                if (parts[i].partNumber.isNotEmpty)
                  _CopyableCodePill(
                    code: parts[i].partNumber,
                    muted: parts[i].isNonServiceable,
                    prominent: !parts[i].isNonServiceable,
                  ),
                if (parts[i].positionLabel.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    parts[i].positionLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.tertiary,
                    ),
                  ),
                ],
                const Spacer(),
                if (parts[i].verified)
                  Icon(
                    Icons.verified_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
              ],
            ),
            if (parts[i].brand.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                parts[i].brand,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (parts[i].detailSegments.isNotEmpty) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                parts[i].detailSegments.join(' • '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (i < parts.length - 1) const Divider(height: 14),
          ],
        ],
      ),
    );
  }
}

class _AllOilOptionsCard extends StatelessWidget {
  const _AllOilOptionsCard({required this.specs});

  final List<OilSpec> specs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _SpecSectionCard(
      icon: Icons.water_drop_rounded,
      title: 'ALL ENGINE OIL OPTIONS',
      trailing: '${specs.length} specs',
      child: Column(
        children: <Widget>[
          for (var i = 0; i < specs.length; i++) ...<Widget>[
            _OilOptionRow(
              spec: specs[i],
              theme: theme,
              colorScheme: colorScheme,
            ),
            if (i < specs.length - 1) const Divider(height: 14),
          ],
        ],
      ),
    );
  }
}

class _OilOptionRow extends StatelessWidget {
  const _OilOptionRow({
    required this.spec,
    required this.theme,
    required this.colorScheme,
  });

  final OilSpec spec;
  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final capacity = spec.formattedCapacity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (spec.viscosity.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  spec.viscosity,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                spec.oilTypeLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (capacity != null)
              Text(
                capacity,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            if (spec.verified) ...<Widget>[
              const SizedBox(width: 6),
              Icon(
                Icons.verified_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
            ],
          ],
        ),
        if (spec.specNotes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            spec.specNotes,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _FluidsServicesCard extends StatelessWidget {
  const _FluidsServicesCard({required this.groupedServices});

  final Map<String, List<VehicleServiceItem>> groupedServices;

  @override
  Widget build(BuildContext context) {
    final entries = groupedServices.entries.toList(growable: false);

    return _SpecSectionCard(
      icon: Icons.miscellaneous_services_rounded,
      title: 'FLUIDS & MAINTENANCE SERVICES',
      trailing: '${entries.length} systems',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < entries.length; i++) ...<Widget>[
            _ServiceSystemBlock(
              serviceName: entries[i].key,
              items: entries[i].value,
            ),
            if (i < entries.length - 1) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

class _ServiceSystemBlock extends StatelessWidget {
  const _ServiceSystemBlock({
    required this.serviceName,
    required this.items,
  });

  final String serviceName;
  final List<VehicleServiceItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          serviceName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < items.length; i++) ...<Widget>[
          _ServiceItemRow(item: items[i]),
          if (i < items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ServiceItemRow extends StatelessWidget {
  const _ServiceItemRow({required this.item});

  final VehicleServiceItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final description =
        item.cleanNotes.isNotEmpty ? item.cleanNotes : item.origin;
    final codes = item.productCodes;
    final interval = item.formattedInterval;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            if (item.verified) ...<Widget>[
              const SizedBox(width: 6),
              Icon(
                Icons.verified_rounded,
                size: 15,
                color: colorScheme.primary,
              ),
            ],
          ],
        ),
        if (interval != null || codes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (interval != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Interval: $interval',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              for (final code in codes)
                _CopyableCodePill(
                  code: code,
                  muted: false,
                  prominent: false,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CatalogAndPowertrainCard extends StatelessWidget {
  const _CatalogAndPowertrainCard({required this.result});

  final VinLookupResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final matched = result.matchedPartsVehicle;
    final sources = result.uniqueSources;

    return _SpecSectionCard(
      icon: Icons.info_outline_rounded,
      title: 'POWERTRAIN & CATALOG MATCH DETAILS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (result.vehicle.id != null && result.vehicle.id! > 0)
            _KeyValueMetaRow(
              label: 'Vehicle ID',
              value: '#${result.vehicle.id}',
            ),
          if (matched != null) ...<Widget>[
            _KeyValueMetaRow(
              label: 'Parts Catalog Match',
              value: matched.summary,
            ),
            if (matched.matchType.isNotEmpty)
              _KeyValueMetaRow(
                label: 'Parts Match Score',
                value:
                    '${matched.matchType}${matched.matchScore != null ? ' (score ${matched.matchScore})' : ''}',
              ),
          ],
          for (final vf in result.vfMatches) ...<Widget>[
            if (vf.engineRaw.isNotEmpty)
              _KeyValueMetaRow(
                label: 'Product Finder Engine',
                value: vf.engineRaw,
              ),
            if (vf.modelRaw.isNotEmpty)
              _KeyValueMetaRow(
                label: 'Platform / Model Group',
                value: vf.modelRaw,
              ),
            _KeyValueMetaRow(
              label: 'Engine Specs',
              value: <String>[
                if (vf.displacementL != null)
                  '${vf.displacementL!.toStringAsFixed(1)}L',
                if (vf.yearFrom != null || vf.yearTo != null)
                  '${vf.yearFrom ?? '?'}–${vf.yearTo ?? 'present'}',
                if (vf.region.isNotEmpty) vf.region,
                if (vf.grade.isNotEmpty) 'Grade ${vf.grade}',
                if (vf.capacityQt != null)
                  JsonParsers.formatQuarts(vf.capacityQt!),
              ].join(' • '),
            ),
            if (vf.matchType.isNotEmpty)
              _KeyValueMetaRow(
                label: 'Match Confidence',
                value:
                    '${vf.matchType}${vf.matchScore != null ? ' (score ${vf.matchScore})' : ''}',
              ),
          ],
          if (sources.isNotEmpty) ...<Widget>[
            const Divider(height: 14),
            Text(
              'Sources: ${sources.join(' • ')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyValueMetaRow extends StatelessWidget {
  const _KeyValueMetaRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecSectionCard extends StatelessWidget {
  const _SpecSectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// Tappable monospace part/code pill that copies [code] on tap.
class _CopyableCodePill extends StatefulWidget {
  const _CopyableCodePill({
    required this.code,
    this.suffixLabel = '',
    this.muted = false,
    this.prominent = true,
  });

  final String code;
  final String suffixLabel;
  final bool muted;
  final bool prominent;

  @override
  State<_CopyableCodePill> createState() => _CopyableCodePillState();
}

class _CopyableCodePillState extends State<_CopyableCodePill> {
  bool _copied = false;
  Timer? _resetTimer;

  Future<void> _copy() async {
    if (widget.muted) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: widget.code));
    await HapticFeedback.lightImpact();
    _resetTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color bgColor;
    final Color fgColor;
    if (widget.muted) {
      bgColor = colorScheme.surfaceContainerHighest;
      fgColor = colorScheme.onSurfaceVariant;
    } else if (widget.prominent) {
      bgColor = colorScheme.primaryContainer;
      fgColor = colorScheme.onPrimaryContainer;
    } else {
      bgColor = colorScheme.surfaceContainerHighest;
      fgColor = colorScheme.onSurface;
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: widget.muted ? null : _copy,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.code,
                style: (widget.prominent
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.labelMedium)
                    ?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  color: fgColor,
                ),
              ),
              if (widget.suffixLabel.isNotEmpty) ...<Widget>[
                const SizedBox(width: 5),
                Text(
                  widget.suffixLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fgColor.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (!widget.muted) ...<Widget>[
                const SizedBox(width: 5),
                Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 13,
                  color: _copied
                      ? colorScheme.primary
                      : fgColor.withValues(alpha: 0.72),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactCopyTextButton extends StatefulWidget {
  const _CompactCopyTextButton({required this.valueToCopy});

  final String valueToCopy;

  @override
  State<_CompactCopyTextButton> createState() => _CompactCopyTextButtonState();
}

class _CompactCopyTextButtonState extends State<_CompactCopyTextButton> {
  bool _copied = false;
  Timer? _resetTimer;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.valueToCopy));
    await HapticFeedback.lightImpact();
    _resetTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TextButton.icon(
      onPressed: _copy,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 32),
        foregroundColor: _copied ? colorScheme.primary : colorScheme.primary,
      ),
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        size: 15,
      ),
      label: Text(
        _copied ? 'Copied' : 'Copy',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}
