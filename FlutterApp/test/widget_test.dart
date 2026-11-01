import 'package:flutter_test/flutter_test.dart';
import 'package:studygo_app/main.dart';

void main() {
  testWidgets('StudyGo app shows API configuration guidance by default', (tester) async {
    await tester.pumpWidget(const StudyGoApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('STUDYGO_API_URL'), findsOneWidget);
  });
}
