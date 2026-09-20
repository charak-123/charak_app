import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class _ProcedureEntry {
  final nameCtrl  = TextEditingController();
  final priceCtrl = TextEditingController();
  _ProcedureEntry();
  void dispose() { nameCtrl.dispose(); priceCtrl.dispose(); }
  bool get valid => nameCtrl.text.trim().isNotEmpty && double.tryParse(priceCtrl.text) != null;
}

class PricingSetupScreen extends ConsumerStatefulWidget {
  const PricingSetupScreen({super.key});

  @override
  ConsumerState<PricingSetupScreen> createState() => _PricingSetupScreenState();
}

class _PricingSetupScreenState extends ConsumerState<PricingSetupScreen> {
  // Consult fees
  final _onlineBaseCtrl  = TextEditingController();
  final _onlineExtraCtrl = TextEditingController();
  final _homeBaseCtrl    = TextEditingController();
  final _homeExtraCtrl   = TextEditingController();
  final _thresholdCtrl   = TextEditingController();

  final List<_ProcedureEntry> _procs = [_ProcedureEntry()];

  bool _loadingDoctorInfo = true;
  bool _offersOnline = false, _offersHome = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDoctorInfo();
  }

  @override
  void dispose() {
    _onlineBaseCtrl.dispose(); _onlineExtraCtrl.dispose();
    _homeBaseCtrl.dispose();   _homeExtraCtrl.dispose();
    _thresholdCtrl.dispose();
    for (final p in _procs) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDoctorInfo() async {
    try {
      final me = await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
      setState(() {
        _offersOnline = me['offers_online_consult'] as bool? ?? false;
        _offersHome   = me['offers_home_visit']    as bool? ?? false;
        _loadingDoctorInfo = false;
      });
    } catch (_) {
      setState(() => _loadingDoctorInfo = false);
    }
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Pricing
      final pricingItems = <Map<String, dynamic>>[];
      if (_offersOnline) {
        pricingItems.add({
          'channel': 'online_consult',
          'price': double.parse(_onlineBaseCtrl.text),
          'extra_rate_per_15min': double.tryParse(_onlineExtraCtrl.text) ?? 0,
        });
      }
      if (_offersHome) {
        pricingItems.add({
          'channel': 'home_visit',
          'price': double.parse(_homeBaseCtrl.text),
          'extra_rate_per_15min': double.tryParse(_homeExtraCtrl.text) ?? 0,
        });
      }
      await ApiClient.instance.put('/doctors/me/pricing', pricingItems);

      // Procedures
      for (final p in _procs.where((p) => p.valid)) {
        await ApiClient.instance.post('/doctors/me/procedures', {
          'name': p.nameCtrl.text.trim(),
          'price': double.parse(p.priceCtrl.text),
        });
      }

      // Threshold
      if (_thresholdCtrl.text.isNotEmpty) {
        await ApiClient.instance.patch('/doctors/me', {
          'procedure_review_threshold': double.parse(_thresholdCtrl.text),
        });
      }

      if (mounted) context.go('/home');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// One consult-fee block: `.field` label, then the base-price row
  /// (18px ₹ + flexible input + `.price-suffix`) and the 86px extra-rate row.
  Widget _feeSection(String label, TextEditingController baseCtrl, TextEditingController extraCtrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabel),
        const SizedBox(height: 7),
        Row(children: [
          const Text('₹', style: _rupee),
          const SizedBox(width: 10),
          Expanded(
            child: _PriceField(
              controller: baseCtrl,
              hint: '500',
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          const Text('per 15 min', style: _suffix),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 86,
            child: _PriceField(
              controller: extraCtrl,
              hint: '150',
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          const Text('extra per 15 min', style: _suffix),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Which channels this doctor offers decides which fee sections render, so
    // this is arriving content, not a pending action — `.skel` blocks keep the
    // step dots and heading in place while it loads.
    if (_loadingDoctorInfo) {
      return const Scaffold(
        backgroundColor: CharakColors.bg,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CharakStepDots(current: 2),
                SizedBox(height: 10),
                Text('Set your prices', style: CharakText.h1),
                SizedBox(height: 5),
                CharakSkeleton(height: 14),
                SizedBox(height: 7),
                CharakSkeleton(width: 240, height: 14),
                SizedBox(height: 18),
                CharakSkeleton(height: 132, radius: 14),
                SizedBox(height: 12),
                CharakSkeleton(height: 132, radius: 14),
              ],
            ),
          ),
        ),
      );
    }

    final onlineValid = !_offersOnline || (_onlineBaseCtrl.text.isNotEmpty);
    final homeValid   = !_offersHome   || (_homeBaseCtrl.text.isNotEmpty);

    final onlineShown = _onlineBaseCtrl.text.isNotEmpty ? _onlineBaseCtrl.text : '—';
    final homeShown   = _homeBaseCtrl.text.isNotEmpty ? _homeBaseCtrl.text : '—';

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
                    const CharakStepDots(current: 2),
                    const SizedBox(height: 10),
                    const Text('Set your prices', style: CharakText.h1),
                    const SizedBox(height: 5),
                    Text(
                      'Consult fee covers a base time (min 15 min). Extra time is charged '
                      'per additional 15 min — your call.',
                      style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted),
                    ),
                    const SizedBox(height: 18),

                    if (_offersOnline) ...[
                      _feeSection('Online Consult', _onlineBaseCtrl, _onlineExtraCtrl),
                      const SizedBox(height: 12),
                    ],
                    if (_offersHome) ...[
                      _feeSection('Home Visit', _homeBaseCtrl, _homeExtraCtrl),
                      const SizedBox(height: 14),

                      const CharakSectionTitle(label: 'Procedure prices · fixed'),
                      const SizedBox(height: 9),
                      Text(
                        "Shown to patients on your profile. Charged only after a home visit, "
                        "for what's actually done.",
                        style: CharakText.caption.copyWith(color: CharakColors.inkMuted, height: 1.5),
                      ),
                      const SizedBox(height: 12),

                      // `.proc-price-row` — bordered 9/14 row, name on the left,
                      // ₹ + a 78×38 right-aligned price input on the right.
                      ..._procs.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: CharakColors.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: CharakColors.border),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: _PlainField(
                                controller: p.nameCtrl,
                                hint: 'e.g. ECG',
                                onChanged: () => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('₹', style: TextStyle(
                              fontFamily: CharakText.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: CharakColors.ink,
                              fontFeatures: [FontFeature.tabularFigures()],
                            )),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 78,
                              child: _PriceField(
                                controller: p.priceCtrl,
                                hint: '250',
                                height: 38,
                                align: TextAlign.right,
                                onChanged: () => setState(() {}),
                              ),
                            ),
                            if (_procs.length > 1)
                              GestureDetector(
                                onTap: () {
                                  p.dispose();
                                  setState(() => _procs.removeAt(i));
                                },
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(Icons.remove_circle_outline,
                                      size: 18, color: CharakColors.danger),
                                ),
                              ),
                          ]),
                        );
                      }),
                      CharakGhostButton(
                        label: 'Add procedure',
                        icon: Icons.add,
                        onPressed: () => setState(() => _procs.add(_ProcedureEntry())),
                      ),

                      const SizedBox(height: 16),
                      const CharakSectionTitle(label: 'Senior review threshold'),
                      const SizedBox(height: 9),
                      const Text('Review procedure bills above', style: _fieldLabel),
                      const SizedBox(height: 7),
                      Row(children: [
                        const Text('₹', style: _rupee),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 120,
                          child: _PriceField(
                            controller: _thresholdCtrl,
                            hint: '500',
                            onChanged: () => setState(() {}),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 18),

                      // `.price-preview` — bgSubtle block, 13px/1.55 muted with
                      // the figures lifted to ink.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: const BoxDecoration(
                          color: CharakColors.bgSubtle,
                          borderRadius: BorderRadius.all(CharakRadius.card),
                        ),
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontFamily: CharakText.fontFamily,
                              fontSize: 13,
                              height: 1.55,
                              color: CharakColors.inkMuted,
                            ),
                            children: [
                              const TextSpan(text: 'Patients see '),
                              TextSpan(text: '₹$onlineShown', style: _previewStrong),
                              const TextSpan(text: ' online and '),
                              TextSpan(text: '₹$homeShown', style: _previewStrong),
                              const TextSpan(
                                text: ' for home visits for a 15-min consult — plus your fixed '
                                    'procedure rates and the senior-review note.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
                    ],
                  ],
                ),
              ),
            ),
            CharakCtaBar.single(
              CharakButton(
                label: 'Finish — go live',
                onPressed: (onlineValid && homeValid) ? _submit : null,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.field label` — 13px/600 ink.
const _fieldLabel = TextStyle(
  fontFamily: CharakText.fontFamily,
  fontSize: 13,
  fontWeight: FontWeight.w600,
  height: 1.4,
  color: CharakColors.ink,
);

/// The 18px/600 rupee glyph that leads each price row.
const _rupee = TextStyle(
  fontFamily: CharakText.fontFamily,
  fontSize: 18,
  fontWeight: FontWeight.w600,
  height: 1.3,
  color: CharakColors.ink,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// `.price-suffix` — 12.5px muted trailing unit.
const _suffix = TextStyle(
  fontFamily: CharakText.fontFamily,
  fontSize: 12.5,
  height: 1.4,
  color: CharakColors.inkMuted,
);

/// `.price-preview b` — the figures inside the preview block.
const _previewStrong = TextStyle(
  color: CharakColors.ink,
  fontWeight: FontWeight.w600,
);

/// `.input.tnum` — bordered numeric field on the control radius, tabular
/// figures. [height] drops to 38px for the compact `.proc-in` variant.
class _PriceField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final double height;
  final TextAlign align;
  final VoidCallback onChanged;
  const _PriceField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.height = 50,
    this.align = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      borderRadius: const BorderRadius.all(CharakRadius.button),
      border: Border.all(color: CharakColors.border),
    ),
    alignment: Alignment.center,
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: align,
      style: CharakText.body.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: hint,
        hintStyle: CharakText.body.copyWith(color: CharakColors.inkMuted),
      ),
      onChanged: (_) => onChanged(),
    ),
  );
}

/// Borderless 14px field used inside `.proc-price-row`, whose own border is
/// drawn by the row.
class _PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  const _PlainField({required this.controller, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: CharakText.body.copyWith(fontSize: 14),
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      hintText: hint,
      hintStyle: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted),
    ),
    onChanged: (_) => onChanged(),
  );
}
