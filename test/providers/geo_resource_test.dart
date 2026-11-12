import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class Handler extends Mock implements CoreHandlerInterface {}

void main() {
  test(
    'manual sync uses just-edited URL and refreshes info after completion',
    () async {
      final handler = Handler();
      final pending = Completer<String>();
      var reads = 0;
      when(
        () => handler.updateGeoData('MMDB', urls: any(named: 'urls')),
      ).thenAnswer((_) => pending.future);
      final container = ProviderContainer(
        overrides: [
          geoResourceCoreProvider.overrideWithValue(
            CoreController.test(handler),
          ),
          geoFileInfoProvider.overrideWith((ref, type) async {
            reads++;
            return null;
          }),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        geoFileInfoProvider(GeoResource.MMDB),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(geoFileInfoProvider(GeoResource.MMDB).future);
      final action = container.read(geoResourceActionProvider.notifier);
      action.updateGeoResourceUrl(
        GeoResource.MMDB,
        'https://new.example/Country.mmdb',
      );
      expect(
        container.read(updateParamsProvider).geoXUrl['mmdb'],
        'https://new.example/Country.mmdb',
      );
      final task = action.updateGeoResource(GeoResource.MMDB);
      expect(
        container.read(isUpdatingProvider(GeoResource.MMDB.updatingKey)),
        isTrue,
      );
      final urls =
          verify(
                () => handler.updateGeoData(
                  'MMDB',
                  urls: captureAny(named: 'urls'),
                ),
              ).captured.single
              as Map<String, String>;
      expect(urls['mmdb'], 'https://new.example/Country.mmdb');
      container
              .read(isUpdatingProvider(GeoResource.MMDB.updatingKey).notifier)
              .value =
          false;
      await action.updateGeoResource(GeoResource.MMDB);
      verifyNever(
        () => handler.updateGeoData('MMDB', urls: any(named: 'urls')),
      );
      expect(reads, 1);
      pending.complete('');
      await task;
      await container.read(geoFileInfoProvider(GeoResource.MMDB).future);
      expect(reads, 2);
      expect(
        container.read(isUpdatingProvider(GeoResource.MMDB.updatingKey)),
        isFalse,
      );
    },
  );

  test('sync error clears busy state and keeps the configured URL', () async {
    final handler = Handler();
    when(
      () => handler.updateGeoData('MMDB', urls: any(named: 'urls')),
    ).thenThrow(StateError('download failed'));
    final container = ProviderContainer(
      overrides: [
        geoResourceCoreProvider.overrideWithValue(CoreController.test(handler)),
      ],
    );
    addTearDown(container.dispose);
    final action = container.read(geoResourceActionProvider.notifier);
    action.updateGeoResourceUrl(
      GeoResource.MMDB,
      'https://new.example/Country.mmdb',
    );
    await expectLater(
      action.updateGeoResource(GeoResource.MMDB),
      throwsStateError,
    );
    expect(
      container.read(isUpdatingProvider(GeoResource.MMDB.updatingKey)),
      isFalse,
    );
    expect(
      container.read(patchClashConfigProvider).geoXUrl[GeoResource.MMDB],
      'https://new.example/Country.mmdb',
    );
  });
}
