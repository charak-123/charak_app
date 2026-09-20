import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    if (result != null) setState(() => _doc = result.files.single);
  }

  // TODO(backend): the document should be required. It is optional only
  // because client-side Supabase Storage uploads cannot be authorised — these
  // apps authenticate with a custom FastAPI JWT, not a Supabase auth session,
  // so the client carries just the anon key and RLS rejects the insert (403).
  // Restore `&& _doc != null` once uploads go through a backend endpoint.
  bool get _valid => _licenseCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      String? docUrl;
      if (_doc != null && _doc!.bytes != null) {
        // Non-fatal: a failed upload must not strand the doctor mid-onboarding.
        try {
          final supabase = Supabase.instance.client;
          final ext  = _doc!.extension ?? 'pdf';
          final path = 'verification-docs/${DateTime.now().millisecondsSinceEpoch}.$ext';
          await supabase.storage.from('verification-docs').uploadBinary(
            path, _doc!.bytes!,
            fileOptions: FileOptions(contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext'),
          );
          // Signed URL (TTL 10 years for ops review)
          docUrl = await supabase.storage.from('verification-docs')
              .createSignedUrl(path, 60 * 60 * 24 * 365 * 10);
        } catch (_) {
          if (mounted) {
            showCharakToast(context,
                message: "Couldn't attach the document — submitted without it.",
                isError: true);
          }
        }
      }

      await ApiClient.instance.post('/doctors/me/verification', {
        'license_number': _licenseCtrl.text.trim(),
        if (docUrl != null) 'document_url': docUrl,
      });
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
                    // `.step-dots` — step 2 of 3.
                    const CharakStepDots(current: 1),
                    const SizedBox(height: 10),
                    const Text('Verify your license', style: CharakText.h1),
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

                    const Text('Degree certificate / council ID',
                        style: TextStyle(
                          fontFamily: CharakText.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: CharakColors.ink,
                        )),
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
