import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Uploads images and returns their public HTTPS URL.
abstract interface class ImageUploader {
  bool get isConfigured;

  /// Uploads [bytes]. [folder] overrides the configured default folder.
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    String? folder,
    String? publicId,
  });
}

/// Cloudinary account settings for unsigned uploads.
///
/// Defaults to FixNear's account (see [defaultCloudName]). To use another
/// account, set them at build time:
///
/// ```sh
/// flutter run \
///   --dart-define=CLOUDINARY_CLOUD_NAME=your-cloud \
///   --dart-define=CLOUDINARY_UPLOAD_PRESET=your-unsigned-preset \
///   --dart-define=CLOUDINARY_FOLDER=fixnear   # optional default folder
/// ```
///
/// Never ship the Cloudinary API secret in the app; unsigned presets exist so
/// that clients can upload without it.
class CloudinaryConfig {
  const CloudinaryConfig({
    required this.cloudName,
    required this.uploadPreset,
    this.folder,
  });

  /// FixNear's Cloudinary account. Neither value is a secret: the cloud name
  /// is part of every image URL and the preset is unsigned. Override both
  /// with `--dart-define` to use another account.
  static const defaultCloudName = 'gp7e9yws';
  static const defaultUploadPreset = 'fixnearAvatar';

  static CloudinaryConfig fromEnvironment() {
    const folder = String.fromEnvironment('CLOUDINARY_FOLDER');
    return const CloudinaryConfig(
      cloudName: String.fromEnvironment(
        'CLOUDINARY_CLOUD_NAME',
        defaultValue: defaultCloudName,
      ),
      uploadPreset: String.fromEnvironment(
        'CLOUDINARY_UPLOAD_PRESET',
        defaultValue: defaultUploadPreset,
      ),
      folder: folder == '' ? null : folder,
    );
  }

  final String cloudName;
  final String uploadPreset;

  /// Used when an upload doesn't name its own folder.
  final String? folder;

  bool get isConfigured =>
      cloudName.trim().isNotEmpty && uploadPreset.trim().isNotEmpty;
}

/// Uploads images to Cloudinary with an unsigned upload preset.
class CloudinaryService implements ImageUploader {
  CloudinaryService({CloudinaryConfig? config, http.Client? httpClient})
    : _config = config ?? CloudinaryConfig.fromEnvironment(),
      _httpClient = httpClient ?? http.Client();

  /// Largest image accepted before upload, in bytes.
  static const maxUploadBytes = 5 * 1024 * 1024;

  final CloudinaryConfig _config;
  final http.Client _httpClient;

  @override
  bool get isConfigured => _config.isConfigured;

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    String? folder,
    String? publicId,
  }) async {
    // Messages here are shown to users, so they stay plain-language.
    if (!isConfigured) {
      throw StateError('Photo uploads are not set up for this app yet.');
    }
    if (bytes.isEmpty) {
      throw ArgumentError('Choose an image to upload.');
    }
    if (bytes.length > maxUploadBytes) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }

    final targetFolder = (folder ?? _config.folder)?.trim();
    final request =
        http.MultipartRequest(
            'POST',
            Uri.https(
              'api.cloudinary.com',
              '/v1_1/${_config.cloudName.trim()}/image/upload',
            ),
          )
          ..fields['upload_preset'] = _config.uploadPreset.trim()
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );
    if (targetFolder != null && targetFolder.isNotEmpty) {
      request.fields['folder'] = targetFolder;
    }
    if (publicId != null && publicId.trim().isNotEmpty) {
      request.fields['public_id'] = publicId.trim();
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _httpClient.send(request),
      );
    } catch (_) {
      throw StateError('Could not upload the photo. Check your connection.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Cloudinary rejected the photo upload.');
    }
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw StateError('Cloudinary returned an unexpected response.');
    }
    final url = body is Map<String, dynamic> ? body['secure_url'] : null;
    if (url is! String || !url.startsWith('https://')) {
      throw StateError('Cloudinary returned an unexpected response.');
    }
    return url;
  }
}

/// Returns a Cloudinary delivery URL resized and face-cropped to a square of
/// [size] pixels. URLs from other hosts are returned unchanged.
String cloudinaryAvatarUrl(String url, {int size = 256}) {
  const marker = '/image/upload/';
  if (!url.contains('res.cloudinary.com') || !url.contains(marker)) return url;
  return url.replaceFirst(
    marker,
    '${marker}c_fill,g_face,w_$size,h_$size,q_auto,f_auto/',
  );
}

/// A Cloudinary delivery URL limited to [width] pixels wide, for thumbnails.
String cloudinaryThumbnailUrl(String url, {int width = 320}) {
  const marker = '/image/upload/';
  if (!url.contains('res.cloudinary.com') || !url.contains(marker)) return url;
  return url.replaceFirst(marker, '${marker}c_limit,w_$width,q_auto,f_auto/');
}
