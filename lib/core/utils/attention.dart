import '../models/marketplace_models.dart';

/// Whether [request] is waiting on the customer right now: quotes to pick
/// from, finished work to confirm, or cash to pay.
bool customerNeedsToAct(ServiceRequest request) =>
    request.status == RequestStatus.quoted ||
    request.status == RequestStatus.providerCompleted ||
    (request.status == RequestStatus.completed &&
        request.paymentStatus == 'unpaid');

/// Whether [request] is waiting on the provider right now: a job sent
/// directly to them that they haven't answered, or cash to confirm.
bool providerNeedsToAct(ServiceRequest request, String providerUid) =>
    (request.status == RequestStatus.requested &&
        request.providerUid == providerUid) ||
    (request.status == RequestStatus.completed &&
        request.paymentStatus == 'pending_provider_confirmation');
