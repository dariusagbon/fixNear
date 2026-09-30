import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fixnear/core/services/cloudinary_service.dart';

class _MockHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({
      'secure_url': 'https://res.cloudinary.com/demo/image/upload/sample.jpg',
    });

    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  test('uploadImage returns secure_url for valid config', () async {
    final service = CloudinaryService(
      config: const CloudinaryConfig(
        cloudName: 'demo',
        uploadPreset: 'fixnear_preset',
      ),
      httpClient: _MockHttpClient(),
    );

    final url = await service.uploadImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'test.png',
    );

    expect(url, 'https://res.cloudinary.com/demo/image/upload/sample.jpg');
  });

  test('uploadImage throws when Cloudinary config is missing', () async {
    final service = CloudinaryService(
      config: const CloudinaryConfig(cloudName: '', uploadPreset: ''),
      httpClient: _MockHttpClient(),
    );

    await expectLater(
      () => service.uploadImage(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'test.png',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
