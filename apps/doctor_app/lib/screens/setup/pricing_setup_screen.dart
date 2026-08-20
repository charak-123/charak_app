import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

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

  List<_ProcedureEntry> _procs = [_ProcedureEntry()];

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
    for (final p in _procs) p.dispose();
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

  Widget _feeSection(String label, TextEditingController baseCtrl, TextEditingController extraCtrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CharakText.h2.copyWith(color: CharakColors.ink)),
        const SizedBox(height: CharakSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: baseCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Base fee (₹)', hintText: '500'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: CharakSpacing.sm),
            Expanded(
              child: TextField(
                controller: extraCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Extra/15 min (₹)', hintText: '100'),
              ),
            ),
          ],
        ),
        const SizedBox(height: CharakSpacing.xs),
        Text('Base fee covers first 15 min. Extra time billed per additional 15 min.',
            style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDoctorInfo) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final onlineValid = !_offersOnline || (_onlineBaseCtrl.text.isNotEmpty);
    final homeValid   = !_offersHome   || (_homeBaseCtrl.text.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('Pricing & Procedures')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_offersOnline) ...[
                _feeSection('Online Consult', _onlineBaseCtrl, _onlineExtraCtrl),
                const Divider(height: CharakSpacing.xl),
              ],
              if (_offersHome) ...[
                _feeSection('Home Visit', _homeBaseCtrl, _homeExtraCtrl),
                const Divider(height: CharakSpacing.xl),

                // Procedures
                Text('Procedures you perform on home visits',
                    style: CharakText.h2.copyWith(color: CharakColors.ink)),
                const SizedBox(height: CharakSpacing.xs),
                Text('Fixed prices shown to patients upfront. Only procedures actually performed are billed.',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                const SizedBox(height: CharakSpacing.base),
                ..._procs.asMap().entries.map((entry) {
                  final i = entry.key;
                  final p = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: CharakSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: p.nameCtrl,
                            decoration: const InputDecoration(hintText: 'e.g. ECG'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: CharakSpacing.sm),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: p.priceCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(hintText: '₹ price'),
                          ),
                        ),
                        if (_procs.length > 1)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: CharakColors.danger),
                            onPressed: () {
                              p.dispose();
                              setState(() => _procs.removeAt(i));
                            },
                          ),
                      ],
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () => setState(() => _procs.add(_ProcedureEntry())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add procedure'),
                ),
                const Divider(height: CharakSpacing.xl),

                // Senior review threshold
                Text('Senior review threshold', style: CharakText.h2.copyWith(color: CharakColors.ink)),
                const SizedBox(height: CharakSpacing.xs),
                Text('Procedure bills above this amount require senior doctor review before patient pays.',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                const SizedBox(height: CharakSpacing.sm),
                TextField(
                  controller: _thresholdCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: '₹ 5000', prefixText: '₹ '),
                ),
                const Divider(height: CharakSpacing.xl),
              ],

              if (_error != null) ...[
                Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
                const SizedBox(height: CharakSpacing.base),
              ],

              CharakButton(
                label: 'Go Live',
                onPressed: (onlineValid && homeValid) ? _submit : null,
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
