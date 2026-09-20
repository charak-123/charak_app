import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:charak_core/charak_core.dart';

final _categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/categories') as List;
  return res.cast<Map<String, dynamic>>();
});

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();
  String? _categoryId;
  File?   _photo;
  bool    _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (img != null) setState(() => _photo = File(img.path));
  }

  // The photo is optional: the wireframe's Continue is ungated, and
  // CharakAvatar falls back to toned initials wherever a doctor has no image,
  // so a missing photo degrades cleanly instead of blocking onboarding.
  bool get _valid =>
      _nameCtrl.text.trim().length >= 2 && _categoryId != null;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      String? photoUrl;
      if (_photo != null) {
        // Non-fatal: client-side Storage uploads are unauthorised until they
        // move behind a backend endpoint (see verification_screen for why), and
        // a doctor without a photo still renders via CharakAvatar's initials.
        try {
          final supabase = Supabase.instance.client;
          final bytes = await _photo!.readAsBytes();
          final ext   = _photo!.path.split('.').last;
          final path  = 'doctor-photos/${DateTime.now().millisecondsSinceEpoch}.$ext';
          await supabase.storage.from('doctor-photos').uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: 'image/$ext'));
          photoUrl = supabase.storage.from('doctor-photos').getPublicUrl(path);
        } catch (_) {
          if (mounted) {
            showCharakToast(context,
                message: "Couldn't upload the photo — saved without it.",
                isError: true);
          }
        }
      }
      await ApiClient.instance.patch('/doctors/me', {
        'name': _nameCtrl.text.trim(),
        'category_id': _categoryId,
        'bio': _bioCtrl.text.trim(),
        if (photoUrl != null) 'photo_url': photoUrl,
      });
      if (mounted) context.go('/onboarding/verification');
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
    final cats = ref.watch(_categoriesProvider);

    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                // `.body` gutters + this screen's `padding-top:16px`.
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // `.step-dots` — step 1 of 3.
                    const CharakStepDots(current: 0),
                    const SizedBox(height: 10),
                    const Text('Set up your profile', style: CharakText.h1),
                    const SizedBox(height: 5),
                    Text('One screen, fill it once — this is what patients see in the directory.',
                        style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted)),
                    const SizedBox(height: 18),

                    CharakInput(label: 'Full name', placeholder: 'Dr. Aarav Mehta',
                        controller: _nameCtrl, onChanged: (_) => setState(() {})),
                    const SizedBox(height: 12),

                    const Text('Specialty', style: _fieldLabel),
                    const SizedBox(height: 7),
                    cats.when(
                      data: (list) => ShadSelect<String>(
                        placeholder: const Text('Select specialty'),
                        initialValue: _categoryId,
                        options: list.map((c) => ShadOption(value: c['id'] as String, child: Text(c['name'] as String))).toList(),
                        selectedOptionBuilder: (context, value) =>
                            Text(list.firstWhere((c) => c['id'] == value)['name'] as String),
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Failed to load specialties', style: CharakText.caption.copyWith(color: CharakColors.danger)),
                    ),
                    const SizedBox(height: 12),

                    const Text('Profile photo', style: _fieldLabel),
                    const SizedBox(height: 7),
                    CharakUploadTile(
                      icon: Icons.camera_alt_outlined,
                      label: 'Upload a clear, professional photo',
                      doneLabel: 'Photo added — patients see this in the directory',
                      done: _photo != null,
                      onTap: _pickPhoto,
                    ),
                    const SizedBox(height: 12),

                    CharakInput(label: 'Bio (1–2 lines)',
                        placeholder: 'General physician with 9 years in family practice.',
                        controller: _bioCtrl, maxLines: 4),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: CharakText.caption.copyWith(color: CharakColors.danger)),
                    ],
                  ],
                ),
              ),
            ),
            CharakCtaBar.single(
              CharakButton(
                label: 'Continue',
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

/// `.field label` — 13px/600 ink.
const _fieldLabel = TextStyle(
  fontFamily: CharakText.fontFamily,
  fontSize: 13,
  fontWeight: FontWeight.w600,
  height: 1.4,
  color: CharakColors.ink,
);
