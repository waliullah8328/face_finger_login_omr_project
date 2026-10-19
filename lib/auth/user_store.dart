import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'face_math.dart';

/// A teacher registered on this phone, identified by their face.
class AppUser {
  final String id;
  final String name;
  final String institution;

  /// Normalized face embeddings captured at sign up.
  final List<List<double>> faces;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.name,
    required this.institution,
    required this.faces,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'institution': institution,
        'faces': faces,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        name: json['name'] as String,
        institution: json['institution'] as String? ?? '',
        faces: [
          for (final f in json['faces'] as List)
            [for (final x in f as List) (x as num).toDouble()],
        ],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Users, the logged-in session and the fingerprint owner, kept on the phone
/// in [SharedPreferences].
class UserStore {
  UserStore._(this._prefs);

  static Future<UserStore> instance() async =>
      UserStore._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _usersKey = 'auth_users';
  static const _sessionKey = 'auth_session';
  static const _fingerprintKey = 'auth_fingerprint_user';

  List<AppUser> get users {
    final raw = _prefs.getString(_usersKey);
    if (raw == null) return [];
    try {
      return [
        for (final u in jsonDecode(raw) as List)
          AppUser.fromJson(u as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveUsers(List<AppUser> users) => _prefs.setString(
      _usersKey, jsonEncode([for (final u in users) u.toJson()]));

  AppUser? byId(String? id) {
    if (id == null) return null;
    for (final u in users) {
      if (u.id == id) return u;
    }
    return null;
  }

  AppUser? get currentUser => byId(_prefs.getString(_sessionKey));

  Future<void> login(AppUser user) => _prefs.setString(_sessionKey, user.id);

  Future<void> logout() => _prefs.remove(_sessionKey);

  /// The one account the phone's fingerprint unlocks (the sensor only knows
  /// "phone owner", not which teacher).
  AppUser? get fingerprintUser => byId(_prefs.getString(_fingerprintKey));

  Future<void> setFingerprintUser(AppUser? user) => user == null
      ? _prefs.remove(_fingerprintKey)
      : _prefs.setString(_fingerprintKey, user.id);

  /// The registered user whose face is closest to [probe], if close enough.
  AppUser? recognize(List<double> probe) {
    final match = bestMatch(probe, users, (u) => u.faces);
    return match != null && match.isMatch ? match.candidate : null;
  }

  Future<AppUser> register({
    required String name,
    required String institution,
    required List<List<double>> faces,
  }) async {
    final user = AppUser(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name.trim(),
      institution: institution.trim(),
      faces: faces,
      createdAt: DateTime.now(),
    );
    await _saveUsers([...users, user]);
    return user;
  }

  Future<void> delete(AppUser user) async {
    await _saveUsers([for (final u in users) if (u.id != user.id) u]);
    if (_prefs.getString(_sessionKey) == user.id) await logout();
    if (_prefs.getString(_fingerprintKey) == user.id) {
      await setFingerprintUser(null);
    }
  }
}
