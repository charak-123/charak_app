import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:charak_core/charak_core.dart';
import 'schedule_editor.dart';

class HomeVisitSetupScreen extends ConsumerStatefulWidget {
  final bool fromSetup;
  const HomeVisitSetupScreen({super.key, this.fromSetup = false});

  @override
  ConsumerState<HomeVisitSetupScreen> createState() => _HomeVisitSetupScreenState();
}

class _HomeVisitSetupScreenState extends ConsumerState<HomeVisitSetupScreen> {
  List<ScheduleBlock> _blocks = [];
  double? _lat, _lng;
  String? _address;
  int    _radius = 3; // middle of _radii; pre-selected per the wireframe
  bool   _loading = false, _locating = false;
  String? _error;

  static const _radii = [2, 3, 5];

  Future<void> _detectLocation() async {
    setState(() { _locating = true; _error = null; });
    try {
      // Location services off at the OS level can't be fixed by a permission
      // prompt — say so instead of failing with a generic message.
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _error =
            'Location is turned off on this phone. Switch it on, then tap Detect again.');
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() => _error =
            'Location permission is blocked for Charak. Enable it in Settings, '
            'or skip this and set your base location later.');
        await Geolocator.openAppSettings();
        return;
      }
      if (perm == LocationPermission.denied) {
        setState(() => _error =
            'Location permission declined. You can skip this and set your base '
            'location later.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _address = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      });
    } catch (_) {
      setState(() => _error =
          "Couldn't get a location fix. You can skip this and set your base "
          'location later.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // The base location is not required to finish setup: a doctor indoors, or one
  // who declines the permission, must still be able to onboard and pin it later.
  // The wireframe's Continue is likewise ungated. Radius defaults below.
  bool get _valid => _blocks.isNotEmpty;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.instance.put('/schedules/me/home-visit', _blocks.map((b) => b.toJson()).toList());
      // Only send what we actually have: the backend strips nulls and rejects
      // an empty patch with "No fields to update", so a skipped location must
      // not turn into a body of three nulls.
      await ApiClient.instance.patch('/doctors/me', {
        'service_radius_km': _radius,
        if (_lat != null) 'base_lat': _lat,
        if (_lng != null) 'base_lng': _lng,
      });
      if (mounted) context.go('/setup/pricing');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Home visits', style: CharakText.h1),
                    const SizedBox(height: 5),
                    Text('Schedule, radius and base location.',
                        style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted)),
                    const SizedBox(height: 16),

                    const CharakSectionTitle(label: 'Service radius'),
                    const SizedBox(height: 9),
                    // `.rad-chips` — equal 52px cells, 10px gutters.
                    Row(
                      children: [
                        for (var idx = 0; idx < _radii.length; idx++) ...[
                          if (idx > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _RadiusChip(
                              label: '${_radii[idx]} km',
                              selected: _radius == _radii[idx],
                              onTap: () => setState(() => _radius = _radii[idx]),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),

                    const CharakSectionTitle(label: 'Base location'),
                    const SizedBox(height: 9),
                    _BaseLocationCard(
                      locating: _locating,
                      address: _address,
                      resolved: _lat != null,
                      onTap: _detectLocation,
                    ),
                    const SizedBox(height: 20),

                    const CharakSectionTitle(label: 'Visit hours'),
                    const SizedBox(height: 9),
                    // `.card` wrapper with the spec's 4px/14px inset.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: CharakColors.bg,
                        borderRadius: const BorderRadius.all(CharakRadius.card),
                        border: Border.all(color: CharakColors.border),
                      ),
                      child: ScheduleEditor(
                        blocks: _blocks,
                        onChanged: (b) => setState(() => _blocks = b),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: CharakSpacing.base),
                      Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
                    ],
                  ],
                ),
              ),
            ),
            CharakCtaBar.single(
              CharakButton(
                label: 'Continue',
                onPressed: _valid ? _submit : null,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.rad-chip` — 52px tall bordered cell that takes a primary border and a
/// primarySoft fill when selected.
class _RadiusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RadiusChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: CharakDurations.buttonPress,
      height: 52,
      decoration: BoxDecoration(
        color: selected ? CharakColors.primarySoft : CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.button),
        border: Border.all(color: selected ? CharakColors.primary : CharakColors.border),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: CharakText.bodyMed.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: selected ? CharakColors.primaryDeep : CharakColors.ink,
        ),
      ),
    ),
  );
}

/// Base-location card — 36px primarySoft pin chip, 14px/600 label with a
/// 12px muted coordinate line, trailing chevron.
class _BaseLocationCard extends StatelessWidget {
  final bool locating;
  final String? address;
  final bool resolved;
  final VoidCallback onTap;
  const _BaseLocationCard({
    required this.locating,
    required this.address,
    required this.resolved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
        border: Border.all(color: CharakColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CharakColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.location_on_outlined,
                size: 16, color: CharakColors.primaryDeep),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolved ? 'Base location set' : 'Use my current location',
                  style: CharakText.bodyMed.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  locating ? 'Detecting location…' : (address ?? 'Tap to detect via GPS'),
                  style: const TextStyle(
                    fontFamily: CharakText.fontFamily,
                    fontSize: 12,
                    height: 1.4,
                    color: CharakColors.inkMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (locating)
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.chevron_right, size: 16, color: CharakColors.inkMuted),
        ],
      ),
    ),
  );
}
