import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:listen_with_eve/main.dart';
import 'package:listen_with_eve/services/web_search_tool.dart';

void main() {
  testWidgets('LteApp builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const LteApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('WebSearchTool defaults to /api/search proxy', () {
    final transport = BackendProxySearchTransport();
    expect(transport.proxyUri?.path, '/api/search');
  });
}
