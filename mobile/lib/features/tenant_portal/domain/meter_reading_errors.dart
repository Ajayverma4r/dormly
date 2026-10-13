// features/tenant_portal/domain/meter_reading_errors.dart
//
// Tenant-facing wording for meter-reading failures. Backend validation that
// helps the tenant fix the input is kept; everything else is replaced so raw
// exception text never reaches the screen.

import 'package:dio/dio.dart';

enum MeterReadingAction { submit, load }

String meterReadingErrorMessage(
  Object error, {
  MeterReadingAction action = MeterReadingAction.submit,
}) {
  final fallback = action == MeterReadingAction.submit
      ? 'Could not submit your reading. Please try again.'
      : 'Could not load your meter readings. Please try again.';
  if (error is! DioException) return fallback;

  final response = error.response;
  if (response == null) {
    return 'Could not reach the server. Check your connection and try again.';
  }

  final data = response.data;
  final message =
      data is Map && data['error'] != null ? data['error'].toString() : '';
  final lower = message.toLowerCase();

  if (lower.contains('cannot be less than previous')) return message;
  if (lower.contains('only image uploads')) {
    return 'Please attach a photo of the meter (image files only).';
  }
  if (lower.contains('file too large') || response.statusCode == 413) {
    return 'The meter photo is too large. Please retake it and try again.';
  }

  return switch (response.statusCode) {
    400 => action == MeterReadingAction.submit
        ? 'Please enter a valid meter reading and try again.'
        : fallback,
    401 => 'Your session has expired. Please sign in again.',
    403 => 'Meter readings are not available for your property. '
        'Please contact your property owner.',
    404 => 'We could not find an active stay for your account. '
        'Please contact your property owner.',
    final int code when code >= 500 =>
      'Something went wrong on our side. Please try again in a moment.',
    _ => fallback,
  };
}
