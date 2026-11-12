part of '../action.dart';

@Riverpod(keepAlive: true)
class GeoResourceAction extends _$GeoResourceAction {
  final _updating = <GeoResource>{};

  @override
  void build() {}

  Future<void> updateGeoResource(GeoResource geoResource) async {
    final key = geoResource.updatingKey;
    if (_updating.contains(geoResource) || ref.read(isUpdatingProvider(key))) {
      return;
    }
    _updating.add(geoResource);
    ref.read(isUpdatingProvider(key).notifier).value = true;
    try {
      await ref
          .read(geoResourceCoreProvider)
          .updateGeoData(
            geoResource.name,
            urls: ref.read(patchClashConfigProvider).geoXUrl.raw,
          );
    } finally {
      _updating.remove(geoResource);
      ref.read(isUpdatingProvider(key).notifier).value = false;
      ref.invalidate(geoFileInfoProvider(geoResource));
    }
  }

  void updateGeoResourceUrl(GeoResource geoResource, String newUrl) {
    if (!newUrl.isUrl) {
      throw 'Invalid url';
    }
    ref.read(patchClashConfigProvider.notifier).update((state) {
      return state.copyWith(geoXUrl: {...state.geoXUrl, geoResource: newUrl});
    });
  }
}
