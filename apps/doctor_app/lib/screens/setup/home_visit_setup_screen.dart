import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:charak_core/charak_core.dart';
import 'schedule_editor.dart';
import '../shared/charak_button.dart';

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
  int?   _radius;
  bool   _loading = false, _locating = false;
  String? _error;

  static const _radii = [2, 3, 5];

  Future<void> _detectLocation() async {
    setState(() => _locating = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _address = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      });
    } catch (e) {
      setState(() => _error = 'Could not get location. Please enable location access.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool get _valid => _blocks.isNotEmpty && _lat != null && _radius != null;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.instance.put('/schedules/me/home-visit', _blocks.map((b) => b.toJson()).toList());
      await ApiClient.instance.patch('/doctors/me', {
        'base_lat': _lat,
        'base_lng': _lng,
        'service_radius_km': _radius,
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
      appBar: AppBar(title: const Text('Home Visit Service')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Schedule
              Text('When are you available for home visits?',
                  style: CharakText.h2.copyWith(color: CharakColors.ink)),
              const SizedBox(height: CharakSpacing.base),
              ScheduleEditor(
                blocks: _blocks,
                onChanged: (b) => setState(() => _blocks = b),
              ),
              const Divider(height: CharakSpacing.xl),

              // Base location
              Text('Your base location', style: CharakText.h2.copyWith(color: CharakColors.ink)),
              const SizedBox(height: CharakSpacing.xs),
              Text('Patients within your radius can book home visits.',
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.base),
              GestureDetector(
                onTap: _detectLocation,
                child: Container(
                  padding: const EdgeInsets.all(CharakSpacing.base),
                  decoration: BoxDecoration(
                    color: CharakColors.bgSubtle,
                    borderRadius: BorderRadius.all(CharakRadius.button),
                    border: Border.all(color: _lat != null ? CharakColors.success : CharakColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _lat != null ? Icons.location_on : Icons.my_location,
                        color: _lat != null ? CharakColors.success : CharakColors.primary,
                      ),
                      const SizedBox(width: CharakSpacing.sm),
                      Expanded(
                        child: Text(
                          _locating ? 'Detecting location…'
                              : _address ?? 'Tap to use current location',
                          style: CharakText.body.copyWith(
                            color: _lat != null ? CharakColors.success : CharakColors.inkMuted,
                          ),
                        ),
                      ),
                      if (_locating) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                ),
              ),
              const Divider(height: CharakSpacing.xl),

              // Radius
              Text('Service radius', style: CharakText.h2.copyWith(color: CharakColors.ink)),
              const SizedBox(height: CharakSpacing.xs),
              Text('You\'ll serve patients within this distance.',
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.base),
              Row(
                children: _radii.map((r) {
                  final sel = _radius == r;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _radius = r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: CharakSpacing.sm),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: sel ? CharakColors.primary : CharakColors.bgSubtle,
                          borderRadius: BorderRadius.all(CharakRadius.button),
                          border: Border.all(color: sel ? CharakColors.primary : CharakColors.border),
                        ),
                        child: Text('$r km',
                            textAlign: TextAlign.center,
                            style: CharakText.bodyMed.copyWith(color: sel ? Colors.white : CharakColors.ink)),
                      ),
                    ),
                  );
                }).toList(),
              ),

              if (_error != null) ...[
                const SizedBox(height: CharakSpacing.base),
                Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
              ],
              const SizedBox(height: CharakSpacing.lg),
              CharakButton(
                label: 'Continue',
                onPressed: _valid ? _submit : null,
                isLoading: _loading,
              ),
              const SizedBox(height: CharakSpacing.base),
            ],
          ),
        ),
      ),
    );
  }
}
