part of '../action.dart';

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  @override
  void build() {}

  void updateCurrentSelectedMap(String groupName, String proxyName) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile != null &&
        currentProfile.selectedMap[groupName] != proxyName) {
      final selectedMap = Map<String, String>.from(currentProfile.selectedMap)
        ..[groupName] = proxyName;
      ref
          .read(profilesProvider.notifier)
          .put(currentProfile.copyWith(selectedMap: selectedMap));
    }
  }

  Future<void> deleteProfile(int id) async {
    await ref.read(profilesProvider.notifier).del(id);
    await clearEffect(id);
    final currentProfileId = ref.read(currentProfileIdProvider);
    if (currentProfileId == id) {
      final profiles = ref.read(profilesProvider);
      if (profiles.isNotEmpty) {
        final updateId = profiles.first.id;
        ref.read(currentProfileIdProvider.notifier).value = updateId;
      } else {
        ref.read(currentProfileIdProvider.notifier).value = null;
        ref.read(setupActionProvider.notifier).setRunning(false);
      }
    }
  }

  Future<void> autoUpdateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(profile.autoUpdateDuration)
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type != ProfileType.url) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        final message = profile.source == ProfileSource.xboard
            ? XboardRedaction.text(e)
            : e.toString();
        commonPrint.log(message, logLevel: LogLevel.warning);
      }
    }
  }

  Future<void> putProfile(Profile profile) {
    final operation = ref.read(profilesProvider.notifier).put(profile);
    if (ref.read(currentProfileIdProvider) == null) {
      ref.read(currentProfileIdProvider.notifier).value = profile.id;
    }
    return operation;
  }

  Future<void> updateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (profile.type != ProfileType.url) continue;
      await updateProfile(profile);
    }
  }

  Future<Profile> importProfileData(Profile profile, Uint8List bytes) {
    return dataMutationQueue.run(() async {
      final prepared = ref.read(profilesProvider).optimizeLabel(profile);
      final next = await commitProfileData(
        database: database,
        activeRoot: await appPath.homeDirPath,
        profile: prepared,
        bytes: bytes,
        recoverPending: () =>
            ref.read(backupActionProvider.notifier)._recoverPendingRestore(),
        validate: (path) async {
          final base = await coreController.readConfig(path);
          final setup = await ref.read(setupStateProvider(profile.id).future);
          final compiled = await ref
              .read(setupActionProvider.notifier)
              .getProfile(
                setupState: setup.copyWith(profileSource: profile.source),
                patchConfig: ref.read(patchClashConfigProvider),
                baseConfig: base,
              );
          final error = await coreController.validateConfigWithData(
            compiled.a,
            runtime: true,
          );
          if (error.isNotEmpty) throw FormatException(error);
        },
        onCleanupFailure: (error) => commonPrint.log(
          'Profile cleanup: $error',
          logLevel: LogLevel.warning,
        ),
      );
      if (!ref.mounted) return next;
      ref.read(profilesProvider.notifier).acceptCommitted(next);
      if (ref.read(currentProfileIdProvider) == null) {
        ref.read(currentProfileIdProvider.notifier).value = next.id;
      }
      return next;
    });
  }

  Future<Profile> createCustomProfile({String? label}) => importProfileData(
    Profile.custom(label: label ?? currentAppLocalizations.custom),
    Uint8List.fromList(utf8.encode(defaultCustomProfile)),
  );

  Future<void> updateProfile(Profile profile, {bool showLoading = false}) {
    return dataMutationQueue.run(
      () => _updateProfile(profile, showLoading: showLoading),
    );
  }

  Future<void> _updateProfile(
    Profile profile, {
    required bool showLoading,
  }) async {
    try {
      if (showLoading) {
        ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = true;
      }
      if (ref.read(profilesProvider).getProfile(profile.id) != null) {
        await ref.read(profilesProvider.notifier).put(profile);
      }
      final downloaded = await profile.download();
      await importProfileData(downloaded.profile, downloaded.bytes);
      if (profile.id == ref.read(currentProfileIdProvider)) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true);
      }
    } finally {
      ref.read(isUpdatingProvider(profile.updatingKey).notifier).value = false;
    }
  }

  Future<void> addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    if (platformFile == null) return;
    final bytes = await platformFile.readBytes();
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(currentPageLabelProvider.notifier).toProfiles();
    await globalState.loadingRun(tag: LoadingTag.profiles, () async {
      return importProfileData(Profile.normal(label: platformFile.name), bytes);
    }, title: currentAppLocalizations.addProfile);
  }

  Future<void> addProfileFormURL(String url) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
    await globalState.loadingRun(tag: LoadingTag.profiles, () async {
      final downloaded = await Profile.normal(url: url).download();
      return importProfileData(downloaded.profile, downloaded.bytes);
    }, title: currentAppLocalizations.addProfile);
  }

  void setProfileAndAutoApply(Profile profile) {
    ref.read(profilesProvider.notifier).put(profile);
    if (profile.id == ref.read(currentProfileIdProvider)) {
      ref.read(setupActionProvider.notifier).applyProfileDebounce();
    }
  }

  Future<void> addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    addProfileFormURL(url);
  }

  void reorder(List<Profile> profiles) {
    ref.read(profilesProvider.notifier).reorder(profiles);
  }

  Future<void> clearEffect(int profileId) async {
    final profilePath = await appPath.getProfilePath(profileId.toString());
    final profileFile = File(profilePath);
    final isExists = await profileFile.exists();
    if (isExists) {
      await profileFile.safeDelete(recursive: true);
    }
    final error = await coreController.clearEffect(profileId);
    if (error.isNotEmpty) {
      commonPrint.log(error, logLevel: LogLevel.warning);
    }
  }
}
