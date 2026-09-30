import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixnear/core/models/app_user.dart';
import 'package:fixnear/core/models/marketplace_models.dart';
import 'package:fixnear/core/services/cloudinary_service.dart';
import 'package:fixnear/core/services/marketplace_service.dart';
import 'package:fixnear/core/services/push_notifications.dart';
import 'package:fixnear/core/theme/app_theme.dart';
import 'package:fixnear/core/utils/formatters.dart';
import 'package:fixnear/features/auth/auth_gate.dart';
import 'package:fixnear/features/customer/customer_marketplace_screen.dart';
import 'package:fixnear/features/jobs/job_detail_screen.dart';
import 'package:fixnear/features/notifications/notification_host.dart';
import 'package:fixnear/features/profile/edit_profile_screen.dart';
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
          imageUploader: CloudinaryService(cloudName: '', uploadPreset: ''),
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

  group('layouts', () {
    final profile = AppUser(
      id: 'customer-1',
      email: 'casey@example.com',
      name: 'Casey Customer',
      role: UserRole.customer,
    );
    // Built inside each test: constructing an HTTP client outside a test
    // zone fails under flutter_test.
    CloudinaryService uploader() =>
        CloudinaryService(cloudName: '', uploadPreset: '');

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
            repository: busyRepository(),
          ),
        );
        // A job sent directly to this provider waits on them.
        expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
        await checkGuidelines(tester);
        await tester.tap(find.text('My jobs'));
        await tester.pumpAndSettle();
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
  final Map<String, List<ProviderQuote>> quotesByRequest = {};
  String? acceptedRequestId;
  ProviderQuote? acceptedQuote;
  Object? acceptQuoteError;
  String? cancelledRequestId;

  @override
  Stream<List<ProviderProfile>> watchProviders() => Stream.value([
    const ProviderProfile(
      id: 'provider-1',
      name: 'Provider One',
      category: 'Plumbing',
      serviceArea: 'Davao City',
      startingPrice: 500,
      isAvailable: true,
    ),
  ]);

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
