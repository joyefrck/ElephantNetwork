// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../account.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(xboardApi)
final xboardApiProvider = XboardApiProvider._();

final class XboardApiProvider
    extends $FunctionalProvider<XboardApi, XboardApi, XboardApi>
    with $Provider<XboardApi> {
  XboardApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'xboardApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$xboardApiHash();

  @$internal
  @override
  $ProviderElement<XboardApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  XboardApi create(Ref ref) {
    return xboardApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(XboardApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<XboardApi>(value),
    );
  }
}

String _$xboardApiHash() => r'eea8f72085ebbba67a7982115013aee50cb7b8e5';

@ProviderFor(xboardSessionStore)
final xboardSessionStoreProvider = XboardSessionStoreProvider._();

final class XboardSessionStoreProvider
    extends
        $FunctionalProvider<
          XboardSessionStore,
          XboardSessionStore,
          XboardSessionStore
        >
    with $Provider<XboardSessionStore> {
  XboardSessionStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'xboardSessionStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$xboardSessionStoreHash();

  @$internal
  @override
  $ProviderElement<XboardSessionStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  XboardSessionStore create(Ref ref) {
    return xboardSessionStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(XboardSessionStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<XboardSessionStore>(value),
    );
  }
}

String _$xboardSessionStoreHash() =>
    r'4e7cf4cff9076b8a2504e32db93a72c97be40603';

@ProviderFor(xboardManagedProfileGateway)
final xboardManagedProfileGatewayProvider =
    XboardManagedProfileGatewayProvider._();

final class XboardManagedProfileGatewayProvider
    extends
        $FunctionalProvider<
          XboardManagedProfileGateway,
          XboardManagedProfileGateway,
          XboardManagedProfileGateway
        >
    with $Provider<XboardManagedProfileGateway> {
  XboardManagedProfileGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'xboardManagedProfileGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$xboardManagedProfileGatewayHash();

  @$internal
  @override
  $ProviderElement<XboardManagedProfileGateway> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  XboardManagedProfileGateway create(Ref ref) {
    return xboardManagedProfileGateway(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(XboardManagedProfileGateway value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<XboardManagedProfileGateway>(value),
    );
  }
}

String _$xboardManagedProfileGatewayHash() =>
    r'578286c0661baacb31925bc8cb13dc5041aeb56a';

@ProviderFor(XboardSessionController)
final xboardSessionControllerProvider = XboardSessionControllerProvider._();

final class XboardSessionControllerProvider
    extends $NotifierProvider<XboardSessionController, XboardSessionState> {
  XboardSessionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'xboardSessionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$xboardSessionControllerHash();

  @$internal
  @override
  XboardSessionController create() => XboardSessionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(XboardSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<XboardSessionState>(value),
    );
  }
}

String _$xboardSessionControllerHash() =>
    r'1ba5398216b8315c916e4d932c9e6eef4e27d8c6';

abstract class _$XboardSessionController extends $Notifier<XboardSessionState> {
  XboardSessionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<XboardSessionState, XboardSessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<XboardSessionState, XboardSessionState>,
              XboardSessionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
