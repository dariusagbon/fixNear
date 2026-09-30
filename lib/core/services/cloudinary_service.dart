import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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

  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
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
