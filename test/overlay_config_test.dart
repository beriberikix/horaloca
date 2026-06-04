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
    test('defaults: bottom-left, Ubuntu, 12h, rounded, no border, white/dark', () {
      const OverlayConfig cfg = OverlayConfig();
      expect(cfg.position, OverlayPosition.bottomLeft);
      expect(cfg.fontFamily, 'Ubuntu');
      expect(cfg.use24HourClock, isFalse);
      expect(cfg.cornerRadius, 12.0); // rounded
      expect(cfg.borderWidth, 0.0); // no border
      expect(cfg.textColor, 0xFFFFFFFF); // opaque white
      expect(cfg.backgroundColor, 0x9E000000); // ~62% black
      expect(cfg.borderColor, 0xFFFFFFFF);
    });

    test('toMap/fromMap round-trip preserves all fields', () {
      const OverlayConfig cfg = OverlayConfig(
        text: '16:20\nCEST (Berlin, Germany)',
        position: OverlayPosition.topRight,
        fontFamily: 'Noto Sans',
        fontScale: 1.5,
        use24HourClock: true,
        cornerRadius: 0.0,
        borderWidth: 1.0,
        textColor: 0xFF00FF00,
        backgroundColor: 0x80123456,
        borderColor: 0xFFFF0000,
      );
      final OverlayConfig restored = OverlayConfig.fromMap(cfg.toMap());
      expect(restored, cfg);
    });

    test('square vs rounded and border on/off survive round-trip', () {
      const OverlayConfig square =
          OverlayConfig(cornerRadius: 0.0, borderWidth: 1.0);
      final OverlayConfig restored = OverlayConfig.fromMap(square.toMap());
      expect(restored.cornerRadius, 0.0);
      expect(restored.borderWidth, 1.0);
    });

    test('copyWith only changes text when ticking the clock', () {
      const OverlayConfig cfg = OverlayConfig(
        position: OverlayPosition.centerRight,
        fontScale: 2.0,
        cornerRadius: 0.0,
        textColor: 0xFF112233,
      );
      final OverlayConfig ticked = cfg.copyWith(text: '12:00\nUTC (London)');
      expect(ticked.text, '12:00\nUTC (London)');
      expect(ticked.position, OverlayPosition.centerRight);
      expect(ticked.fontScale, 2.0);
      expect(ticked.cornerRadius, 0.0);
      expect(ticked.textColor, 0xFF112233);
    });
  });
}
