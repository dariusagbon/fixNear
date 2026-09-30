import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

<<<<<<< HEAD
class CloudinaryConfig {
  const CloudinaryConfig({
    required this.cloudName,
    required this.uploadPreset,
    this.folder,
  });

  static CloudinaryConfig fromEnvironment() {
    return CloudinaryConfig(
      cloudName: const String.fromEnvironment(
        'CLOUDINARY_CLOUD_NAME',
        defaultValue: '',
      ),
      uploadPreset: const String.fromEnvironment(
        'CLOUDINARY_UPLOAD_PRESET',
        defaultValue: '',
      ),
      folder: const String.fromEnvironment(
        'CLOUDINARY_FOLDER',
        defaultValue: '',
      ),
    );
  }

  final String cloudName;
  final String uploadPreset;
  final String? folder;

  bool get isConfigured =>
      cloudName.trim().isNotEmpty && uploadPreset.trim().isNotEmpty;
}

class CloudinaryService {
  CloudinaryService({CloudinaryConfig? config, http.Client? httpClient})
      : _config = config ?? CloudinaryConfig.fromEnvironment(),
        _httpClient = httpClient ?? http.Client();

  final CloudinaryConfig _config;
  final http.Client _httpClient;
=======
/// Uploads images and returns their public HTTPS URL.
abstract interface class ImageUploader {
  bool get isConfigured;
>>>>>>> 904e434f9190bd218d6d4749e605770a566009fc

  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
<<<<<<< HEAD
    String? folder,
    String? publicId,
  }) async {
    if (!_config.isConfigured) {
      throw StateError(
        'Cloudinary is not configured. Set CLOUDINARY_CLOUD_NAME and '
        'CLOUDINARY_UPLOAD_PRESET via --dart-define or pass a config object.',
      );
    }

    final cloudName = _config.cloudName.trim();
    final uploadPreset = _config.uploadPreset.trim();
    final targetFolder = (folder ?? _config.folder)?.trim();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
    );

    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    request.fields['upload_preset'] = uploadPreset;

    if (targetFolder != null && targetFolder.isNotEmpty) {
      request.fields['folder'] = targetFolder;
    }

    if (publicId != null && publicId.trim().isNotEmpty) {
      request.fields['public_id'] = publicId.trim();
    }

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Cloudinary upload failed (${response.statusCode}): $body',
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected Cloudinary response: $body');
    }

    final secureUrl = decoded['secure_url'];
    if (secureUrl is! String || secureUrl.isEmpty) {
      throw StateError(
        'Cloudinary upload succeeded but did not return a usable URL: $body',
      );
    }

    return secureUrl;
  }
}
=======
    required String folder,
  });
}

/// Uploads images to Cloudinary with an *unsigned* upload preset.
///
/// Configure it at build time so no secrets live in source control:
///
/// ```sh
/// flutter run \
///   --dart-define=CLOUDINARY_CLOUD_NAME=your-cloud \
///   --dart-define=CLOUDINARY_UPLOAD_PRESET=your-unsigned-preset
/// ```
///
/// Never ship the Cloudinary API secret in the app; unsigned presets exist so
/// that clients can upload without it.
class CloudinaryService implements ImageUploader {
  CloudinaryService({
    http.Client? client,
    String? cloudName,
    String? uploadPreset,
  }) : _client = client ?? http.Client(),
       _cloudName = cloudName ?? _defaultCloudName,
       _uploadPreset = uploadPreset ?? _defaultUploadPreset;

  static const _defaultCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
  );
  static const _defaultUploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
  );

  /// Largest image accepted before upload, in bytes.
  static const maxUploadBytes = 5 * 1024 * 1024;

  final http.Client _client;
  final String _cloudName;
  final String _uploadPreset;

  @override
  bool get isConfigured => _cloudName.isNotEmpty && _uploadPreset.isNotEmpty;

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String folder,
  }) async {
    if (!isConfigured) {
      throw StateError('Photo uploads are not set up for this app yet.');
    }
    if (bytes.isEmpty) {
      throw ArgumentError('Choose an image to upload.');
    }
    if (bytes.length > maxUploadBytes) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }

    final request =
        http.MultipartRequest(
            'POST',
            Uri.https('api.cloudinary.com', '/v1_1/$_cloudName/image/upload'),
          )
          ..fields['upload_preset'] = _uploadPreset
          ..fields['folder'] = folder
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } catch (_) {
      throw StateError('Could not upload the photo. Check your connection.');
    }

    if (response.statusCode != 200) {
      throw StateError('Cloudinary rejected the photo upload.');
    }
    final body = jsonDecode(response.body);
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
>>>>>>> 904e434f9190bd218d6d4749e605770a566009fc
