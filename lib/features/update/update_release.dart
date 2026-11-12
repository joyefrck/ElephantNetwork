import 'dart:ffi';
import 'dart:io';

final class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.build,
    required this.platform,
    required this.arch,
    required this.url,
    required this.size,
    required this.sha256,
    required this.notes,
  });

  final String version;
  final int build;
  final String platform;
  final String arch;
  final Uri url;
  final int size;
  final String sha256;
  final String notes;

  static String get currentArch {
    final arch = Abi.current().toString().split('_').last;
    return arch == 'ia32' ? 'x86' : arch;
  }

  static String normalizeArch(String value) => switch (value) {
    'amd64' || 'x86_64' => 'x64',
    'aarch64' || 'arm64-v8a' => 'arm64',
    'armeabi-v7a' || 'armv7' => 'arm',
    'ia32' || 'i386' || 'i686' => 'x86',
    _ => value,
  };

  factory UpdateRelease.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] ?? json['tag_name'])?.toString() ?? '';
    final uri = Uri.tryParse(json['download_url']?.toString() ?? '');
    final build = int.tryParse(json['build_number']?.toString() ?? '');
    final size = int.tryParse(json['file_size']?.toString() ?? '');
    final hash = json['sha256']?.toString().toLowerCase() ?? '';
    final platform = json['platform']?.toString() ?? '';
    final arch = normalizeArch(json['arch']?.toString() ?? '');
    if (!RegExp(r'^v?[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(version) ||
        build == null ||
        build <= 0 ||
        size == null ||
        size <= 0 ||
        size > 4 * 1024 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !const {'android', 'windows', 'macos', 'linux'}.contains(platform) ||
        !const {'arm', 'arm64', 'x86', 'x64'}.contains(arch)) {
      throw const FormatException('Invalid update metadata');
    }
    return UpdateRelease(
      version: version.startsWith('v') ? version.substring(1) : version,
      build: build,
      platform: platform,
      arch: arch,
      url: uri,
      size: size,
      sha256: hash,
      notes: (json['release_notes'] ?? json['body'])?.toString() ?? '',
    );
  }

  bool isNewerThan(String currentVersion, int currentBuild) {
    final target = version.split('.').map(int.parse).toList();
    final current = currentVersion.split('.').map(int.parse).toList();
    if (current.length != 3) {
      throw const FormatException('Invalid installed version');
    }
    for (var index = 0; index < 3; index++) {
      final order = target[index].compareTo(current[index]);
      if (order != 0) return order > 0;
    }
    return build > currentBuild;
  }

  void validateTarget({String? platform, String? arch}) {
    if (this.platform != (platform ?? Platform.operatingSystem) ||
        this.arch != normalizeArch(arch ?? currentArch)) {
      throw const FormatException('Update platform or architecture mismatch');
    }
  }

  String get extension => switch (platform) {
    'android' => 'apk',
    'windows' => 'exe',
    'macos' => 'dmg',
    'linux' => 'deb',
    _ => throw const FormatException('Unsupported update platform'),
  };

  Map<String, dynamic> toJson() => {
    'version': version,
    'build_number': build,
    'platform': platform,
    'arch': arch,
    'download_url': url.toString(),
    'file_size': size,
    'sha256': sha256,
    'release_notes': notes,
  };
}
