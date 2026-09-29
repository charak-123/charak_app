import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:charak_core/charak_core.dart';

/// The patient's saved addresses, newest-first as the backend returns them.
///
/// A home visit books against one of these by `address_id` — the backend needs
/// the coordinates to check the doctor's service radius, which is why a
/// free-text address is not enough and every address carries a lat/lng.
final patientAddressesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/addresses/');
  return List<Map<String, dynamic>>.from(res as List? ?? const []);
});

/// One line summarising an address, matching what the backend snapshots onto
/// the booking.
String formatAddress(Map<String, dynamic> a) => [
      a['line1'],
      a['line2'],
      a['landmark'] != null && (a['landmark'] as String).isNotEmpty
          ? 'near ${a['landmark']}'
          : null,
      a['city'],
      a['pincode'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

/// Selectable list of saved addresses with an "Add an address" affordance.
///
/// Kept as a section rather than its own route so the channel choice and the
/// destination stay on one screen — the patient picks "Home Visit" and says
/// where in the same breath.
class AddressPickerSection extends ConsumerWidget {
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  const AddressPickerSection({
    super.key,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientAddressesProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: CharakSkeletonCard(),
      ),
      error: (e, _) => CharakNoteBanner(
        icon: Icons.error_outline,
        tone: CharakStatusTone.danger,
        message: e is ApiException ? e.message : 'Could not load your addresses',
      ),
      data: (addresses) {
        // Nothing saved yet: the first visit has to create one, so lead with
        // the action rather than an empty list.
        if (addresses.isEmpty) {
          return Column(children: [
            const CharakInfoStrip(
              icon: Icons.location_on_outlined,
              label: 'Add the address the doctor should visit.',
            ),
            const SizedBox(height: 10),
            CharakButton(
              label: 'Add an address',
              icon: Icons.add_rounded,
              outlined: true,
              onPressed: () => _add(context, ref),
            ),
          ]);
        }

        return Column(children: [
          for (final a in addresses) ...[
            CharakTileCard(
              leading: Icon(
                selectedId == a['id']
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selectedId == a['id']
                    ? CharakColors.success
                    : CharakColors.inkMuted,
              ),
              title: (a['label'] as String?)?.isNotEmpty == true
                  ? a['label'] as String
                  : 'Address',
              subtitle: formatAddress(a),
              onTap: () => onSelected(a['id'] as String),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 2),
          CharakButton(
            label: 'Add another address',
            icon: Icons.add_rounded,
            outlined: true,
            onPressed: () => _add(context, ref),
          ),
        ]);
      },
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final created = await showCharakSheet<Map<String, dynamic>>(
      context,
      title: 'Add an address',
      child: const _AddAddressForm(),
    );
    if (created == null) return;
    // Refresh the list so the new address renders, then select it — adding an
    // address is only ever done in order to use it.
    ref.invalidate(patientAddressesProvider);
    onSelected(created['id'] as String?);
  }
}

// ── Add-address form ──────────────────────────────────────────────────────────

class _AddAddressForm extends StatefulWidget {
  const _AddAddressForm();
  @override
  State<_AddAddressForm> createState() => _AddAddressFormState();
}

class _AddAddressFormState extends State<_AddAddressForm> {
  final _label = TextEditingController(text: 'Home');
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _landmark = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();

  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_label, _line1, _line2, _landmark, _city, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Coordinates come from the device, the same way the doctor pins their base
  /// location. They are required: the service-radius check cannot run without
  /// them, so the form cannot be submitted until a fix is taken.
  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _error =
            'Location is turned off on this phone. Turn it on to pin the address.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() => _error =
            'Location permission is blocked for Charak. Enable it in Settings '
            'to pin this address.');
        await Geolocator.openAppSettings();
        return;
      }
      if (perm == LocationPermission.denied) {
        setState(() =>
            _error = 'Location permission is needed to pin the address.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            "Couldn't get a location fix. Move somewhere with a clearer signal "
            'and try again.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool get _valid =>
      _line1.text.trim().length >= 3 &&
      _city.text.trim().length >= 2 &&
      _pincode.text.trim().length == 6 &&
      _lat != null &&
      _lng != null;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ApiClient.instance.post('/addresses/', {
        'label': _label.text.trim().isEmpty ? 'Home' : _label.text.trim(),
        'line1': _line1.text.trim(),
        if (_line2.text.trim().isNotEmpty) 'line2': _line2.text.trim(),
        if (_landmark.text.trim().isNotEmpty) 'landmark': _landmark.text.trim(),
        'city': _city.text.trim(),
        'pincode': _pincode.text.trim(),
        'lat': _lat,
        'lng': _lng,
      }) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop(created);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the address');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final located = _lat != null && _lng != null;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      CharakField(
          label: 'Label', controller: _label, placeholder: 'Home, Office…'),
      const SizedBox(height: 12),
      CharakField(
        label: 'Flat, building, street',
        controller: _line1,
        placeholder: '12 Rose Lane',
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      CharakField(
          label: 'Area (optional)',
          controller: _line2,
          placeholder: 'Sector 4'),
      const SizedBox(height: 12),
      CharakField(
          label: 'Landmark (optional)',
          controller: _landmark,
          placeholder: 'near City Park'),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: CharakField(
            label: 'City',
            controller: _city,
            placeholder: 'Pune',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: CharakField(
            label: 'PIN code',
            controller: _pincode,
            placeholder: '411001',
            keyboardType: TextInputType.number,
            tabular: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (_) => setState(() {}),
          ),
        ),
      ]),
      const SizedBox(height: 14),

      // The pin is what makes the address dispatchable, so it gets its own
      // explicit step rather than happening invisibly on save.
      if (located)
        CharakInfoStrip(
          icon: Icons.check_circle_outline,
          label: 'Location pinned · '
              '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
        )
      else
        CharakButton(
          label: 'Use my current location',
          icon: Icons.my_location_rounded,
          outlined: true,
          isLoading: _locating,
          onPressed: _locating ? null : _locate,
        ),

      if (_error != null) ...[
        const SizedBox(height: 12),
        CharakNoteBanner(
          icon: Icons.error_outline,
          tone: CharakStatusTone.danger,
          message: _error!,
        ),
      ],

      const SizedBox(height: 16),
      CharakButton(
        label: 'Save address',
        isLoading: _saving,
        onPressed: _valid && !_saving ? _save : null,
      ),
      const SizedBox(height: 4),
      if (!located)
        const CharakHintLine(
            text: 'Pin the location so the doctor can be routed to you.'),
    ]);
  }
}
