import 'update_store.dart';

enum UpdateInstallResult {
  launched,
  authorizationRequired,
  cancelled,
  installed,
}

abstract interface class UpdateInstaller {
  Future<void> prepare(UpdateTask task);
  Future<UpdateInstallResult> install(UpdateTask task);
  Future<UpdateInstallResult?> recover(UpdateTask task);
}
