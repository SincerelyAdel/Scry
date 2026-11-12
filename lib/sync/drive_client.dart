import 'dart:convert';

import 'package:dio/dio.dart';

import 'sync_engine.dart';

/// The access token was refused; sign in again.
class DriveAuthException implements Exception {
  const DriveAuthException();

  @override
  String toString() => 'Google sign-in has expired';
}

/// Reads and writes Scry's one file in the hidden app data folder of the
/// person's Google Drive, which only Scry can see.
class DriveClient implements RemoteStore {
  DriveClient(this._token, {Dio? dio}) : _dio = dio ?? Dio();

  static const fileName = 'scry-sync.json';
  static const _api = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  final String _token;
  final Dio _dio;

  Options get _auth => Options(
    headers: {'Authorization': 'Bearer $_token'},
    responseType: ResponseType.plain,
  );

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) throw const DriveAuthException();
      rethrow;
    }
  }

  /// The file's id and version, or null when there's none yet.
  Future<({String id, String version})?> find() => _call(() async {
    final res = await _dio.get<String>(
      _api,
      queryParameters: {
        'spaces': 'appDataFolder',
        'q': "name = '$fileName' and trashed = false",
        'fields': 'files(id,version)',
        'orderBy': 'modifiedTime desc',
      },
      options: _auth,
    );
    final files = (jsonDecode(res.data!) as Map)['files'] as List;
    if (files.isEmpty) return null;
    final f = files.first as Map;
    return (id: f['id'] as String, version: '${f['version']}');
  });

  @override
  Future<({String id, String version, Map<String, Object?>? content})?>
  read() => _call(() async {
    final found = await find();
    if (found == null) return null;
    final res = await _dio.get<String>(
      '$_api/${found.id}',
      queryParameters: {'alt': 'media'},
      options: _auth,
    );
    final body = res.data ?? '';
    return (
      id: found.id,
      version: found.version,
      content: body.trim().isEmpty
          ? null
          : (jsonDecode(body) as Map).cast<String, Object?>(),
    );
  });

  @override
  Future<String?> version(String id) => _call(() async {
    final res = await _dio.get<String>(
      '$_api/$id',
      queryParameters: {'fields': 'version'},
      options: _auth,
    );
    return '${(jsonDecode(res.data!) as Map)['version']}';
  });

  @override
  Future<void> write(String? id, Map<String, Object?> content) =>
      _call(() async {
        final body = jsonEncode(content);
        if (id != null) {
          await _dio.patch<String>(
            '$_upload/$id',
            queryParameters: {'uploadType': 'media'},
            data: body,
            options: _auth.copyWith(contentType: 'application/json'),
          );
          return;
        }
        const boundary = 'scry-sync-boundary';
        final metadata = jsonEncode({
          'name': fileName,
          'parents': ['appDataFolder'],
        });
        final multipart =
            '--$boundary\r\n'
            'Content-Type: application/json; charset=UTF-8\r\n\r\n'
            '$metadata\r\n'
            '--$boundary\r\n'
            'Content-Type: application/json\r\n\r\n'
            '$body\r\n'
            '--$boundary--';
        await _dio.post<String>(
          _upload,
          queryParameters: {'uploadType': 'multipart'},
          data: utf8.encode(multipart),
          options: _auth.copyWith(
            contentType: 'multipart/related; boundary=$boundary',
          ),
        );
      });
}
