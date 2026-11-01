import 'package:flutter_test/flutter_test.dart';
import 'package:studygo_app/api/studygo_api.dart';

void main() {
  test('API exception keeps readable server error', () {
    final error = ApiException(401, 'invalid_or_expired_token');
    expect(error.statusCode, 401);
    expect(error.toString(), 'invalid_or_expired_token');
  });
}
