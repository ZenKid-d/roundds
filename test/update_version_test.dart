import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/core/update_service.dart';

void main() {
  group('UpdateService.isNewer', () {
    test('патч больше — новее', () {
      expect(UpdateService.isNewer('1.5.2', '1.5.1'), isTrue);
    });

    test('равные версии — не новее', () {
      expect(UpdateService.isNewer('1.5.1', '1.5.1'), isFalse);
    });

    test('текущая новее опубликованной — не обновляем', () {
      expect(UpdateService.isNewer('1.4.9', '1.5.0'), isFalse);
    });

    test('minor больше', () {
      expect(UpdateService.isNewer('1.6.0', '1.5.9'), isTrue);
    });

    test('major больше', () {
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('недостающие компоненты трактуются как 0', () {
      expect(UpdateService.isNewer('1.5', '1.5.0'), isFalse);
      expect(UpdateService.isNewer('1.5.1', '1.5'), isTrue);
    });

    test('нечисловой суффикс игнорируется', () {
      expect(UpdateService.isNewer('1.5.1-beta', '1.5.0'), isTrue);
    });
  });
}
