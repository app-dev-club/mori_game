import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/app_version_compare.dart';

void main() {
  group('AppVersionCompare', () {
    test('サーバー側ビルド番号が大きい場合は更新が必要', () {
      expect(
        AppVersionCompare.isUpdateRequired(
          localBuildNumber: 5,
          remoteBuildNumber: 6,
        ),
        isTrue,
      );
    });

    test('同じビルド番号なら更新不要', () {
      expect(
        AppVersionCompare.isUpdateRequired(
          localBuildNumber: 6,
          remoteBuildNumber: 6,
        ),
        isFalse,
      );
    });

    test('クライアントの方が新しければ更新不要', () {
      expect(
        AppVersionCompare.isUpdateRequired(
          localBuildNumber: 7,
          remoteBuildNumber: 6,
        ),
        isFalse,
      );
    });

    test('parseBuildNumber', () {
      expect(AppVersionCompare.parseBuildNumber('12'), 12);
      expect(AppVersionCompare.parseBuildNumber(''), isNull);
      expect(AppVersionCompare.parseBuildNumber(null), isNull);
    });
  });
}
