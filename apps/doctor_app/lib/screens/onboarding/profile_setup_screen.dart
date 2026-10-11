import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:charak_core/charak_core.dart';

final _categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/categories') as List;
  return res.cast<Map<String, dynamic>>();
});

// Not a real category — a doctor whose specialty isn't in the fixed list
// (Ayurveda, Homeopathy, and anything else not yet a category) had no way to
// register at all. Picking this reveals a free-text field instead of sending
// a category_id; ops assigns the right category by hand during verification,
// same stance the admin dashboard already takes for an unmatched specialty.
const _otherSpecialtyValue = '__other__';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _specialtyOtherCtrl = TextEditingController();
  String? _categoryId;
  File?   _photo;
  bool    _loading = false;
  String? _error;

  bool get _isOther => _categoryId == _otherSpecialtyValue;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _phoneCtrl.dispose();
    _specialtyOtherCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    // This is only ever rendered at avatar size in the directory, and the
    // backend caps it at 5MB — so there is nothing to gain from a full-size
    // camera image, and a lot of upload time to lose.
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (img != null && mounted) setState(() => _photo = File(img.path));
  }

  // The photo is optional: the wireframe's Continue is ungated, and
  // CharakAvatar falls back to toned initials wherever a doctor has no image,
  // so a missing photo degrades cleanly instead of blocking onboarding.
  // A doctor who signed in with Google has no number yet; one who came in by
  // OTP already has a verified one.
  late final bool _needsPhone =
      (ref.read(authProvider).user?['phone'] as String?)?.isNotEmpty != true;
  String get _phoneDigits => _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');

  bool get _valid =>
      _nameCtrl.text.trim().length >= 2 && _categoryId != null &&
      (!_isOther || _specialtyOtherCtrl.text.trim().isNotEmpty) &&
      (!_needsPhone || _phoneDigits.length == 10);

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.instance.patch('/doctors/me', {
        'name': _nameCtrl.text.trim(),
        // Not sent for "Other" — there is no matching category_id, and
        // sending the sentinel value itself would fail the backend's uuid
        // check. application_details.specialty_other is what ops reads
        // instead while assigning the right category by hand.
        if (!_isOther) 'category_id': _categoryId,
        'bio': _bioCtrl.text.trim(),
        if (_needsPhone) 'phone': '+91$_phoneDigits',
        if (_isOther) 'application_details': {
          'specialty_other': _specialtyOtherCtrl.text.trim(),
        },
      });

      final photo = _photo;
      if (photo != null) {
        // Non-fatal, and deliberately after the profile write: a doctor
        // without a photo still renders via CharakAvatar's initials, so a
        // failed upload must not cost them the name and specialty they typed.
        try {
          final ext = photo.path.split('.').last.toLowerCase();
          await ApiClient.instance.postFile(
            '/uploads/doctor/photo',
            bytes: await photo.readAsBytes(),
            filename: photo.path.split('/').last,
            contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
          );
        } catch (_) {
          if (mounted) {
            showCharakToast(context,
                message: "Couldn't upload the photo — saved without it.",
                isError: true);
          }
        }
      }
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
      backgroundColor: CharakColors.ground,
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
                    const Text('Set up your profile', style: CharakText.titleLarge),
                    const SizedBox(height: 5),
                    Text('One screen, fill it once — this is what patients see in the directory.',
                        style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.inkMuted)),
                    const SizedBox(height: 18),

                    CharakInput(label: 'Full name', placeholder: 'Dr. Aarav Mehta',
                        controller: _nameCtrl, onChanged: (_) => setState(() {})),
                    const SizedBox(height: 12),

                    if (_needsPhone) ...[
                      CharakInput(label: 'Mobile number', placeholder: '98200 11223',
                          description: 'Patients and Charak ops use this to reach you.',
                          keyboardType: TextInputType.phone,
                          leading: Text('+91', style: CharakText.body.tabular),
                          controller: _phoneCtrl, onChanged: (_) => setState(() {})),
                      const SizedBox(height: 12),
                    ],

                    Text('Specialty', style: _fieldLabel),
                    const SizedBox(height: 7),
                    cats.when(
                      data: (list) => ShadSelect<String>(
                        placeholder: const Text('Select specialty'),
                        initialValue: _categoryId,
                        options: [
                          ...list.map((c) => ShadOption(value: c['id'] as String, child: Text(c['name'] as String))),
                          const ShadOption(value: _otherSpecialtyValue, child: Text('Other')),
                        ],
                        selectedOptionBuilder: (context, value) => Text(
                          value == _otherSpecialtyValue
                              ? 'Other'
                              : list.firstWhere((c) => c['id'] == value)['name'] as String,
                        ),
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Failed to load specialties', style: CharakText.caption.copyWith(color: CharakColors.danger)),
                    ),
                    if (_isOther) ...[
                      const SizedBox(height: 10),
                      CharakInput(
                        label: 'What do you practise?',
                        placeholder: 'e.g., Ayurveda, Homeopathy',
                        description: "Not in the list yet — our team assigns the right category when they review your application.",
                        controller: _specialtyOtherCtrl,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: 12),

                    Text('Profile photo', style: _fieldLabel),
                    const SizedBox(height: 7),
                    CharakUploadTile(
                      icon: LucideIcons.camera,
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
final _fieldLabel = CharakText.caption.copyWith(color: CharakColors.ink, fontWeight: FontWeight.w600);
