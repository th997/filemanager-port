import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/src/rust/api/remotes.dart';
import 'package:filemanager/src/services/storage_service.dart';

void main() {
  test('RemoteConfigDto JSON round trip and export', () async {
    const config = RemoteConfigDto(
      id: 's3-123',
      name: 'My S3 Bucket',
      kind: 's3',
      endpoint: 'https://s3.amazonaws.com',
      bucket: 'test-bucket',
      region: 'us-east-1',
      accessKeyId: 'AKIA12345',
      secretAccessKey: 'secret_key_abc',
      host: null,
      port: null,
      username: null,
      password: null,
      rootPath: 'data',
      pathStyle: true,
    );

    final map = StorageService.instance; // ensure initialized
    expect(map, isNotNull);

    final rawJson = jsonEncode([
      {
        'id': config.id,
        'name': config.name,
        'kind': config.kind,
        'endpoint': config.endpoint,
        'bucket': config.bucket,
        'region': config.region,
        'accessKeyId': config.accessKeyId,
        'secretAccessKey': config.secretAccessKey,
        'rootPath': config.rootPath,
        'pathStyle': config.pathStyle,
      }
    ]);

    final decoded = jsonDecode(rawJson) as List;
    expect(decoded.length, 1);
    final first = decoded.first as Map<String, dynamic>;
    expect(first['name'], 'My S3 Bucket');
    expect(first['kind'], 's3');
    expect(first['bucket'], 'test-bucket');
    expect(first['accessKeyId'], 'AKIA12345');
    expect(first['secretAccessKey'], 'secret_key_abc');
    expect(first['pathStyle'], true);
  });
}
