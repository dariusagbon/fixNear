import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixnear/core/models/app_user.dart';
import 'package:fixnear/core/models/marketplace_models.dart';
import 'package:fixnear/core/services/cloudinary_service.dart';
import 'package:fixnear/core/services/location_service.dart';
import 'package:fixnear/core/services/marketplace_service.dart';
import 'package:fixnear/core/services/push_notifications.dart';
import 'package:fixnear/core/theme/app_theme.dart';
import 'package:fixnear/core/utils/formatters.dart';
import 'package:fixnear/core/utils/geo.dart';
import 'package:fixnear/features/auth/auth_gate.dart';
import 'package:fixnear/features/customer/customer_marketplace_screen.dart';
import 'package:fixnear/features/jobs/job_detail_screen.dart';
import 'package:fixnear/features/notifications/notification_host.dart';
import 'package:fixnear/features/profile/edit_profile_screen.dart';

import 'dart:convert';

import 'package:fixnear/features/provider/provider_home_screen.dart';

void main() {
  testWidgets('customer can find a provider and submit a service request', (
    WidgetTester tester,
  ) async {
    final repository = _FakeMarketplaceRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerMarketplaceScreen(
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available providers'), findsOneWidget);
    expect(find.text('Provider One'), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Repair a leaking kitchen faucet',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Davao City');
    await tester.tap(find.text('Choose date and time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${DateTime.now().day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    expect(repository.createdCategory, 'Plumbing');
    expect(repository.createdDescription, 'Repair a leaking kitchen faucet');
    expect(repository.createdProvider?.id, 'provider-1');
    expect(repository.createdScheduledAt, isNotNull);
    expect(find.text('My requests'), findsOneWidget);
  });

  testWidgets('sign-in form can switch to account registration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Account type'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);

    await tester.tap(find.text('Customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Service provider').last);
    await tester.pumpAndSettle();

    expect(find.text('Main service'), findsOneWidget);
    expect(find.text('Service area'), findsOneWidget);
    expect(find.text('Starting price (PHP)'), findsOneWidget);
  });

  testWidgets('provider can accept an open request', (
    WidgetTester tester,
  ) async {
    final repository = _FakeMarketplaceRepository()
      ..openRequests = [
        ServiceRequest(
          id: 'request-1',
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          category: 'Plumbing',
          description: 'Repair a leaking faucet',
          serviceArea: 'Davao City',
          status: 'requested',
          createdAt: DateTime(2026),
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderHomeScreen(
          providerUid: 'provider-1',
          providerName: 'Provider One',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repair a leaking faucet'), findsOneWidget);
    await tester.tap(find.text('Send quote'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '850');
    await tester.enterText(
      find.byType(TextFormField).last,
      'Parts and labor included',
    );
    await tester.tap(find.text('Send quote').last);
    await tester.pumpAndSettle();

    expect(repository.quotedRequestId, 'request-1');
    expect(repository.quotedProviderUid, 'provider-1');
    expect(repository.quotePrice, 850);
  });

  testWidgets('customer can accept a provider quote', (
    WidgetTester tester,
  ) async {
    final repository = _FakeMarketplaceRepository()
      ..customerRequests = [
        ServiceRequest(
          id: 'request-2',
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          category: 'Electrical',
          description: 'Replace a light fixture',
          serviceArea: 'Davao City',
          status: RequestStatus.quoted,
          createdAt: DateTime(2026),
        ),
      ]
      ..quotesByRequest['request-2'] = [
        ProviderQuote(
          providerUid: 'provider-2',
          providerName: 'Provider Two',
          price: 1200,
          note: 'Includes materials and installation.',
          createdAt: DateTime(2026),
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerMarketplaceScreen(
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          repository: repository,
        ),
      ),
    );
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();

    expect(find.text('Provider Two · ₱1,200'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(repository.acceptedRequestId, 'request-2');
    expect(repository.acceptedQuote?.providerUid, 'provider-2');
  });

  testWidgets('provider jobs tab shows an empty state with no jobs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderHomeScreen(
          providerUid: 'provider-1',
          providerName: 'Provider One',
          repository: _FakeMarketplaceRepository(),
        ),
      ),
    );
    await tester.tap(find.text('My jobs'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmed earnings'), findsOneWidget);
    expect(find.text('Accepted jobs will appear here.'), findsOneWidget);
  });

  testWidgets('customer confirms before cancelling a request', (
    WidgetTester tester,
  ) async {
    final repository = _FakeMarketplaceRepository()
      ..customerRequests = [
        ServiceRequest(
          id: 'request-3',
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          category: 'Cleaning',
          description: 'Deep clean the living room',
          serviceArea: 'Davao City',
          status: RequestStatus.requested,
          createdAt: DateTime(2026),
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerMarketplaceScreen(
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          repository: repository,
        ),
      ),
    );
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep request'));
    await tester.pumpAndSettle();
    expect(repository.cancelledRequestId, isNull);

    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request').last);
    await tester.pumpAndSettle();
    expect(repository.cancelledRequestId, 'request-3');
  });

  testWidgets('failed quote acceptance shows a friendly message', (
    WidgetTester tester,
  ) async {
    final repository = _FakeMarketplaceRepository()
      ..acceptQuoteError = StateError('This quote is no longer available.')
      ..customerRequests = [
        ServiceRequest(
          id: 'request-4',
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          category: 'Electrical',
          description: 'Install an outlet',
          serviceArea: 'Davao City',
          status: RequestStatus.quoted,
          createdAt: DateTime(2026),
        ),
      ]
      ..quotesByRequest['request-4'] = [
        ProviderQuote(
          providerUid: 'provider-2',
          providerName: 'Provider Two',
          price: 600,
          note: 'Same-day install.',
          createdAt: DateTime(2026),
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerMarketplaceScreen(
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          repository: repository,
        ),
      ),
    );
    await tester.tap(find.text('Requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(find.text('This quote is no longer available.'), findsOneWidget);
  });

  testWidgets('customer account shows profile details and edit action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerMarketplaceScreen(
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          repository: _FakeMarketplaceRepository(),
          profile: AppUser(
            id: 'customer-1',
            email: 'casey@example.com',
            name: 'Casey Customer',
            role: UserRole.customer,
            phone: '09123456789',
          ),
          imageUploader: CloudinaryService(
            config: const CloudinaryConfig(cloudName: '', uploadPreset: ''),
          ),
          onSaveProfile: ({required name, phone, photoUrl}) async {},
        ),
      ),
    );
    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();

    expect(find.text('casey@example.com'), findsOneWidget);
    expect(find.text('09123456789'), findsOneWidget);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsOneWidget);
  });

  group('notifications', () {
    ServiceRequest acceptedJob() => ServiceRequest(
      id: 'job-7',
      customerUid: 'customer-1',
      customerName: 'Casey Customer',
      category: 'Plumbing',
      description: 'Fix a leaking faucet',
      serviceArea: 'Davao City',
      status: RequestStatus.accepted,
      providerUid: 'provider-1',
      providerName: 'Provider One',
      quotedPrice: 850,
      createdAt: DateTime(2026),
    );

    Widget host(
      _FakePush push,
      _FakeMarketplaceRepository repository, {
      UserRole role = UserRole.customer,
    }) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: NotificationHost(
        push: push,
        repository: repository,
        uid: role == UserRole.customer ? 'customer-1' : 'provider-1',
        name: 'Someone',
        role: role,
        child: const Scaffold(body: Text('Home')),
      ),
    );

    testWidgets('registers the device silently on sign-in', (tester) async {
      final push = _FakePush();
      await tester.pumpWidget(host(push, _FakeMarketplaceRepository()));
      await tester.pumpAndSettle();
      expect(push.registered, ['customer-1']);
      expect(push.permissionRequests, 0);
    });

    testWidgets('tapping a notification opens the job', (tester) async {
      final push = _FakePush();
      final repository = _FakeMarketplaceRepository()
        ..customerRequests = [acceptedJob()];
      await tester.pumpWidget(host(push, repository));
      await tester.pumpAndSettle();

      push.opened.add('job-7');
      await tester.pumpAndSettle();
      expect(find.byType(JobDetailScreen), findsOneWidget);
      expect(find.text('Fix a leaking faucet'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
    });

    testWidgets('a notification that launched the app opens the job', (
      tester,
    ) async {
      final push = _FakePush()..initialJobId = 'job-7';
      final repository = _FakeMarketplaceRepository()
        ..providerJobs = [acceptedJob()];
      await tester.pumpWidget(host(push, repository, role: UserRole.provider));
      await tester.pumpAndSettle();
      expect(find.byType(JobDetailScreen), findsOneWidget);
      // The provider sees their next step on the detail page.
      expect(find.text('On the way'), findsWidgets);
    });

    testWidgets('foreground notifications show a banner with View', (
      tester,
    ) async {
      final push = _FakePush();
      final repository = _FakeMarketplaceRepository()
        ..customerRequests = [acceptedJob()];
      await tester.pumpWidget(host(push, repository));
      await tester.pumpAndSettle();

      push.foreground.add(
        const ForegroundNotice(
          title: 'Provider One is on the way',
          body: 'Plumbing · Davao City',
          requestId: 'job-7',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Provider One is on the way'), findsOneWidget);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.byType(JobDetailScreen), findsOneWidget);
    });

    testWidgets('a missing job shows a plain message', (tester) async {
      final push = _FakePush();
      await tester.pumpWidget(host(push, _FakeMarketplaceRepository()));
      await tester.pumpAndSettle();
      push.opened.add('gone');
      await tester.pumpAndSettle();
      expect(find.text('This job no longer exists.'), findsOneWidget);
    });

    testWidgets('customers are asked for permission after their first post', (
      tester,
    ) async {
      final push = _FakePush()..canAsk = true;
      final repository = _FakeMarketplaceRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerMarketplaceScreen(
            customerUid: 'customer-1',
            customerName: 'Casey Customer',
            repository: repository,
            push: push,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Nothing is asked at launch.
      expect(find.text('Get updates on your job?'), findsNothing);

      await tester.ensureVisible(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Repair a leaking kitchen faucet',
      );
      await tester.enterText(find.byType(TextFormField).last, 'Davao City');
      await tester.tap(find.text('Choose date and time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(find.text('Get updates on your job?'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(push.permissionRequests, 1);
      expect(push.registered, ['customer-1']);
    });

    testWidgets('providers are asked for permission when going online', (
      tester,
    ) async {
      final push = _FakePush()..canAsk = true;
      final repository = _FakeMarketplaceRepository()
        ..ownProfile = const ProviderProfile(
          id: 'provider-1',
          name: 'Provider One',
          category: 'Plumbing',
          serviceArea: 'Davao City',
          startingPrice: 500,
          isAvailable: false,
        );
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderHomeScreen(
            providerUid: 'provider-1',
            providerName: 'Provider One',
            repository: repository,
            push: push,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(repository.availabilityChanges, [true]);
      expect(find.text('Get new jobs as they come in?'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(push.permissionRequests, 0);
    });

    testWidgets('devices that were already asked are not asked again', (
      tester,
    ) async {
      final push = _FakePush()..canAsk = false;
      final repository = _FakeMarketplaceRepository()
        ..ownProfile = const ProviderProfile(
          id: 'provider-1',
          name: 'Provider One',
          category: 'Plumbing',
          serviceArea: 'Davao City',
          startingPrice: 500,
          isAvailable: false,
        );
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderHomeScreen(
            providerUid: 'provider-1',
            providerName: 'Provider One',
            repository: repository,
            push: push,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('distance matching', () {
    const downtown = LatLngPoint(7.0654, 125.6076);
    const lanang = LatLngPoint(7.0996, 125.6317);
    const toril = LatLngPoint(7.0187, 125.4966);

    ServiceRequest openJob(
      String id,
      String description, {
      LatLngPoint? at,
      String? providerUid,
    }) => ServiceRequest(
      id: id,
      customerUid: 'customer-1',
      customerName: 'Casey Customer',
      category: 'Plumbing',
      description: description,
      serviceArea: 'Davao City',
      status: RequestStatus.requested,
      providerUid: providerUid,
      createdAt: DateTime(2026),
      latitude: at?.latitude,
      longitude: at?.longitude,
    );

    ProviderProfile me({LatLngPoint? base}) => ProviderProfile(
      id: 'provider-1',
      name: 'Provider One',
      category: 'Plumbing',
      serviceArea: 'Davao City',
      startingPrice: 500,
      isAvailable: true,
      baseLocation: base,
    );

    Widget providerHome(
      _FakeMarketplaceRepository repository, {
      LocationService? location,
    }) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: ProviderHomeScreen(
        providerUid: 'provider-1',
        providerName: 'Provider One',
        repository: repository,
        location: location ?? _FakeLocation(),
      ),
    );

    testWidgets('job board: direct first, nearby by distance, far hidden', (
      tester,
    ) async {
      final repository = _FakeMarketplaceRepository()
        ..ownProfile = me(base: downtown)
        ..openRequests = [
          openJob('far', 'Far job in Toril', at: toril),
          openJob('near', 'Job in Lanang', at: lanang),
          openJob('old', 'Old job without a pin'),
          openJob(
            'direct',
            'Sent to me directly',
            at: toril,
            providerUid: 'provider-1',
          ),
        ];
      await tester.pumpWidget(providerHome(repository));
      await tester.pumpAndSettle();

      final order = [
        'Sent to me directly',
        'Job in Lanang',
        'Old job without a pin',
      ].map((text) => tester.getTopLeft(find.text(text)).dy).toList();
      expect(order, orderedEquals([...order]..sort()));
      expect(find.text('Far job in Toril'), findsNothing);
      expect(find.text('4.6 km away'), findsOneWidget);
      expect(find.text('Sent directly to you'), findsOneWidget);
      expect(find.text('Set your base location'), findsNothing);
    });

    testWidgets('job board asks for a base location when there is none', (
      tester,
    ) async {
      final repository = _FakeMarketplaceRepository()
        ..ownProfile = me()
        ..openRequests = [openJob('far', 'Far job in Toril', at: toril)];
      await tester.pumpWidget(providerHome(repository));
      await tester.pumpAndSettle();
      // Nothing is hidden without a base; the prompt links to Service.
      expect(find.text('Far job in Toril'), findsOneWidget);
      await tester.tap(find.text('Set your base location'));
      await tester.pumpAndSettle();
      expect(find.text('Service radius: 10 km'), findsOneWidget);
    });

    testWidgets('service tab saves base location and radius', (tester) async {
      final repository = _FakeMarketplaceRepository()..ownProfile = me();
      await tester.pumpWidget(
        providerHome(repository, location: _FakeLocation(here: lanang)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Service'));
      await tester.pumpAndSettle();

      expect(find.text('No base location yet'), findsOneWidget);
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Base location: 7.0996'), findsOneWidget);

      // Drag the slider to the far right: 50 km.
      await tester.ensureVisible(find.byType(Slider));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Service radius: 50 km'), findsOneWidget);

      await tester.ensureVisible(find.text('Save settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(repository.savedSettings?.baseLocation, lanang);
      expect(repository.savedSettings?.serviceRadiusKm, 50);
      expect(find.text('Service settings saved.'), findsOneWidget);
    });

    testWidgets('service tab explains when location is unavailable', (
      tester,
    ) async {
      final repository = _FakeMarketplaceRepository()..ownProfile = me();
      await tester.pumpWidget(
        providerHome(
          repository,
          location: _FakeLocation(
            failure: 'Allow location access to use your current location.',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(
        find.text('Allow location access to use your current location.'),
        findsOneWidget,
      );
    });

    testWidgets('customers see provider distances once location is known', (
      tester,
    ) async {
      final location = _FakeLocation(here: downtown, permitted: false);
      final repository = _FakeMarketplaceRepository()
        ..providers = [
          const ProviderProfile(
            id: 'p-far',
            name: 'Far Provider',
            category: 'Plumbing',
            serviceArea: 'Toril',
            startingPrice: 500,
            isAvailable: true,
            baseLocation: toril,
          ),
          const ProviderProfile(
            id: 'p-near',
            name: 'Near Provider',
            category: 'Plumbing',
            serviceArea: 'Lanang',
            startingPrice: 500,
            isAvailable: true,
            baseLocation: lanang,
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerMarketplaceScreen(
            customerUid: 'customer-1',
            customerName: 'Casey Customer',
            repository: repository,
            location: location,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Not asked at launch; no distances yet.
      expect(location.requests, 0);
      expect(find.textContaining('km away'), findsNothing);

      await tester.tap(find.text('Show distances'));
      await tester.pumpAndSettle();
      expect(location.requests, 1);
      expect(find.text('Lanang · 4.6 km away'), findsOneWidget);
      expect(find.text('Toril · 13 km away'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Near Provider')).dy,
        lessThan(tester.getTopLeft(find.text('Far Provider')).dy),
      );
    });

    testWidgets('posting a job with the current location saves the pin', (
      tester,
    ) async {
      final repository = _FakeMarketplaceRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerMarketplaceScreen(
            customerUid: 'customer-1',
            customerName: 'Casey Customer',
            repository: repository,
            location: _FakeLocation(here: lanang),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request service').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pinned at 7.0996'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).first,
        'Repair a leaking kitchen faucet',
      );
      await tester.enterText(find.byType(TextFormField).last, 'Davao City');
      await tester.tap(find.text('Choose date and time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Send request'));
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(repository.createdLatitude, lanang.latitude);
      expect(repository.createdLongitude, lanang.longitude);
    });
  });

  group('job photos and provider profile', () {
    // A valid 1x1 PNG.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    );

    Future<void> fillForm(WidgetTester tester) async {
      await tester.enterText(
        find.byType(TextFormField).first,
        'Repair a leaking kitchen faucet',
      );
      await tester.enterText(find.byType(TextFormField).last, 'Davao City');
      await tester.tap(find.text('Choose date and time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Send request'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
    }

    testWidgets('customers attach photos that upload when the job is sent', (
      tester,
    ) async {
      final repository = _FakeMarketplaceRepository();
      final uploader = _RecordingUploader();
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerMarketplaceScreen(
            customerUid: 'customer-1',
            customerName: 'Casey Customer',
            repository: repository,
            location: _FakeLocation(),
            imageUploader: uploader,
            pickJobPhotos: () async => [
              PickedPhoto(bytes: png, fileName: 'sink.png'),
              PickedPhoto(bytes: png, fileName: 'pipe.png'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request service').first);
      await tester.pumpAndSettle();
      await fillForm(tester);

      await tester.ensureVisible(find.text('Add photos'));
      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 5 photos'), findsOneWidget);
      // Nothing uploads until the request is sent.
      expect(uploader.folders, isEmpty);

      await tester.tap(find.byTooltip('Remove photo 2'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 5 photos'), findsOneWidget);

      await send(tester);
      expect(uploader.folders, ['fixnear/service-requests']);
      expect(repository.createdPhotoUrls, [
        'https://res.cloudinary.com/demo/image/upload/v1/photo-1.jpg',
      ]);
    });

    testWidgets('photo attachment is hidden until uploads are configured', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerMarketplaceScreen(
            customerUid: 'customer-1',
            customerName: 'Casey Customer',
            repository: _FakeMarketplaceRepository(),
            location: _FakeLocation(),
            imageUploader: _RecordingUploader(configured: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request service').first);
      await tester.pumpAndSettle();
      expect(find.text('Add photos'), findsNothing);
    });

    testWidgets('providers see job photos on their board', (tester) async {
      final repository = _FakeMarketplaceRepository()
        ..openRequests = [
          ServiceRequest(
            id: 'with-photos',
            customerUid: 'customer-1',
            customerName: 'Casey Customer',
            category: 'Plumbing',
            description: 'Leaking pipe under the sink',
            serviceArea: 'Davao City',
            status: RequestStatus.requested,
            createdAt: DateTime(2026),
            photoUrls: const [
              'https://res.cloudinary.com/demo/image/upload/v1/a.jpg',
              'https://res.cloudinary.com/demo/image/upload/v1/b.jpg',
            ],
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderHomeScreen(
            providerUid: 'provider-1',
            providerName: 'Provider One',
            repository: repository,
            location: _FakeLocation(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Open job photo 1 of 2'), findsOneWidget);
    });

    testWidgets('providers open Edit profile from their name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderHomeScreen(
            providerUid: 'provider-1',
            providerName: 'Provider One',
            repository: _FakeMarketplaceRepository(),
            location: _FakeLocation(),
            profile: AppUser(
              id: 'provider-1',
              email: 'pat@example.com',
              name: 'Pat Plumbing',
              role: UserRole.provider,
            ),
            imageUploader: _RecordingUploader(),
            onSaveProfile: ({required name, phone, photoUrl}) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pat Plumbing'), findsOneWidget);
      await tester.tap(find.text('Pat Plumbing'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });
  });

  group('layouts', () {
    final profile = AppUser(
      id: 'customer-1',
      email: 'casey@example.com',
      name: 'Casey Customer',
      role: UserRole.customer,
    );
    // Built inside each test: constructing an HTTP client outside a test
    // zone fails under flutter_test.
    CloudinaryService uploader() => CloudinaryService(
      config: const CloudinaryConfig(cloudName: '', uploadPreset: ''),
    );

    _FakeMarketplaceRepository busyRepository() => _FakeMarketplaceRepository()
      ..customerRequests = [
        ServiceRequest(
          id: 'request-q',
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          category: 'Electrical',
          description: 'Replace a ceiling light fixture in the living room',
          serviceArea: 'Poblacion District, Davao City',
          status: RequestStatus.quoted,
          createdAt: DateTime(2026),
          scheduledAt: DateTime(2026, 10, 2, 9, 30),
        ),
        ServiceRequest(
          id: 'request-d',
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          category: 'Plumbing',
          description: 'Fix a leaking faucet',
          serviceArea: 'Davao City',
          status: RequestStatus.completed,
          providerUid: 'provider-1',
          providerName: 'Provider One',
          quotedPrice: 1200,
          createdAt: DateTime(2026),
        ),
      ]
      ..quotesByRequest['request-q'] = [
        ProviderQuote(
          providerUid: 'provider-2',
          providerName: 'Provider Two With A Long Business Name',
          price: 1200,
          note: 'Includes materials, installation and cleanup afterwards.',
          createdAt: DateTime(2026),
        ),
      ]
      ..openRequests = [
        ServiceRequest(
          id: 'request-o',
          customerUid: 'customer-1',
          customerName: 'Casey Customer',
          category: 'Cleaning',
          description: 'Deep clean a two-bedroom apartment before moving out',
          serviceArea: 'Lanang, Davao City',
          status: RequestStatus.requested,
          providerUid: 'provider-1',
          createdAt: DateTime(2026),
        ),
      ];

    Future<void> pumpAt(WidgetTester tester, double width, Widget home) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: home),
      );
      await tester.pumpAndSettle();
    }

    Future<void> checkGuidelines(WidgetTester tester) async {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }

    for (final width in [360.0, 1280.0]) {
      testWidgets('sign-in and provider registration at ${width.toInt()}px', (
        tester,
      ) async {
        await pumpAt(tester, width, const LoginScreen());
        await checkGuidelines(tester);
        await tester.tap(find.text('Create an account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Customer'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Service provider').last);
        await tester.pumpAndSettle();
        await checkGuidelines(tester);
      });

      testWidgets('customer screens at ${width.toInt()}px', (tester) async {
        await pumpAt(
          tester,
          width,
          CustomerMarketplaceScreen(
            customerUid: 'customer-1',
            customerName: 'Casey Customer',
            repository: busyRepository(),
            profile: profile,
            imageUploader: uploader(),
            onSaveProfile: ({required name, phone, photoUrl}) async {},
          ),
        );
        await checkGuidelines(tester);

        await tester.tap(find.text('Requests'));
        await tester.pumpAndSettle();
        // The quoted job and the unpaid job both wait on the customer.
        final needsYou = find.byIcon(Icons.priority_high_rounded);
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('Electrical'),
              matching: find.byType(Card),
            ),
            matching: needsYou,
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Pay cash'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('Pay cash'),
              matching: find.byType(Card),
            ),
            matching: needsYou,
          ),
          findsOneWidget,
        );
        await checkGuidelines(tester);

        await tester.tap(find.text('Account').last);
        await tester.pumpAndSettle();
        await checkGuidelines(tester);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Request service').first);
        await tester.pumpAndSettle();
        expect(find.text('Send request'), findsOneWidget);
        await checkGuidelines(tester);
      });

      testWidgets('provider screens at ${width.toInt()}px', (tester) async {
        await pumpAt(
          tester,
          width,
          ProviderHomeScreen(
            providerUid: 'provider-1',
            providerName: 'Provider One',
            repository: busyRepository()
              ..ownProfile = const ProviderProfile(
                id: 'provider-1',
                name: 'Provider One',
                category: 'Plumbing',
                serviceArea: 'Davao City',
                startingPrice: 500,
                isAvailable: true,
              ),
            location: _FakeLocation(),
          ),
        );
        // A job sent directly to this provider waits on them.
        expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
        await checkGuidelines(tester);
        await tester.tap(find.text('My jobs'));
        await tester.pumpAndSettle();
        await checkGuidelines(tester);
        await tester.tap(find.text('Service'));
        await tester.pumpAndSettle();
        expect(find.text('Save settings'), findsOneWidget);
        await checkGuidelines(tester);
      });

      testWidgets('edit profile at ${width.toInt()}px', (tester) async {
        await pumpAt(
          tester,
          width,
          EditProfileScreen(
            profile: profile,
            uploader: uploader(),
            onSave: ({required name, phone, photoUrl}) async {},
          ),
        );
        await checkGuidelines(tester);
      });
    }
  });

  test('formatters produce readable values', () {
    expect(formatPeso(0), '₱0');
    expect(formatPeso(850), '₱850');
    expect(formatPeso(1200), '₱1,200');
    expect(formatPeso(1234567), '₱1,234,567');
    expect(
      formatDateTime(DateTime(2026, 3, 4, 14, 5)),
      'Mar 4, 2026 · 2:05 PM',
    );
    expect(
      formatDateTime(DateTime(2026, 12, 25, 0, 30)),
      'Dec 25, 2026 · 12:30 AM',
    );
    expect(requestStatusLabel(RequestStatus.onTheWay), 'On the way');
    expect(initialsFor('Casey Customer'), 'CC');
    expect(initialsFor('  '), '?');
  });

  test('service requests preserve selected location data', () {
    final request = ServiceRequest.fromMap({
      'customerUid': 'customer-1',
      'customerName': 'Casey Customer',
      'category': 'Plumbing',
      'description': 'Fix kitchen sink',
      'serviceArea': 'Davao City',
      'locationLabel': 'Davao City Center',
      'latitude': 7.1907,
      'longitude': 125.4553,
      'status': RequestStatus.requested,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    }, 'request-42');

    expect(request.locationLabel, 'Davao City Center');
    expect(request.latitude, 7.1907);
    expect(request.longitude, 125.4553);
  });
}

class _FakeMarketplaceRepository implements MarketplaceRepository {
  String? createdCategory;
  String? createdDescription;
  double? createdLatitude;
  List<String>? createdPhotoUrls;
  double? createdLongitude;
  DateTime? createdScheduledAt;
  ProviderProfile? createdProvider;
  List<ServiceRequest> openRequests = [];
  String? quotedRequestId;
  String? quotedProviderUid;
  int? quotePrice;
  List<ServiceRequest> customerRequests = [];
  List<ServiceRequest> providerJobs = [];
  ProviderProfile? ownProfile;
  final List<bool> availabilityChanges = [];
  ({
    String category,
    String serviceArea,
    int startingPrice,
    LatLngPoint? baseLocation,
    double serviceRadiusKm,
  })?
  savedSettings;
  final Map<String, List<ProviderQuote>> quotesByRequest = {};
  String? acceptedRequestId;
  ProviderQuote? acceptedQuote;
  Object? acceptQuoteError;
  String? cancelledRequestId;

  List<ProviderProfile>? providers;

  @override
  Stream<List<ProviderProfile>> watchProviders() => Stream.value(
    providers ??
        [
          const ProviderProfile(
            id: 'provider-1',
            name: 'Provider One',
            category: 'Plumbing',
            serviceArea: 'Davao City',
            startingPrice: 500,
            isAvailable: true,
          ),
        ],
  );

  @override
  Stream<List<ServiceRequest>> watchCustomerRequests(String customerUid) =>
      Stream.value(customerRequests);

  @override
  Stream<ProviderProfile?> watchProviderProfile(String providerUid) =>
      Stream.value(ownProfile);

  @override
  Future<void> setProviderAvailability(
    String providerUid,
    bool isAvailable,
  ) async {
    availabilityChanges.add(isAvailable);
  }

  @override
  Future<void> updateProviderServiceSettings({
    required String providerUid,
    required String category,
    required String serviceArea,
    required int startingPrice,
    required LatLngPoint? baseLocation,
    required double serviceRadiusKm,
  }) async {
    savedSettings = (
      category: category,
      serviceArea: serviceArea,
      startingPrice: startingPrice,
      baseLocation: baseLocation,
      serviceRadiusKm: serviceRadiusKm,
    );
  }

  @override
  Stream<ServiceRequest?> watchRequest(String requestId) => Stream.value(
    [
      ...customerRequests,
      ...openRequests,
      ...providerJobs,
    ].where((request) => request.id == requestId).firstOrNull,
  );

  @override
  Stream<List<ServiceRequest>> watchOpenRequests(String providerUid) =>
      Stream.value(openRequests);

  @override
  Stream<List<ServiceRequest>> watchProviderJobs(String providerUid) =>
      Stream.value(providerJobs);

  @override
  Stream<List<ProviderQuote>> watchQuotes(String requestId) =>
      Stream.value(quotesByRequest[requestId] ?? []);

  @override
  Stream<List<JobMessage>> watchMessages(String requestId) =>
      const Stream.empty();

  @override
  Future<void> createRequest({
    required String customerUid,
    required String customerName,
    required String category,
    required String description,
    required String serviceArea,
    String? locationLabel,
    double? latitude,
    double? longitude,
    ProviderProfile? provider,
    DateTime? scheduledAt,
    List<String> photoUrls = const [],
  }) async {
    createdCategory = category;
    createdDescription = description;
    createdLatitude = latitude;
    createdPhotoUrls = photoUrls;
    createdLongitude = longitude;
    createdProvider = provider;
    createdScheduledAt = scheduledAt;
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    cancelledRequestId = requestId;
  }

  @override
  Future<void> declineRequest(String requestId, String providerUid) async {}

  @override
  Future<void> sendQuote({
    required String requestId,
    required String providerUid,
    required String providerName,
    required int price,
    required String note,
  }) async {
    quotedRequestId = requestId;
    quotedProviderUid = providerUid;
    quotePrice = price;
  }

  @override
  Future<void> acceptQuote(String requestId, ProviderQuote quote) async {
    if (acceptQuoteError != null) throw acceptQuoteError!;
    acceptedRequestId = requestId;
    acceptedQuote = quote;
  }

  @override
  Future<void> advanceRequest(String requestId, String status) async {}

  @override
  Future<void> confirmCompletion(String requestId, String customerUid) async {}

  @override
  Future<void> sendMessage({
    required String requestId,
    required String senderUid,
    required String senderName,
    required String text,
  }) async {}

  @override
  Future<void> recordCashPayment(String requestId, String customerUid) async {}

  @override
  Future<void> confirmCashPayment(String requestId, String providerUid) async {}
}

class _FakePush implements PushNotifications {
  bool canAsk = false;
  bool grant = true;
  int permissionRequests = 0;
  final List<String> registered = [];
  final List<String> unregistered = [];
  String? initialJobId;
  final opened = StreamController<String>.broadcast();
  final foreground = StreamController<ForegroundNotice>.broadcast();

  @override
  Future<bool> canAskPermission() async => canAsk;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    canAsk = false;
    return grant;
  }

  @override
  Future<void> registerDevice(String uid) async => registered.add(uid);

  @override
  Future<void> unregisterDevice(String uid) async => unregistered.add(uid);

  @override
  Stream<String> get openedJobIds => opened.stream;

  @override
  Future<String?> takeInitialJobId() async {
    final id = initialJobId;
    initialJobId = null;
    return id;
  }

  @override
  Stream<ForegroundNotice> get foregroundNotices => foreground.stream;
}

class _FakeLocation implements LocationService {
  _FakeLocation({this.here, this.permitted = true, this.failure});

  final LatLngPoint? here;
  final bool permitted;
  final String? failure;
  int requests = 0;

  @override
  Future<LatLngPoint?> currentIfPermitted() async => permitted ? here : null;

  @override
  Future<LatLngPoint> requestCurrent() async {
    requests++;
    final point = here;
    if (failure != null || point == null) {
      throw LocationUnavailable(failure ?? 'Location unavailable.');
    }
    return point;
  }
}

class _RecordingUploader implements ImageUploader {
  _RecordingUploader({this.configured = true});

  final bool configured;
  final List<String?> folders = [];

  @override
  bool get isConfigured => configured;

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    String? folder,
    String? publicId,
  }) async {
    folders.add(folder);
    return 'https://res.cloudinary.com/demo/image/upload/v1/photo-${folders.length}.jpg';
  }
}
