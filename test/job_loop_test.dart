import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixnear/core/models/marketplace_models.dart';
import 'package:fixnear/core/services/marketplace_service.dart';
import 'package:fixnear/core/utils/geo.dart';

/// Runs the whole job loop through the real [FirestoreMarketplaceRepository]
/// (transactions, status checks and payment rules) on an in-memory Firestore.
/// Security rules are covered separately by rules-tests/ in the emulator.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreMarketplaceRepository repository;

  const customer = 'customer-1';
  const provider = 'provider-1';
  const otherProvider = 'provider-2';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreMarketplaceRepository(firestore: firestore);
  });

  Future<ServiceRequest> onlyRequest() async =>
      (await repository.watchCustomerRequests(customer).first).single;

  test('post → quote → book → every status → confirm → cash paid', () async {
    await repository.createRequest(
      customerUid: customer,
      customerName: 'Casey Customer',
      category: 'Plumbing',
      description: 'Fix a leaking kitchen faucet',
      serviceArea: 'Davao City',
      locationLabel: 'Home',
      latitude: 7.0731,
      longitude: 125.6128,
      scheduledAt: DateTime(2026, 10, 2, 9),
    );
    var job = await onlyRequest();
    expect(job.status, RequestStatus.requested);
    expect(job.latitude, 7.0731);
    expect(job.geohash, encodeGeohash(const LatLngPoint(7.0731, 125.6128)));

    final board = await repository.watchOpenRequests(provider).first;
    expect(board.map((r) => r.id), [job.id]);

    await repository.sendQuote(
      requestId: job.id,
      providerUid: provider,
      providerName: 'Pat Provider',
      price: 850,
      note: 'Parts and labor included',
    );
    await repository.sendQuote(
      requestId: job.id,
      providerUid: otherProvider,
      providerName: 'Quinn Provider',
      price: 990,
      note: 'Can come today',
    );
    // A revised quote replaces the provider's earlier one.
    await repository.sendQuote(
      requestId: job.id,
      providerUid: provider,
      providerName: 'Pat Provider',
      price: 800,
      note: 'Parts and labor included',
    );
    expect((await onlyRequest()).status, RequestStatus.quoted);

    final quotes = await repository.watchQuotes(job.id).first;
    expect(quotes, hasLength(2));
    final chosen = quotes.firstWhere((q) => q.providerUid == provider);
    expect(chosen.price, 800);

    await repository.acceptQuote(job.id, chosen);
    job = await onlyRequest();
    expect(job.status, RequestStatus.accepted);
    expect(job.providerUid, provider);
    expect(job.quotedPrice, 800);
    expect(await repository.watchOpenRequests(otherProvider).first, isEmpty);

    await repository.sendMessage(
      requestId: job.id,
      senderUid: customer,
      senderName: 'Casey Customer',
      text: 'Gate code is 1234',
    );
    expect(await repository.watchMessages(job.id).first, hasLength(1));

    for (final status in [
      RequestStatus.onTheWay,
      RequestStatus.arrived,
      RequestStatus.inProgress,
      RequestStatus.providerCompleted,
    ]) {
      await repository.advanceRequest(job.id, status);
      expect((await onlyRequest()).status, status);
    }

    await repository.confirmCompletion(job.id, customer);
    expect((await onlyRequest()).status, RequestStatus.completed);

    await repository.recordCashPayment(job.id, customer);
    expect(
      (await onlyRequest()).paymentStatus,
      'pending_provider_confirmation',
    );
    await repository.confirmCashPayment(job.id, provider);
    expect((await onlyRequest()).paymentStatus, 'paid');

    final providerJobs = await repository.watchProviderJobs(provider).first;
    expect(providerJobs.single.paymentStatus, 'paid');
  });

  test('the repository refuses out-of-order steps', () async {
    await repository.createRequest(
      customerUid: customer,
      customerName: 'Casey Customer',
      category: 'Plumbing',
      description: 'Fix a leaking kitchen faucet',
      serviceArea: 'Davao City',
      scheduledAt: DateTime(2026, 10, 2, 9),
    );
    final job = await onlyRequest();

    // No quote accepted yet, so the job cannot move.
    await expectLater(
      () => repository.advanceRequest(job.id, RequestStatus.onTheWay),
      throwsStateError,
    );
    await expectLater(
      () => repository.confirmCompletion(job.id, customer),
      throwsStateError,
    );
    await expectLater(
      () => repository.recordCashPayment(job.id, customer),
      throwsStateError,
    );

    await repository.sendQuote(
      requestId: job.id,
      providerUid: provider,
      providerName: 'Pat Provider',
      price: 850,
      note: 'Parts and labor included',
    );
    await repository.acceptQuote(
      job.id,
      (await repository.watchQuotes(job.id).first).single,
    );

    // Skipping from accepted straight to arrived.
    await expectLater(
      () => repository.advanceRequest(job.id, RequestStatus.arrived),
      throwsStateError,
    );
    // Quoting a job that is already booked.
    await expectLater(
      () => repository.sendQuote(
        requestId: job.id,
        providerUid: otherProvider,
        providerName: 'Quinn Provider',
        price: 700,
        note: 'Cheaper',
      ),
      throwsStateError,
    );
  });

  test('declined jobs leave that provider’s board only', () async {
    await repository.createRequest(
      customerUid: customer,
      customerName: 'Casey Customer',
      category: 'Cleaning',
      description: 'Deep clean the living room',
      serviceArea: 'Davao City',
      scheduledAt: DateTime(2026, 10, 2, 9),
    );
    final job = await onlyRequest();
    await repository.declineRequest(job.id, provider);

    expect(await repository.watchOpenRequests(provider).first, isEmpty);
    expect(
      (await repository.watchOpenRequests(otherProvider).first).single.id,
      job.id,
    );
  });

  test('provider settings save a base location with geohash', () async {
    await firestore.doc('providerProfiles/$provider').set({
      'name': 'Pat Provider',
      'category': 'Plumbing',
      'serviceArea': 'Davao City',
      'startingPrice': 500,
      'isAvailable': false,
    });
    // An old profile reads with safe defaults.
    var profile = await repository.watchProviderProfile(provider).first;
    expect(profile!.baseLocation, isNull);
    expect(profile.serviceRadiusKm, 10);

    await repository.setProviderAvailability(provider, true);
    await repository.updateProviderServiceSettings(
      providerUid: provider,
      category: 'Electrical',
      serviceArea: ' Lanang ',
      startingPrice: 650,
      baseLocation: const LatLngPoint(7.0996, 125.6317),
      serviceRadiusKm: 80,
    );
    profile = await repository.watchProviderProfile(provider).first;
    expect(profile!.isAvailable, isTrue);
    expect(profile.category, 'Electrical');
    expect(profile.serviceArea, 'Lanang');
    expect(profile.baseLocation, const LatLngPoint(7.0996, 125.6317));
    expect(profile.serviceRadiusKm, 50, reason: 'clamped to the maximum');
    final raw = (await firestore.doc('providerProfiles/$provider').get())
        .data()!;
    expect(raw['baseGeohash'], 'wc326u6nn');
  });

  group('reopening, withdrawing, cancelling, rescheduling', () {
    Future<String> post({String? directTo}) async {
      await repository.createRequest(
        customerUid: customer,
        customerName: 'Casey Customer',
        category: 'Plumbing',
        description: 'Fix a leaking kitchen faucet',
        serviceArea: 'Davao City',
        scheduledAt: DateTime.now().add(const Duration(days: 1)),
        provider: directTo == null
            ? null
            : ProviderProfile(
                id: directTo,
                name: 'Pat Provider',
                category: 'Plumbing',
                serviceArea: 'Davao City',
                startingPrice: 500,
                isAvailable: true,
              ),
      );
      return (await onlyRequest()).id;
    }

    Future<void> book(String id) async {
      await repository.sendQuote(
        requestId: id,
        providerUid: provider,
        providerName: 'Pat Provider',
        price: 850,
        note: 'ok',
      );
      await repository.acceptQuote(
        id,
        (await repository.watchQuotes(id).first).single,
      );
    }

    test('declining a direct job reopens it to other providers', () async {
      final id = await post(directTo: provider);
      expect(await repository.watchOpenRequests(otherProvider).first, isEmpty);

      await repository.declineRequest(id, provider);
      final job = await onlyRequest();
      expect(job.providerUid, isNull);
      expect(job.declinedProviderUids, [provider]);
      expect(await repository.watchOpenRequests(provider).first, isEmpty);
      expect(
        (await repository.watchOpenRequests(otherProvider).first).single.id,
        id,
      );
    });

    test('a withdrawing provider reopens the job without them', () async {
      final id = await post();
      await book(id);
      await repository.advanceRequest(id, RequestStatus.onTheWay);

      await repository.withdrawFromJob(id, provider, reason: 'Car broke down');
      final job = await onlyRequest();
      expect(job.status, RequestStatus.requested);
      expect(job.providerUid, isNull);
      expect(job.quotedPrice, isNull);
      expect(job.declinedProviderUids, [provider]);
      expect(
        (await repository.watchOpenRequests(otherProvider).first).single.id,
        id,
      );
    });

    test(
      'withdrawing or cancelling is refused once the provider arrives',
      () async {
        final id = await post();
        await book(id);
        await repository.advanceRequest(id, RequestStatus.onTheWay);
        await repository.advanceRequest(id, RequestStatus.arrived);
        await expectLater(
          () => repository.withdrawFromJob(id, provider),
          throwsStateError,
        );
        await expectLater(() => repository.cancelRequest(id), throwsStateError);
      },
    );

    test('customers cancel a booked job with a reason', () async {
      final id = await post();
      await book(id);
      await repository.cancelRequest(id, reason: '  Fixed it myself ');
      final job = await onlyRequest();
      expect(job.status, RequestStatus.cancelled);
      expect(job.cancelledBy, 'customer');
      expect(job.cancelReason, 'Fixed it myself');
    });

    test('customers reschedule to a future time only', () async {
      final id = await post();
      final newTime = DateTime.now().add(const Duration(days: 3));
      await repository.rescheduleRequest(id, newTime);
      expect(
        (await onlyRequest()).scheduledAt!.difference(newTime).inSeconds,
        0,
      );
      await expectLater(
        () => repository.rescheduleRequest(
          id,
          DateTime.now().subtract(const Duration(hours: 1)),
        ),
        throwsArgumentError,
      );
    });
  });
}
