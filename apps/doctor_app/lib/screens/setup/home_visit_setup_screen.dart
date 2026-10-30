import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  bool   _loaded = false;
  Object? _loadError;
  String? _error;

  static const _radii = [2, 3, 5];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// What is already saved: hours, radius and base location. This screen
  /// used to open blank every time, so a doctor changing one block had to
  /// redo the week, and an untouched radius reset to 3 km on save.
  Future<void> _load() async {
    setState(() { _loadError = null; _loaded = false; });
    try {
      final results = await Future.wait([
        loadScheduleBlocks('home_visit'),
        ApiClient.instance.get('/doctors/me'),
      ]);
      final me = results[1] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _blocks = results[0] as List<ScheduleBlock>;
        _radius = (me['service_radius_km'] as num?)?.toInt() ?? _radius;
        _lat = (me['base_lat'] as num?)?.toDouble();
        _lng = (me['base_lng'] as num?)?.toDouble();
        _loaded = true;
      });
      final lat = _lat, lng = _lng;
      if (lat != null && lng != null) {
        final place = await CharakLocation.describe(lat, lng);
        if (mounted && _lat == lat && _lng == lng) setState(() => _address = _label(place));
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// The area name reads better than raw coordinates; fall back to them when
  /// the phone's geocoder had nothing.
  static String _label(CharakPlace p) {
    final text = [p.line2, p.city, p.pincode].whereType<String>().join(', ');
    return text.isNotEmpty ? text : '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}';
  }

  Future<void> _detectLocation() async {
    setState(() { _locating = true; _error = null; });
    try {
      final place = await CharakLocation.current();
      if (!mounted) return;
      setState(() {
        _lat = place.lat;
        _lng = place.lng;
        _address = _label(place);
      });
    } on CharakLocationException catch (e) {
      if (mounted) {
        setState(() => _error =
            '${e.message} You can skip this and set your base location later.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // The base location is not required to finish setup: a doctor indoors, or one
  // who declines the permission, must still be able to onboard and pin it later.
  // The wireframe's Continue is likewise ungated. Radius defaults below.
  bool get _valid => _blocks.isNotEmpty;

  /// The standard choices, plus a saved radius that isn't one of them, so
  /// it shows as selected instead of silently becoming 3 km.
  List<int> get _radiusChoices =>
      _radii.contains(_radius) ? _radii : ([..._radii, _radius]..sort());

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
      if (!mounted) return;
      if (widget.fromSetup) {
        context.go('/setup/pricing');
      } else {
        showCharakToast(context, message: 'Home visit settings saved');
        context.pop(true);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CharakScreen(
      // This screen also serves as a settings re-edit, pushed from the
      // profile tab — without a back affordance there is no way off it on
      // iOS, which has no hardware back button. Blank title: the screen
      // already carries its own big title below.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loadError != null
                  ? CharakErrorState(error: _loadError!, onRetry: _load)
                  : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Home visits', style: CharakText.titleLarge),
                    const SizedBox(height: 5),
                    Text('Schedule, radius and base location.',
                        style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted)),
                    const SizedBox(height: 16),

                    const CharakSectionTitle(label: 'Service radius'),
                    const SizedBox(height: 9),
                    // `.rad-chips` — equal 52px cells, 10px gutters.
                    Row(
                      children: [
                        for (var idx = 0; idx < _radiusChoices.length; idx++) ...[
                          if (idx > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _RadiusChip(
                              label: '${_radiusChoices[idx]} km',
                              selected: _radius == _radiusChoices[idx],
                              onTap: () => setState(() => _radius = _radiusChoices[idx]),
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
                    if (_lat != null) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('Moved? Tap it where you now start your visits to pin it again.',
                            style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                      ),
                    ],
                    const SizedBox(height: 20),

                    const CharakSectionTitle(label: 'Visit hours'),
                    const SizedBox(height: 9),
                    // `.card` wrapper with the spec's 4px/14px inset.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: CharakColors.bg,
                        borderRadius: const BorderRadius.all(CharakRadius.card),
                      ),
                      child: !_loaded
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: CharakSkeletonList(count: 3, avatar: false, padding: EdgeInsets.zero),
                            )
                          : ScheduleEditor(
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
                label: widget.fromSetup ? 'Continue' : 'Save',
                // Never save over settings that didn't load: that would erase them.
                onPressed: _loaded && _valid ? _submit : null,
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
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            // Same well as CharakListRow's leading icon.
            decoration: BoxDecoration(
              color: CharakColors.primarySoft,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
            ),
            alignment: Alignment.center,
            child: Icon(LucideIcons.mapPin,
                size: 20, color: CharakColors.primaryDeep),
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
                  locating
                      ? 'Detecting location…'
                      : (address ?? (resolved ? 'Pinned' : 'Tap to detect via GPS')),
                  style: CharakText.caption.tabular.copyWith(color: CharakColors.inkMuted),
                ),
              ],
            ),
          ),
          if (locating)
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(resolved ? LucideIcons.locateFixed : LucideIcons.chevronRight,
                size: 16, color: CharakColors.inkMuted),
        ],
      ),
    ),
  );
}
