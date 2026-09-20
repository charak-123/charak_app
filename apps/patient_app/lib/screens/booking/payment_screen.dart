import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const PaymentScreen({super.key, required this.bookingId});
  @override
  ConsumerState<PaymentScreen> createState() => _State();
}

class _State extends ConsumerState<PaymentScreen> {
  bool _loading = false;
  Map<String, dynamic>? _order;
  bool _cardTab = false;
  final _upiCtrl = TextEditingController();

  @override
  void dispose() {
    _upiCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _createOrder();
  }

  Future<void> _createOrder() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.post(
          '/payments/${widget.bookingId}/order', {});
      setState(() => _order = res as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    if (_order == null) return;
    setState(() => _loading = true);
    try {
      final key = _order!['razorpay_key'] as String? ?? '';

      if (key.startsWith('stub')) {
        // Dev mode: stub-complete the payment directly
        await ApiClient.instance.post(
            '/payments/${widget.bookingId}/stub-complete', {});
        if (mounted) context.go('/booking/${widget.bookingId}/confirmed');
        return;
      }

      // Production: open Razorpay checkout
      // razorpay_flutter SDK opens the checkout sheet here
      // razorpay.open({
      //   'key': key,
      //   'amount': _order!['amount'],
      //   'order_id': _order!['razorpay_order_id'],
      //   'name': 'Charak',
      //   'description': 'Consultation fee',
      // });
      // Handle payment success/failure via razorpay callbacks
      // On success: context.go('/booking/${widget.bookingId}/confirmed')

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add Razorpay key to enable live payments')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _order != null ? (_order!['amount'] as int) / 100 : 0.0;
    final isStub =
        (_order?['razorpay_key'] as String? ?? '').startsWith('stub');

    return Scaffold(
      backgroundColor: CharakColors.bg,
      appBar: const CharakTopBar(title: 'Payment'),
      body: _loading && _order == null
          // Initial order fetch — content is arriving, so `.skel` stands in.
          ? const _PaymentLoading()
          : Column(children: [
              Expanded(child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  // `.sheet-title` row — amount left, "Secure" badge right.
                  Row(children: [
                    Expanded(
                      child: Text('Pay ₹${amount.toStringAsFixed(0)}',
                          style: CharakText.h2.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ),
                    const CharakBadge(
                        label: 'Secure',
                        variant: CharakBadgeVariant.muted,
                        icon: Icons.lock_outline),
                  ]),
                  const SizedBox(height: 4),
                  const Text('Consultation fee · paid before the visit',
                      style: charakHintStyle),
                  const SizedBox(height: 14),

                  CharakSegmented<bool>(
                    value: _cardTab,
                    onChanged: (v) => setState(() => _cardTab = v),
                    segments: const [
                      CharakSegment(value: false, label: 'UPI'),
                      CharakSegment(value: true, label: 'Card'),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (!_cardTab) ...[
                    CharakField(
                      label: 'UPI ID',
                      controller: _upiCtrl,
                      placeholder: 'yourname@bank',
                      hint: 'or pay with',
                    ),
                    const SizedBox(height: 12),
                    // `.two-col` — 46px ghost buttons side by side.
                    Row(children: [
                      Expanded(
                        child: CharakButton(
                          label: 'GPay',
                          outlined: true,
                          onPressed: () => _notice('Opening GPay…'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CharakButton(
                          label: 'PhonePe',
                          outlined: true,
                          onPressed: () => _notice('Opening PhonePe…'),
                        ),
                      ),
                    ]),
                  ] else ...[
                    const CharakField(
                      label: 'Card number',
                      placeholder: '4242 4242 4242 4242',
                      tabular: true,
                    ),
                    const SizedBox(height: 10),
                    const Row(children: [
                      Expanded(
                        child: CharakField(
                            label: 'Expiry', placeholder: '08/28', tabular: true),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: CharakField(
                            label: 'CVV', placeholder: '123', tabular: true),
                      ),
                    ]),
                  ],

                  const SizedBox(height: 14),
                  const CharakNoteBanner(
                    icon: Icons.verified_user_outlined,
                    tone: CharakStatusTone.success,
                    message: 'Payment is processed securely via Razorpay. The '
                        'booking is confirmed the moment payment lands.',
                  ),
                ],
              )),

              CharakCtaBar.single(
                CharakButton(
                  label: isStub
                      ? 'Confirm payment (dev stub)'
                      : 'Pay ₹${amount.toStringAsFixed(0)}',
                  isLoading: _loading,
                  onPressed: _order != null ? _pay : null,
                ),
              ),
            ]),
    );
  }

  void _notice(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// Loading state for the initial order fetch: `.skel` blocks in the shape of
/// the amount header, the UPI/Card segmented control and the field below it.
class _PaymentLoading extends StatelessWidget {
  const _PaymentLoading();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          CharakSkeleton(width: 148, height: 21),
          Spacer(),
          CharakSkeleton(width: 78, height: 22, radius: 11),
        ]),
        SizedBox(height: 10),
        CharakSkeleton(width: 234, height: 13),
        SizedBox(height: 18),
        CharakSkeleton(height: 40, radius: 12),
        SizedBox(height: 18),
        CharakSkeleton(width: 64, height: 13),
        SizedBox(height: 8),
        CharakSkeleton(height: 46, radius: 12),
        SizedBox(height: 14),
        Row(children: [
          Expanded(child: CharakSkeleton(height: 46, radius: 12)),
          SizedBox(width: 10),
          Expanded(child: CharakSkeleton(height: 46, radius: 12)),
        ]),
      ],
    ),
  );
}
