import 'package:flutter_test/flutter_test.dart';
import 'playback_regression.dart' as regression;

void main() {
  for (final entry in {
    ...regression.queueCases,
    ...regression.concurrencyCases,
    ...regression.stateCases
  }.entries) {
    test(entry.key, () async {
      final fixture = regression.Fixture();
      try {
        await entry.value(fixture);
      } finally {
        await fixture.close();
      }
    });
  }
}
