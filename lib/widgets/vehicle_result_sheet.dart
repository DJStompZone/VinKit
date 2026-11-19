import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vinkit_app/models/oil_spec.dart';
import 'package:vinkit_app/models/vehicle_part.dart';
import 'package:vinkit_app/models/vehicle_service_item.dart';
import 'package:vinkit_app/models/vin_lookup_exception.dart';
import 'package:vinkit_app/models/vin_lookup_result.dart';
import 'package:vinkit_app/models/vin_lookup_state.dart';
import 'package:vinkit_app/services/vin_lookup_controller.dart';

/// Scrollable Material 3 bottom sheet presenting VIN lookup loading, error,
/// and decoded vehicle, parts, oil, and service details.
class VehicleResultSheet extends StatelessWidget {
  /// Creates a [VehicleResultSheet] bound to [controller].
  const VehicleResultSheet({
    super.key,
    required this.controller,
    required this.onScanNext,
    required this.onEnterDifferentVin,
  });

  /// Controller driving the active VIN lookup lifecycle.
  final VinLookupController controller;

  /// Invoked when the user taps "Scan Next Vehicle".
  final VoidCallback onScanNext;

  /// Invoked when the user chooses to enter a different VIN manually.
  final VoidCallback onEnterDifferentVin;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final state = controller.state;

