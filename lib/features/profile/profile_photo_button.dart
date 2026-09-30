import 'package:flutter/material.dart';

import '../../core/models/app_user.dart';
import '../../core/services/cloudinary_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/profile_avatar.dart';
import 'edit_profile_screen.dart';

/// The person's photo with a camera badge. Tapping it picks a new photo,
/// uploads it to Cloudinary and saves it to the profile straight away,
/// without opening Edit profile.
class ProfilePhotoButton extends StatefulWidget {
  const ProfilePhotoButton({
    required this.profile,
    required this.uploader,
    required this.onSave,
    this.pickPhoto = pickPhotoWithImagePicker,
    this.radius = 44,
    super.key,
  });

  final AppUser profile;
  final ImageUploader uploader;
  final ProfileSaver onSave;
  final PhotoPicker pickPhoto;
  final double radius;

  @override
  State<ProfilePhotoButton> createState() => _ProfilePhotoButtonState();
}

class _ProfilePhotoButtonState extends State<ProfilePhotoButton> {
  bool _uploading = false;

  void _say(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _change() async {
    if (!widget.uploader.isConfigured) {
      _say('Photo uploads are not set up for this app yet.');
      return;
    }
    final source = await chooseImageSource(context);
    if (source == null || !mounted) return;

    final PickedPhoto? photo;
    try {
      photo = await widget.pickPhoto(source);
    } catch (_) {
      if (mounted) _say('Could not open that photo. Try another one.');
      return;
    }
    if (photo == null || !mounted) return;
    if (photo.bytes.length > CloudinaryService.maxUploadBytes) {
      _say('Choose an image smaller than 5 MB.');
      return;
    }

    setState(() => _uploading = true);
    try {
      final url = await widget.uploader.uploadImage(
        bytes: photo.bytes,
        fileName: photo.fileName,
        folder: 'fixnear/avatars',
      );
      final profile = widget.profile;
      await widget.onSave(
        name: profile.name,
        phone: profile.phone,
        photoUrl: url,
      );
      if (mounted) _say('Profile photo updated.');
    } catch (error) {
      if (mounted) {
        _say(
          friendlyErrorMessage(
            error,
            'Could not update your photo. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.radius;
    final hasPhoto = (widget.profile.photoUrl ?? '').isNotEmpty;
    return Semantics(
      button: true,
      label: hasPhoto ? 'Change profile photo' : 'Add profile photo',
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _uploading ? null : _change,
        child: SizedBox(
          width: radius * 2 + 8,
          height: radius * 2 + 8,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ProfileAvatar(
                name: widget.profile.name,
                photoUrl: widget.profile.photoUrl,
                radius: radius,
              ),
              if (_uploading)
                SizedBox(
                  width: radius * 2,
                  height: radius * 2,
                  child: const CircularProgressIndicator(strokeWidth: 3),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.photo_camera_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
