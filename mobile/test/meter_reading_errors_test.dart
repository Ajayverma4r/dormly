import 'package:dio/dio.dart';
import 'package:dormly/features/tenant_portal/domain/meter_reading_errors.dart';
import 'package:flutter_test/flutter_test.dart';

final _req = RequestOptions(path: '/v1/tenant-portal/meter-readings');

DioException _http(int status, [Object? data]) => DioException(
      requestOptions: _req,
      response: Response(requestOptions: _req, statusCode: status, data: data),
      type: DioExceptionType.badResponse,
    );

void main() {
  test('keeps the previous-reading validation message', () {
    const msg = 'Reading (120) cannot be less than previous (150).';
    expect(meterReadingErrorMessage(_http(400, {'error': msg})), msg);
  });

  test('schema validation becomes a plain instruction, not raw details', () {
    final e = _http(400, {'error': 'Validation failed', 'details': []});
    expect(meterReadingErrorMessage(e),
        'Please enter a valid meter reading and try again.');
  });

  test('image-only and size limits are explained', () {
    expect(
      meterReadingErrorMessage(_http(400, {'error': 'Only image uploads are allowed'})),
      contains('image files only'),
    );
    expect(
      meterReadingErrorMessage(_http(400, {'error': 'File too large'})),
      contains('too large'),
    );
  });

  test('no active tenancy / not found is friendly', () {
    expect(meterReadingErrorMessage(_http(404, {'error': 'Not found'})),
        contains('active stay'));
  });

  test('feature disabled, session and server errors are friendly', () {
    expect(meterReadingErrorMessage(_http(403, {'error': 'x'})),
        contains('not available'));
    expect(meterReadingErrorMessage(_http(401)), contains('session'));
    expect(
      meterReadingErrorMessage(_http(500, {'error': 'relation "x" does not exist'})),
      isNot(contains('relation')),
    );
  });

  test('connection failures and unknown errors never show raw text', () {
    final offline = DioException(
      requestOptions: _req,
      type: DioExceptionType.connectionError,
      message: 'SocketException: Failed host lookup',
    );
    expect(meterReadingErrorMessage(offline), contains('connection'));
    expect(meterReadingErrorMessage(StateError('boom')),
        'Could not submit your reading. Please try again.');
    expect(
      meterReadingErrorMessage(StateError('boom'),
          action: MeterReadingAction.load),
      'Could not load your meter readings. Please try again.',
    );
  });
}
