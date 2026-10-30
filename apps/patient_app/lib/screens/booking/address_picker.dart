import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        icon: LucideIcons.circleAlert,
        tone: CharakStatusTone.danger,
        message: e is ApiException ? e.message : 'Could not load your addresses',
      ),
      data: (addresses) {
        // Nothing saved yet: the first visit has to create one, so lead with
        // the action rather than an empty list.
        if (addresses.isEmpty) {
          return Column(children: [
            const CharakInfoStrip(
              icon: LucideIcons.mapPin,
              label: 'Add the address the doctor should visit.',
            ),
            const SizedBox(height: 10),
            CharakButton(
              label: 'Add an address',
              icon: LucideIcons.plus,
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
                    ? LucideIcons.circleDot
                    : LucideIcons.circle,
                size: 20,
                color: selectedId == a['id']
                    ? CharakColors.success
                    : CharakColors.inkMuted,
              ),
              title: (a['label'] as String?)?.isNotEmpty == true
                  ? a['label'] as String
                  : 'Address',
              subtitle: formatAddress(a),
              // A saved address can be corrected: a flat number, a landmark,
              // or the pin itself.
              trailing: IconButton(
                tooltip: 'Edit address',
                icon: Icon(LucideIcons.pencil, size: 18, color: CharakColors.primary),
                onPressed: () => _edit(context, ref, a),
              ),
              onTap: () => onSelected(a['id'] as String),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 2),
          CharakButton(
            label: 'Add another address',
            icon: LucideIcons.plus,
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

  Future<void> _edit(BuildContext context, WidgetRef ref, Map<String, dynamic> address) async {
    final saved = await showCharakSheet<Map<String, dynamic>>(
      context,
      title: 'Edit address',
      child: _AddAddressForm(initial: address),
    );
    if (saved == null) return;
    ref.invalidate(patientAddressesProvider);
    onSelected(saved['id'] as String?);
  }
}

// ── Add-address form ──────────────────────────────────────────────────────────

/// Adds an address, or with [initial] edits a saved one. Every field stays
/// editable after "Fill from my current location": the phone's geocoder only
/// suggests text, and the patient knows their flat number better than it
/// does.
class _AddAddressForm extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _AddAddressForm({this.initial});
  @override
  State<_AddAddressForm> createState() => _AddAddressFormState();
}

class _AddAddressFormState extends State<_AddAddressForm> {
  late final _label = TextEditingController(text: _initial('label') ?? 'Home');
  late final _line1 = TextEditingController(text: _initial('line1'));
  late final _line2 = TextEditingController(text: _initial('line2'));
  late final _landmark = TextEditingController(text: _initial('landmark'));
  late final _city = TextEditingController(text: _initial('city'));
  late final _pincode = TextEditingController(text: _initial('pincode'));

  late double? _lat = (widget.initial?['lat'] as num?)?.toDouble();
  late double? _lng = (widget.initial?['lng'] as num?)?.toDouble();
  bool _locating = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.initial != null;
  String? _initial(String k) => widget.initial?[k] as String?;

  @override
  void dispose() {
    for (final c in [_label, _line1, _line2, _landmark, _city, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Coordinates come from the device, the same way the doctor pins their base
  /// location, and are required: the service-radius check cannot run without
  /// them. The phone's geocoder then reads the address at that spot and fills
  /// any field the patient has not typed yet. Everything stays editable.
  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final place = await CharakLocation.current();
      if (!mounted) return;
      setState(() {
        _lat = place.lat;
        _lng = place.lng;
        _fill(_line1, place.line1);
        _fill(_line2, place.line2);
        _fill(_city, place.city);
        _fill(_pincode, place.pincode);
        if (!place.hasAddress) {
          _error = "Pinned your spot, but couldn't read the address. "
              'Please type it in.';
        }
      });
    } on CharakLocationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _fill(TextEditingController c, String? value) {
    if (value != null && c.text.trim().isEmpty) c.text = value;
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
      final body = {
        'label': _label.text.trim().isEmpty ? 'Home' : _label.text.trim(),
        'line1': _line1.text.trim(),
        if (_line2.text.trim().isNotEmpty) 'line2': _line2.text.trim(),
        if (_landmark.text.trim().isNotEmpty) 'landmark': _landmark.text.trim(),
        'city': _city.text.trim(),
        'pincode': _pincode.text.trim(),
        'lat': _lat,
        'lng': _lng,
      };
      final saved = (_editing
          ? await ApiClient.instance.patch('/addresses/${widget.initial!['id']}', body)
          : await ApiClient.instance.post('/addresses/', body)) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop(saved);
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

    // Scrolls inside the sheet, which rides up with the keyboard: with the
    // keyboard open the form is taller than what is left, and without this
    // the field being typed into sat behind the keyboard.
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
      // explicit step rather than happening invisibly on save. Once pinned
      // it can be taken again (standing somewhere else, or a poor first fix);
      // the typed address is kept either way.
      if (located) ...[
        const CharakInfoStrip(
          icon: LucideIcons.circleCheck,
          label: 'Location pinned. You can still edit any line above.',
        ),
        const SizedBox(height: 8),
        CharakButton(
          label: 'Pin my current location again',
          icon: LucideIcons.locateFixed,
          variant: CharakButtonVariant.outline,
          isLoading: _locating,
          onPressed: _locating ? null : _locate,
        ),
      ] else
        CharakButton(
          label: 'Fill from my current location',
          icon: LucideIcons.locateFixed,
          outlined: true,
          isLoading: _locating,
          onPressed: _locating ? null : _locate,
        ),

      if (_error != null) ...[
        const SizedBox(height: 12),
        CharakNoteBanner(
          icon: LucideIcons.circleAlert,
          tone: CharakStatusTone.danger,
          message: _error!,
        ),
      ],

      const SizedBox(height: 16),
      CharakButton(
        label: _editing ? 'Save changes' : 'Save address',
        isLoading: _saving,
        onPressed: _valid && !_saving ? _save : null,
      ),
      const SizedBox(height: 4),
      if (!located)
        const CharakHintLine(
            text: 'Pin the location so the doctor can be routed to you.'),
    ]),
    );
  }
}
