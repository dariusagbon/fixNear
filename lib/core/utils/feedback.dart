import 'package:flutter/material.dart';

import 'formatters.dart';

/// Runs [action] and reports the outcome in a snackbar: [successMessage]
/// when given, otherwise a plain-language error on failure.
Future<void> runWithFeedback(
  BuildContext context,
  Future<void> Function() action, {
  required String failureMessage,
  String? successMessage,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    if (successMessage != null) {
      messenger?.showSnackBar(SnackBar(content: Text(successMessage)));
    }
  } catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text(friendlyErrorMessage(error, failureMessage))),
    );
  }
}
