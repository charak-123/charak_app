import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

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

  bool get _valid => _licenseCtrl.text.trim().isNotEmpty && _doc != null;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      final supabase = Supabase.instance.client;
      final ext  = _doc!.extension ?? 'pdf';
      final path = 'verification-docs/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('verification-docs').uploadBinary(
        path, _doc!.bytes!,
        fileOptions: FileOptions(contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext'),
      );
      // Signed URL (TTL 10 years for ops review)
      final docUrl = await supabase.storage.from('verification-docs')
          .createSignedUrl(path, 60 * 60 * 24 * 365 * 10);

      await ApiClient.instance.post('/doctors/me/verification', {
        'license_number': _licenseCtrl.text.trim(),
        'document_url': docUrl,
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
      appBar: AppBar(title: const Text('Verify Credentials')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CharakSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('We manually verify all doctors.\nThis typically takes 24-48 hours.',
                  style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.lg),

              Text('Medical Council Registration Number *',
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.xs),
              TextField(
                controller: _licenseCtrl,
                decoration: const InputDecoration(hintText: 'e.g. MH-2023-12345'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: CharakSpacing.base),

              Text('Upload license or medical certificate *',
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              const SizedBox(height: CharakSpacing.xs),
              GestureDetector(
                onTap: _pickDocument,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: CharakSpacing.lg, horizontal: CharakSpacing.base),
                  decoration: BoxDecoration(
                    color: CharakColors.bgSubtle,
                    borderRadius: BorderRadius.all(CharakRadius.button),
                    border: Border.all(color: _doc != null ? CharakColors.success : CharakColors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _doc != null ? Icons.check_circle : Icons.upload_file,
                        color: _doc != null ? CharakColors.success : CharakColors.inkMuted,
                        size: 32,
                      ),
                      const SizedBox(height: CharakSpacing.sm),
                      Text(
                        _doc != null ? _doc!.name : 'Tap to upload (JPG, PNG, PDF)',
                        style: CharakText.caption.copyWith(
                            color: _doc != null ? CharakColors.success : CharakColors.inkMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: CharakSpacing.base),

              Container(
                padding: const EdgeInsets.all(CharakSpacing.md),
                decoration: BoxDecoration(
                  color: CharakColors.bgSubtle,
                  borderRadius: BorderRadius.all(CharakRadius.card),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, color: CharakColors.inkMuted, size: 16),
                    const SizedBox(width: CharakSpacing.sm),
                    Expanded(
                      child: Text('Your information is secure and only reviewed by our team.',
                          style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: CharakSpacing.base),
                Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
              ],

              const Spacer(),
              CharakButton(
                label: 'Submit for Verification',
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
