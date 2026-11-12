import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

final geoResourceCoreProvider = Provider<CoreController>(
  (ref) => coreController,
);
final geoFileInfoProvider = FutureProvider.autoDispose
    .family<FileInfo?, GeoResource>((ref, type) async {
      final home = await appPath.homeDirPath;
      final fileName = switch (type) {
        GeoResource.MMDB => MMDB,
        GeoResource.ASN => ASN,
        GeoResource.GEOIP => GEOIP,
        GeoResource.GEOSITE => GEOSITE,
      };
      return File(p.join(home, fileName)).getFileInfo();
    });
