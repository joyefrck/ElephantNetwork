import 'dart:io';

import 'package:dio/dio.dart';

import 'update_store.dart';

class UpdateDownload {
  UpdateDownload(this.dio);

  final Dio dio;

  Future<File> download(
    UpdateTask task, {
    required CancelToken cancelToken,
    required void Function(int received) onProgress,
  }) async {
    var uri = task.release.url;
    final part = File('${task.file.path}.part');
    IOSink? sink;
    try {
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw const FormatException('Insecure update redirect');
        }
        final response = await dio.get<ResponseBody>(
          uri.toString(),
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (_) => true,
            receiveTimeout: const Duration(minutes: 2),
          ),
        );
        final body = response.data;
        if (body == null) throw const HttpException('Empty update response');
        if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          await body.stream.listen(null).cancel();
          final location = response.headers.value('location');
          if (location == null) {
            throw const HttpException('Missing update redirect');
          }
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode != 200) {
          await body.stream.listen(null).cancel();
          throw HttpException('Update HTTP ${response.statusCode}');
        }
        final contentLength = int.tryParse(
          response.headers.value('content-length') ?? '',
        );
        if (contentLength != null && contentLength != task.release.size) {
          await body.stream.listen(null).cancel();
          throw const FormatException('Update size mismatch');
        }
        var received = 0;
        sink = part.openWrite();
        await for (final bytes in body.stream) {
          cancelToken.checkUpdateCancellation();
          received += bytes.length;
          if (received > task.release.size) {
            throw const FormatException('Update exceeds expected size');
          }
          sink.add(bytes);
          onProgress(received);
        }
        await sink.flush();
        await sink.close();
        sink = null;
        cancelToken.checkUpdateCancellation();
        if (received != task.release.size) {
          throw const FormatException('Incomplete update');
        }
        return part;
      }
      throw const HttpException('Too many update redirects');
    } on Object {
      await sink?.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }
}

extension UpdateCancellation on CancelToken {
  void checkUpdateCancellation() {
    if (isCancelled) throw cancelError!;
  }
}
