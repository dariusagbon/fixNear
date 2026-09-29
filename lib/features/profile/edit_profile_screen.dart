import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/app_user.dart';
import '../../core/services/cloudinary_service.dart';
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

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    required this.profile,
    required this.uploader,
    required this.onSave,
    this.pickPhoto = pickPhotoWithImagePicker,
    super.key,
  });

  final AppUser profile;
  final ImageUploader uploader;
  final ProfileSaver onSave;
  final PhotoPicker pickPhoto;

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
