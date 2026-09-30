import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fixnear/core/models/app_user.dart';
import 'package:fixnear/core/services/cloudinary_service.dart';
import 'package:fixnear/features/profile/edit_profile_screen.dart';

final _profile = AppUser(
  id: 'customer-1',
  email: 'casey@example.com',
  name: 'Casey Customer',
  role: UserRole.customer,
);

class _FakeUploader implements ImageUploader {
  _FakeUploader({this.isConfigured = true});

  @override
  final bool isConfigured;
  Uint8List? uploadedBytes;
  String? uploadedFolder;

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    String? folder,
    String? publicId,
  }) async {
    uploadedBytes = bytes;
    uploadedFolder = folder;
    return 'https://res.cloudinary.com/demo/image/upload/v1/fixnear/avatars/a.jpg';
  }
}

class _SavedProfile {
  _SavedProfile(this.name, this.phone, this.photoUrl);

  final String name;
  final String? phone;
  final String? photoUrl;
}

Widget _host(Widget screen) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

void main() {
  group('CloudinaryService', () {
    test(
      'uploads with the unsigned preset and returns the secure URL',
      () async {
        late http.BaseRequest sent;
        final client = MockClient.streaming((request, bodyStream) async {
          sent = request;
          final body = await bodyStream.bytesToString();
          expect(body, contains('name="upload_preset"'));
          expect(body, contains('fixnear-unsigned'));
          expect(body, contains('name="folder"'));
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'secure_url':
                      'https://res.cloudinary.com/demo/image/upload/v1/a.jpg',
                }),
              ),
            ),
            200,
          );
        });
        final service = CloudinaryService(
          httpClient: client,
          config: const CloudinaryConfig(
            cloudName: 'demo',
            uploadPreset: 'fixnear-unsigned',
          ),
        );

        final url = await service.uploadImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'me.jpg',
          folder: 'fixnear/avatars',
        );

        expect(
          sent.url.toString(),
          'https://api.cloudinary.com/v1_1/demo/image/upload',
        );
        expect(url, 'https://res.cloudinary.com/demo/image/upload/v1/a.jpg');
      },
    );

    test('reports a friendly error when Cloudinary rejects the upload', () {
      final service = CloudinaryService(
        httpClient: MockClient((_) async => http.Response('{"error":{}}', 400)),
        config: const CloudinaryConfig(
          cloudName: 'demo',
          uploadPreset: 'preset',
        ),
      );
      expect(
        service.uploadImage(
          bytes: Uint8List.fromList([1]),
          fileName: 'me.jpg',
          folder: 'f',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('refuses uploads when not configured or too large', () {
      expect(
        CloudinaryService(
          config: const CloudinaryConfig(cloudName: '', uploadPreset: ''),
        ).isConfigured,
        isFalse,
      );
      final service = CloudinaryService(
        httpClient: MockClient((_) async => http.Response('', 500)),
        config: const CloudinaryConfig(
          cloudName: 'demo',
          uploadPreset: 'preset',
        ),
      );
      expect(
        service.uploadImage(
          bytes: Uint8List(CloudinaryService.maxUploadBytes + 1),
          fileName: 'big.jpg',
          folder: 'f',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('avatar URLs get a square face crop', () {
      expect(
        cloudinaryAvatarUrl(
          'https://res.cloudinary.com/demo/image/upload/v1/a.jpg',
          size: 128,
        ),
        'https://res.cloudinary.com/demo/image/upload/'
        'c_fill,g_face,w_128,h_128,q_auto,f_auto/v1/a.jpg',
      );
      expect(
        cloudinaryAvatarUrl('https://example.com/a.jpg'),
        'https://example.com/a.jpg',
      );
    });
  });

  group('EditProfileScreen', () {
    testWidgets('uploads a new photo and saves the profile', (tester) async {
      final uploader = _FakeUploader();
      _SavedProfile? saved;
      // A valid 1x1 transparent PNG.
      final photo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );

      await tester.pumpWidget(
        _host(
          EditProfileScreen(
            profile: _profile,
            uploader: uploader,
            onSave: ({required name, phone, photoUrl}) async {
              saved = _SavedProfile(name, phone, photoUrl);
            },
            pickPhoto: (_) async =>
                PickedPhoto(bytes: photo, fileName: 'me.jpg'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      // On non-web platforms a source picker is shown first.
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();
      expect(find.text('Change photo'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Casey C.');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '+63 912 345 6789',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(uploader.uploadedBytes, photo);
      expect(uploader.uploadedFolder, 'fixnear/avatars');
      expect(saved?.name, 'Casey C.');
      expect(saved?.phone, '+63 912 345 6789');
      expect(saved?.photoUrl, startsWith('https://res.cloudinary.com/'));
      expect(find.text('Profile updated.'), findsOneWidget);
      expect(find.byType(EditProfileScreen), findsNothing);
    });

    testWidgets('rejects an invalid phone number', (tester) async {
      var saveCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: _profile,
            uploader: _FakeUploader(),
            onSave: ({required name, phone, photoUrl}) async => saveCalls++,
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'call me');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid phone number'), findsOneWidget);
      expect(saveCalls, 0);
    });

    testWidgets('explains when photo uploads are not configured', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: _profile,
            uploader: _FakeUploader(isConfigured: false),
            onSave: ({required name, phone, photoUrl}) async {},
          ),
        ),
      );
      expect(find.text('Photo uploads are not set up yet.'), findsOneWidget);
    });
  });
}
