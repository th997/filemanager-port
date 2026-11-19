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

  test('RemoteConfigDto SFTP with private key and passphrase round trip', () async {
    const sftpConfig = RemoteConfigDto(
      id: 'sftp-key',
      name: 'SFTP Server',
      kind: 'sftp',
      host: '192.168.1.100',
      port: 22,
      username: 'deploy',
      password: null,
      privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\nMIIE...\n-----END OPENSSH PRIVATE KEY-----',
      passphrase: 'key_passphrase_123',
      rootPath: '/var/www',
      pathStyle: false,
    );

    final rawJson = jsonEncode([
      {
        'id': sftpConfig.id,
        'name': sftpConfig.name,
        'kind': sftpConfig.kind,
        'host': sftpConfig.host,
        'port': sftpConfig.port,
        'username': sftpConfig.username,
        'privateKey': sftpConfig.privateKey,
        'passphrase': sftpConfig.passphrase,
        'rootPath': sftpConfig.rootPath,
        'pathStyle': sftpConfig.pathStyle,
      }
    ]);

    final decoded = jsonDecode(rawJson) as List;
    expect(decoded.length, 1);
    final first = decoded.first as Map<String, dynamic>;
    expect(first['name'], 'SFTP Server');
    expect(first['kind'], 'sftp');
    expect(first['host'], '192.168.1.100');
    expect(first['port'], 22);
    expect(first['username'], 'deploy');
    expect(first['privateKey'], contains('BEGIN OPENSSH PRIVATE KEY'));
    expect(first['passphrase'], 'key_passphrase_123');
    expect(first['rootPath'], '/var/www');
  });
}
