import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../data/database/database.dart';

/// 笔记加密服务：密码 → PBKDF2 派生密钥 → AES-GCM 封存主密钥；
/// 笔记内容用主密钥 AES-GCM 加密（每笔记随机 nonce）。
/// 错误密码 → GCM 认证失败 → 视为密码错误。
///
/// 密文格式：`enc:v1:<nonceB64>:<cipherB64>`
class SecretService {
  SecretService(this._db);
  final AppDatabase _db;

  static const _iterations = 100000;
  static const _saltLen = 16;
  static const _nonceLen = 12;
  static const _masterKeyLen = 32;
  static const _prefix = 'enc:v1:';

  final _random = Random.secure();
  final _aesGcm = AesGcm.with256bits();

  /// 是否已设置主密钥（是否曾创建过加密笔记）。
  Future<bool> hasMasterKey() async =>
      (await _db.select(_db.secrets).get()).isNotEmpty;

  /// 是否已解锁（内存中持有主密钥）。
  bool unlocked = false;

  SecretKey? _masterKey;

  /// 设置/重置主密钥：生成随机主密钥并用密码封存。
  Future<void> setup(String password) async {
    final salt = _randomBytes(_saltLen);
    final derived = await _deriveKey(password, salt);
    final master = _randomBytes(_masterKeyLen);
    final nonce = _randomBytes(_nonceLen);
    final sealed = await _aesGcm.encrypt(
      master,
      secretKey: derived,
      nonce: nonce,
    );
    await _db.into(_db.secrets).insertOnConflictUpdate(
      SecretsCompanion.insert(
        id: 'master',
        salt: base64Encode(salt),
        nonce: base64Encode(nonce),
        sealedKey: base64Encode(sealed.concatenation()),
        updatedAt: DateTime.now(),
      ),
    );
    _masterKey = SecretKey(master);
    unlocked = true;
  }

  /// 用密码解锁；密码错误返回 false。
  Future<bool> unlock(String password) async {
    final record = await (_db.select(_db.secrets)..where((s) => s.id.equals('master')))
        .getSingleOrNull();
    if (record == null) return false;
    final derived = await _deriveKey(password, base64Decode(record.salt));
    try {
      // sealedKey 存的是 nonce||cipher||mac 拼接，用官方解析还原
      final box = SecretBox.fromConcatenation(
        base64Decode(record.sealedKey),
        nonceLength: _nonceLen,
        macLength: 16, // AES-GCM 认证标签固定 128 位
      );
      final sealed = await _aesGcm.decrypt(box, secretKey: derived);
      _masterKey = SecretKey(sealed);
      unlocked = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 锁定：丢弃内存中的主密钥（退出编辑/应用时调用）。
  void lock() {
    _masterKey = null;
    unlocked = false;
  }

  /// 加密明文（需要已解锁），返回 `enc:v1:...` 字符串。
  Future<String> encrypt(String plaintext) async {
    final key = _requireKey();
    final nonce = _randomBytes(_nonceLen);
    final sealed = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return '$_prefix${base64Encode(nonce)}:${base64Encode(sealed.concatenation())}';
  }

  /// 解密密文（需要已解锁）。非本服务密文原样返回。
  Future<String> decrypt(String stored) async {
    if (!stored.startsWith(_prefix)) return stored;
    final key = _requireKey();
    final parts = stored.substring(_prefix.length).split(':');
    if (parts.length != 2) return stored;
    try {
      // parts[1] 为 nonce||cipher||mac 拼接（nonce 已含在内）
      final box = SecretBox.fromConcatenation(
        base64Decode(parts[1]),
        nonceLength: _nonceLen,
        macLength: 16,
      );
      final plain = await _aesGcm.decrypt(box, secretKey: key);
      return utf8.decode(plain);
    } catch (_) {
      return '';
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: _masterKeyLen * 8,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  SecretKey _requireKey() {
    final key = _masterKey;
    if (key == null) {
      throw StateError('SecretService 未解锁');
    }
    return key;
  }

  List<int> _randomBytes(int n) =>
      List<int>.generate(n, (_) => _random.nextInt(256));
}