              return Column(
                children: <Widget>[
                  Expanded(
                    child: switch (state) {
                      VinLookupIdle() => _LoadingResultView(
                          vin: controller.lastVin ?? '',
                          scrollController: scrollController,
                        ),
                      VinLookupLoading(:final vin) => _LoadingResultView(
                          vin: vin,
                          scrollController: scrollController,
                        ),
                      VinLookupFailure(:final vin, :final error) =>
                        _ErrorResultView(
                          vin: vin,
                          error: error,
                          scrollController: scrollController,
                          onRetry: error.isRetryable
                              ? () => unawaited(controller.retry())
                              : null,
                          onEnterDifferentVin: onEnterDifferentVin,
                        ),
                      VinLookupSuccess(:final result) => _SuccessResultView(
                          result: result,
                          scrollController: scrollController,
                        ),
                    },
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onScanNext,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Scan Next Vehicle'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _LoadingResultView extends StatelessWidget {
  const _LoadingResultView({
    required this.vin,
    required this.scrollController,
  });

  final String vin;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: <Widget>[
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text(
          'Decoding VIN & Service Specs',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        if (vin.isNotEmpty)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(
                  vin,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Fetching vehicle match, maintenance filters, motor oil specs, and fluid services...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ErrorResultView extends StatelessWidget {
  const _ErrorResultView({
    required this.vin,
    required this.error,
    required this.scrollController,
    required this.onRetry,
    required this.onEnterDifferentVin,
  });

  final String vin;
  final VinLookupException error;
  final ScrollController scrollController;
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
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: <Widget>[
        Center(
          child: CircleAvatar(
            radius: 32,
            backgroundColor: colorScheme.errorContainer,
            foregroundColor: colorScheme.onErrorContainer,
            child: Icon(icon, size: 32),
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
          const SizedBox(height: 16),
          _VinCopyCard(vin: vin),
        ],
        const SizedBox(height: 20),
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

class _SuccessResultView extends StatelessWidget {
  const _SuccessResultView({
    required this.result,
    required this.scrollController,
  });

  final VinLookupResult result;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final partCategories = result.orderedPartCategories;
    final groupedServices = result.servicesByName;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        _VehicleHeaderCard(result: result),
        if (partCategories.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          _SectionTitle(
            title: 'Parts & Filters',
            countLabel: '${partCategories.length} categories',
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < partCategories.length; i++) ...<Widget>[
            _PartCategoryCard(
              category: partCategories[i],
              parts: result.partsByCategory[partCategories[i]]!,
            ),
            if (i < partCategories.length - 1) const SizedBox(height: 10),
          ],
        ],
        if (result.oilSpecs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          _SectionTitle(
            title: 'Engine Oil Specifications',
            countLabel: '${result.oilSpecs.length} options',
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < result.oilSpecs.length; i++) ...<Widget>[
            _OilSpecCard(spec: result.oilSpecs[i]),
            if (i < result.oilSpecs.length - 1) const SizedBox(height: 10),
          ],
        ],
        if (groupedServices.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          _SectionTitle(
            title: 'Fluids & Maintenance Services',
            countLabel: '${groupedServices.length} systems',
          ),
          const SizedBox(height: 10),
          for (final entry in groupedServices.entries) ...<Widget>[
            _ServiceGroupCard(
              serviceName: entry.key,
              items: entry.value,
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (result.matchedPartsVehicle != null ||
            result.vfMatches.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _CatalogMatchCard(result: result),
        ],
      ],
    );
  }
}

class _VehicleHeaderCard extends StatelessWidget {
  const _VehicleHeaderCard({required this.result});

  final VinLookupResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final vehicle = result.vehicle;
    final oilViscosity = result.primaryOilViscosity;
    final oilCapacity = result.primaryOilCapacityLabel;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                        vehicle.displayTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (vehicle.engine.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          vehicle.engine,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (vehicle.year != null && vehicle.year! > 0)
                  _MetadataChip(
                    icon: Icons.calendar_today_rounded,
                    label: '${vehicle.year}',
                  ),
                if (vehicle.make.isNotEmpty)
                  _MetadataChip(
                    icon: Icons.factory_outlined,
                    label: vehicle.make,
                  ),
                if (vehicle.model.isNotEmpty)
                  _MetadataChip(
                    icon: Icons.label_outline_rounded,
                    label: vehicle.model,
                  ),
                if (vehicle.trim.isNotEmpty)
                  _MetadataChip(
                    icon: Icons.auto_awesome_outlined,
                    label: vehicle.trim,
                  ),
                if (oilViscosity != null)
                  _MetadataChip(
                    icon: Icons.opacity_rounded,
                    label: 'Oil $oilViscosity',
                  ),
                if (oilCapacity != null)
                  _MetadataChip(
                    icon: Icons.water_drop_outlined,
                    label: oilCapacity,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _VinCopyCard(vin: result.vin),
          ],
        ),
      ),
    );
  }
}

class _VinCopyCard extends StatelessWidget {
  const _VinCopyCard({required this.vin});

  final String vin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'RAW VIN',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    vin,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CopyActionButton(valueToCopy: vin),
          ],
        ),
      ),
    );
  }
}

class _CopyActionButton extends StatefulWidget {
  const _CopyActionButton({
    required this.valueToCopy,
    this.compact = false,
  });

  final String valueToCopy;
  final bool compact;

  @override
  State<_CopyActionButton> createState() => _CopyActionButtonState();
}

class _CopyActionButtonState extends State<_CopyActionButton> {
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
    final colorScheme = Theme.of(context).colorScheme;
    if (widget.compact) {
      return IconButton(
        onPressed: _copy,
        tooltip: _copied ? 'Copied' : 'Copy part number',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          size: 18,
          color: _copied ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      );
    }

    return FilledButton.tonalIcon(
      onPressed: _copy,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        size: 18,
      ),
      label: Text(_copied ? 'Copied' : 'Copy'),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: colorScheme.onSecondaryContainer),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.countLabel,
  });

  final String title;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          countLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PartCategoryCard extends StatelessWidget {
  const _PartCategoryCard({
    required this.category,
    required this.parts,
  });

  final String category;
  final List<VehiclePart> parts;

  IconData _iconForCategory(String key) {
    return switch (key) {
      'oil_filter' => Icons.oil_barrel_outlined,
      'air_filter' => Icons.air_rounded,
      'cabin_filter' => Icons.hvac_rounded,
      'fuel_filter' => Icons.local_gas_station_outlined,
      'battery' => Icons.battery_charging_full_rounded,
      'wiper' => Icons.waves_rounded,
      _ => Icons.build_circle_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  _iconForCategory(category),
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  VehiclePart.labelForCategory(category),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < parts.length; i++) ...<Widget>[
              _PartRow(part: parts[i]),
              if (i < parts.length - 1) const Divider(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({required this.part});

  final VehiclePart part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final position = part.positionLabel;
    final segments = part.detailSegments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (part.partNumber.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  part.partNumber,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            if (part.partNumber.isNotEmpty && part.partNumber != 'NS')
              _CopyActionButton(
                valueToCopy: part.partNumber,
                compact: true,
              ),
            if (position.isNotEmpty) ...<Widget>[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  position,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (part.verified)
              Tooltip(
                message: 'Verified catalog fitment',
                child: Icon(
                  Icons.verified_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
          ],
        ),
        if (part.brand.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            part.brand,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (segments.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            segments.join(' • '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _OilSpecCard extends StatelessWidget {
  const _OilSpecCard({required this.spec});

  final OilSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final capacity = spec.formattedCapacity;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (spec.viscosity.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      spec.viscosity,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    spec.oilTypeLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (capacity != null)
                  Text(
                    capacity,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (spec.verified) ...<Widget>[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.verified_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ],
              ],
            ),
            if (spec.specNotes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                spec.specNotes,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServiceGroupCard extends StatelessWidget {
  const _ServiceGroupCard({
    required this.serviceName,
    required this.items,
  });

  final String serviceName;
  final List<VehicleServiceItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.miscellaneous_services_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    serviceName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < items.length; i++) ...<Widget>[
              _ServiceItemRow(item: items[i]),
              if (i < items.length - 1) const Divider(height: 14),
            ],
          ],
        ),
      ),
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
    final interval = item.formattedInterval;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                item.notes.isNotEmpty ? item.notes : item.origin,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (item.verified) ...<Widget>[
              const SizedBox(width: 8),
              Icon(
                Icons.verified_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
            ],
          ],
        ),
        if (interval != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            'Interval: $interval',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _CatalogMatchCard extends StatelessWidget {
  const _CatalogMatchCard({required this.result});

  final VinLookupResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final matched = result.matchedPartsVehicle;

    return Card(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            'Catalog Match Metadata',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (matched != null) ...<Widget>[
              Text(
                'Parts Catalog Vehicle: ${matched.summary}',
                style: theme.textTheme.bodySmall,
              ),
              if (matched.matchType.isNotEmpty)
                Text(
                  'Match Type: ${matched.matchType} (score ${matched.matchScore ?? '-'})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
            for (final vf in result.vfMatches) ...<Widget>[
              if (matched != null) const SizedBox(height: 8),
              Text(
                'Product Finder: ${vf.engineRaw}',
                style: theme.textTheme.bodySmall,
              ),
              if (vf.modelRaw.isNotEmpty)
                Text(
                  'Model Group: ${vf.modelRaw} • ${vf.matchType} (score ${vf.matchScore ?? '-'})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
