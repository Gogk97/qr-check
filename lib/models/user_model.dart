class UserModel {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final bool isGuest;
  final DateTime loginAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.isGuest,
    required this.loginAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'avatarUrl': avatarUrl,
        'isGuest': isGuest,
        'loginAt': loginAt.toIso8601String(),
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String? ?? 'guest',
        name: json['name'] as String? ?? 'Tamu',
        email: json['email'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        isGuest: json['isGuest'] as bool? ?? true,
        loginAt: json['loginAt'] != null
            ? DateTime.tryParse(json['loginAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  factory UserModel.guest({String? deviceId}) => UserModel(
        id: (deviceId != null && deviceId.isNotEmpty)
            ? 'guest_$deviceId'
            : 'guest_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Pengguna Tamu',
        email: 'guest@qrcheck.local',
        isGuest: true,
        loginAt: DateTime.now(),
      );

  factory UserModel.googleUser({
    String? id,
    required String name,
    required String email,
    String? avatarUrl,
  }) =>
      UserModel(
        id: id ?? 'google_${email.hashCode.abs()}',
        name: name,
        email: email,
        avatarUrl: avatarUrl,
        isGuest: false,
        loginAt: DateTime.now(),
      );
}
