import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:charak_core/charak_core.dart';

class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  final _licenseCtrl = TextEditingController();
  PlatformFile? _doc;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result == null || !mounted) return;
    final picked = result.files.single;
    // storage.LIMITS caps a document at 15MB, and rejects it only after the
    // whole file has been uploaded. Say so before that happens.
    const maxBytes = 15 * 1024 * 1024;
    if (picked.size > maxBytes) {
      showCharakToast(context,
          message: 'That file is '
              '${(picked.size / (1024 * 1024)).toStringAsFixed(1)}MB — the '
              'limit is 15MB. Try a photo of the certificate instead of a scan.');
      return;
    }
    setState(() => _doc = picked);
  }

  // The document is required: a licence number alone is not something ops can
  // verify. The upload goes through `POST /uploads/doctor/verification-document`
  // — a client-side Storage write is rejected, because these apps authenticate
  // with a FastAPI JWT rather than a Supabase auth session.
  bool get _valid => _licenseCtrl.text.trim().isNotEmpty && _doc != null;

  Future<void> _submit() async {
    final doc = _doc;
    if (doc == null || doc.bytes == null) {
      setState(() => _error = 'Attach your medical licence or degree certificate');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      // Licence number first: the document upload sets verification_status back
      // to pending, so it must be the last write of the pair.
      await ApiClient.instance.post('/doctors/me/verification', {
        'license_number': _licenseCtrl.text.trim(),
      });

      final ext = (doc.extension ?? 'pdf').toLowerCase();
      await ApiClient.instance.postFile(
        '/uploads/doctor/verification-document',
        bytes: doc.bytes!,
        filename: doc.name,
        contentType: ext == 'pdf'
            ? 'application/pdf'
            : 'image/${ext == 'jpg' ? 'jpeg' : ext}',
      );
      if (mounted) context.go('/onboarding/verification-pending');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CharakColors.ground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // `.step-dots` — step 2 of 3.
                    const CharakStepDots(current: 1),
                    const SizedBox(height: 10),
                    const Text('Verify your license', style: CharakText.titleLarge),
                    const SizedBox(height: 5),
                    Text('Manual check by our team — usually within 1 working day. You can explore the app meanwhile.',
                        style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted)),
                    const SizedBox(height: 18),

                    CharakInput(
                      label: 'Medical council registration no.',
                      placeholder: 'MCI-118342',
                      controller: _licenseCtrl,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),

                    Text('Degree certificate / council ID',
                        style: CharakText.caption.copyWith(color: CharakColors.ink, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 7),
                    CharakUploadTile(
                      icon: Icons.upload_outlined,
                      label: 'Upload photo or PDF',
                      doneLabel: _doc?.name ?? 'attached',
                      done: _doc != null,
                      onTap: _pickDocument,
                    ),
                    const SizedBox(height: 14),

                    // `.exp-line` — 15px primary shield beside 12.5px muted copy.
                    const CharakHintLine(
                      icon: Icons.verified_user_outlined,
                      text: 'Your registration number, degree and ID are checked by a human on '
                          'our team. Nothing is automated.',
                    ),

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
                label: 'Submit for verification',
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
