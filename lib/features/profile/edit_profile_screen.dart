import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/app_user.dart';
import '../../core/services/cloudinary_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/profile_avatar.dart';

/// Image bytes chosen by the user, ready to upload.
class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

typedef PhotoPicker = Future<PickedPhoto?> Function(ImageSource source);

typedef ProfileSaver = Future<void> Function({
  required String name,
  String? phone,
  String? photoUrl,
});

Future<PickedPhoto?> pickPhotoWithImagePicker(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 85,
  );
  if (file == null) return null;
  return PickedPhoto(bytes: await file.readAsBytes(), fileName: file.name);
}

/// Picks several photos (e.g. for a job). Returns an empty list if the user
/// cancels.
typedef MultiPhotoPicker = Future<List<PickedPhoto>> Function();

Future<List<PickedPhoto>> pickPhotosWithImagePicker() async {
  final files = await ImagePicker().pickMultiImage(
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
    limit: maxJobPhotos,
  );
  return [
    for (final file in files.take(maxJobPhotos))
      PickedPhoto(bytes: await file.readAsBytes(), fileName: file.name),
  ];
}

/// Most photos a customer can attach to one job (also enforced by rules).
const maxJobPhotos = 5;

/// Account-level actions shown at the bottom of Edit profile.
class AccountControls {
  const AccountControls({
    required this.emailVerified,
    required this.sendVerificationEmail,
    required this.deleteAccount,
  });

  final bool emailVerified;
  final Future<void> Function() sendVerificationEmail;

  /// Deletes the account after confirming [password]. Throws a
  /// [StateError] with a user-facing message when it can't.
  final Future<void> Function(String password) deleteAccount;
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    required this.profile,
    required this.uploader,
    required this.onSave,
    this.pickPhoto = pickPhotoWithImagePicker,
    this.account,
    super.key,
  });

  final AppUser profile;
  final ImageUploader uploader;
  final ProfileSaver onSave;
  final PhotoPicker pickPhoto;

  /// Email verification and account deletion. Hidden when null.
  final AccountControls? account;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.profile.name);
  late final _phoneController = TextEditingController(
    text: widget.profile.phone ?? '',
  );
  PickedPhoto? _newPhoto;
  bool _removePhoto = false;
  bool _saving = false;
  String? _error;

  String? get _currentPhotoUrl => _removePhoto ? null : widget.profile.photoUrl;

  bool get _hasPhoto => _newPhoto != null || _currentPhotoUrl != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Center(child: _buildPhoto()),
                  const SizedBox(height: 8),
                  Center(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _saving ? null : _choosePhoto,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(_hasPhoto ? 'Change photo' : 'Add photo'),
                        ),
                        if (_hasPhoto)
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    _newPhoto = null;
                                    _removePhoto = true;
                                  }),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                  ),
                  if (!widget.uploader.isConfigured)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Photo uploads are not set up yet.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) return 'Enter your name';
                      if (name.length > 80) return 'Use 80 characters or fewer';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phoneController,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                      hintText: '+63 912 345 6789',
                    ),
                    validator: (value) {
                      final phone = value?.trim() ?? '';
                      if (phone.isEmpty) return null;
                      final digits = phone.replaceAll(RegExp(r'\D'), '');
                      final validChars = RegExp(r'^\+?[\d\s()-]+$');
                      return validChars.hasMatch(phone) &&
                              phone.length <= 20 &&
                              digits.length >= 7 &&
                              digits.length <= 15
                          ? null
                          : 'Enter a valid phone number';
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    initialValue: widget.profile.email,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save changes'),
                  ),
                  if (widget.account != null) ...[
                    const SizedBox(height: 32),
                    const Divider(),
                    _AccountSection(
                      email: widget.profile.email,
                      controls: widget.account!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    const radius = 52.0;
    final photo = _newPhoto;
    if (photo != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: MemoryImage(photo.bytes),
        onBackgroundImageError: (_, _) {
          if (!mounted) return;
          setState(() {
            _newPhoto = null;
            _error = 'That file is not a supported image. Try another one.';
          });
        },
      );
    }
    return ProfileAvatar(
      name: _nameController.text.isEmpty
          ? widget.profile.name
          : _nameController.text,
      photoUrl: _currentPhotoUrl,
      radius: radius,
    );
  }

  Future<void> _choosePhoto() async {
    if (!widget.uploader.isConfigured) {
      setState(() => _error = 'Photo uploads are not set up for this app yet.');
      return;
    }
    final source = kIsWeb
        ? ImageSource.gallery
        : await showModalBottomSheet<ImageSource>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose from gallery'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Take a photo'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                ],
              ),
            ),
          );
    if (source == null || !mounted) return;

    try {
      final photo = await widget.pickPhoto(source);
      if (photo == null || !mounted) return;
      if (photo.bytes.length > CloudinaryService.maxUploadBytes) {
        setState(() => _error = 'Choose an image smaller than 5 MB.');
        return;
      }
      setState(() {
        _newPhoto = photo;
        _removePhoto = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not open that photo. Try another one.');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var photoUrl = _currentPhotoUrl;
      final photo = _newPhoto;
      if (photo != null) {
        photoUrl = await widget.uploader.uploadImage(
          bytes: photo.bytes,
          fileName: photo.fileName,
          folder: 'fixnear/avatars',
        );
      }
      await widget.onSave(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        photoUrl: photoUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated.')));
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = friendlyErrorMessage(
          error,
          'Could not save your profile. Try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AccountSection extends StatefulWidget {
  const _AccountSection({required this.email, required this.controls});

  final String email;
  final AccountControls controls;

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  bool _sent = false;

  Future<void> _sendVerification() async {
    try {
      await widget.controls.sendVerificationEmail();
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not send the email. Try again.'),
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(controls: widget.controls),
    );
    if (deleted == true && mounted) {
      // The account is gone; return to the sign-in screen.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Account', style: textTheme.titleMedium),
        if (!widget.controls.emailVerified) ...[
          const SizedBox(height: 8),
          Text(
            _sent
                ? 'Verification email sent to ${widget.email}. Open the link, then come back.'
                : 'Your email address is not verified yet.',
            style: textTheme.bodyMedium,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _sendVerification,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: Text(_sent ? 'Send again' : 'Send verification email'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.error,
            side: const BorderSide(color: AppTheme.error),
          ),
          onPressed: _delete,
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete account'),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.controls});

  final AccountControls controls;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password to confirm.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controls.deleteAccount(_password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyErrorMessage(
            error,
            'Could not delete your account. Try again.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'This permanently deletes your profile and sign-in, cancels '
            'your open requests and removes your provider listing. It '
            "can't be undone. Past jobs stay in the other person's "
            'history without your name.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _confirm(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppTheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Keep account'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Delete account'),
        ),
      ],
    );
  }
}
