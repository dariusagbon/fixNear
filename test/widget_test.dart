import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixnear/core/models/marketplace_models.dart';
import 'package:fixnear/core/services/marketplace_service.dart';
import 'package:fixnear/features/auth/auth_gate.dart';
import 'package:fixnear/features/customer/customer_marketplace_screen.dart';
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

    expect(find.text('Provider Two · ₱1200'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(repository.acceptedRequestId, 'request-2');
    expect(repository.acceptedQuote?.providerUid, 'provider-2');
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
  final Map<String, List<ProviderQuote>> quotesByRequest = {};
  String? acceptedRequestId;
  ProviderQuote? acceptedQuote;

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
  Stream<List<ServiceRequest>> watchOpenRequests(String providerUid) =>
      Stream.value(openRequests);

  @override
  Stream<List<ServiceRequest>> watchProviderJobs(String providerUid) =>
      const Stream.empty();

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
  Future<void> cancelRequest(String requestId) async {}

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
