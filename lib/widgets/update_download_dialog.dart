import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/update/update_controller.dart';
import 'package:fl_clash/providers/update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpdateDownloadDialog extends ConsumerStatefulWidget {
  const UpdateDownloadDialog({super.key});

  @override
  ConsumerState<UpdateDownloadDialog> createState() =>
      _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends ConsumerState<UpdateDownloadDialog>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(updateTaskProvider).refreshInstall());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(updateTaskProvider);
    final l10n = context.appLocalizations;
    return ValueListenableBuilder<UpdateSnapshot>(
      valueListenable: controller,
      builder: (context, snapshot, _) {
        final release = snapshot.release;
        final downloading = snapshot.phase == UpdatePhase.downloading;
        final verifying = snapshot.phase == UpdatePhase.verifying;
        final status = switch (snapshot.phase) {
          UpdatePhase.downloading => l10n.updateDownloading,
          UpdatePhase.verifying => l10n.updateVerifying,
          UpdatePhase.ready => l10n.updateReady,
          UpdatePhase.installing => l10n.updateInstalling,
          UpdatePhase.authorizationRequired => l10n.updateAuthorizationRequired,
          UpdatePhase.failed => l10n.updateFailed,
          UpdatePhase.cancelled => l10n.updateCancelled,
          UpdatePhase.installed => l10n.updateInstalled,
          UpdatePhase.available => '',
        };
        return AlertDialog(
          scrollable: true,
          title: Text(l10n.discoverNewVersion),
          content: SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText.rich(
                  TextSpan(
                    text:
                        '${l10n.versionWithBuild(release?.version ?? '', '${release?.build ?? ''}')}\n\n',
                    style: context.textTheme.titleLarge,
                    children: [
                      TextSpan(
                        text: '${l10n.releaseNotes}\n',
                        style: context.textTheme.titleSmall,
                      ),
                      TextSpan(
                        text: release?.notes.trim().isNotEmpty == true
                            ? release!.notes
                            : l10n.releaseNotesUnavailable,
                        style: context.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (status.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(status),
                ],
                if (downloading || verifying) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: downloading && release != null
                        ? snapshot.received / release.size
                        : null,
                  ),
                  if (downloading && release != null)
                    Text(
                      '${(snapshot.received / 1048576).toStringAsFixed(1)} / ${(release.size / 1048576).toStringAsFixed(1)} MB',
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (downloading || verifying) controller.cancel();
                Navigator.of(context).pop();
              },
              child: Text(
                snapshot.phase == UpdatePhase.ready
                    ? l10n.updateLater
                    : l10n.cancel,
              ),
            ),
            if (!snapshot.busy && snapshot.phase != UpdatePhase.installed)
              FilledButton(
                onPressed: () => unawaited(
                  controller.canInstall
                      ? controller.install()
                      : controller.download(),
                ),
                child: Text(
                  controller.canInstall ? l10n.updateInstallNow : l10n.update,
                ),
              ),
          ],
        );
      },
    );
  }
}
