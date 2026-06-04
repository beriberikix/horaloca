import 'package:flutter_test/flutter_test.dart';
import 'package:horaloca/models/overlay_config.dart';
import 'package:horaloca/models/overlay_position.dart';

void main() {
  group('OverlayPosition', () {
    test('defines all nine slots', () {
      expect(OverlayPosition.values.length, 9);
    });

    test('anchors map correctly to the 3x3 grid', () {
      expect(OverlayPosition.bottomLeft.horizontalAnchor, 0.0);
      expect(OverlayPosition.bottomLeft.verticalAnchor, 1.0);
      expect(OverlayPosition.topRight.horizontalAnchor, 1.0);
      expect(OverlayPosition.topRight.verticalAnchor, 0.0);
      expect(OverlayPosition.center.horizontalAnchor, 0.5);
      expect(OverlayPosition.center.verticalAnchor, 0.5);
    });

    test('wire round-trip is stable', () {
      for (final OverlayPosition p in OverlayPosition.values) {
        expect(OverlayPosition.fromWire(p.wireValue), p);
      }
    });

    test('unknown wire value falls back to bottomLeft', () {
      expect(OverlayPosition.fromWire('nonsense'), OverlayPosition.bottomLeft);
      expect(OverlayPosition.fromWire(null), OverlayPosition.bottomLeft);
    });
  });

  group('OverlayConfig', () {
    test('defaults match the MVP spec (bottom-left, Ubuntu, 12h)', () {
      const OverlayConfig cfg = OverlayConfig();
      expect(cfg.position, OverlayPosition.bottomLeft);
      expect(cfg.fontFamily, 'Ubuntu');
      expect(cfg.use24HourClock, isFalse);
      expect(cfg.pngBackgroundPath, isNull);
    });

    test('toMap/fromMap round-trip preserves all fields', () {
      const OverlayConfig cfg = OverlayConfig(
        text: '16:20 (CEST)',
        position: OverlayPosition.topRight,
        fontFamily: 'Noto Sans',
        fontScale: 1.5,
        use24HourClock: true,
        backgroundOpacity: 0.8,
        pngBackgroundPath: '/home/u/badge.png',
      );
      final OverlayConfig restored = OverlayConfig.fromMap(cfg.toMap());
      expect(restored, cfg);
    });

    test('copyWith can clear the PNG background', () {
      const OverlayConfig cfg = OverlayConfig(pngBackgroundPath: '/x.png');
      final OverlayConfig cleared = cfg.copyWith(clearPngBackground: true);
      expect(cleared.pngBackgroundPath, isNull);
    });

    test('copyWith only changes text when ticking the clock', () {
      const OverlayConfig cfg = OverlayConfig(
        position: OverlayPosition.centerRight,
        fontScale: 2.0,
      );
      final OverlayConfig ticked = cfg.copyWith(text: '12:00 (UTC)');
      expect(ticked.text, '12:00 (UTC)');
      expect(ticked.position, OverlayPosition.centerRight);
      expect(ticked.fontScale, 2.0);
    });
  });
}
