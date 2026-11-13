class PaymentRecord {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String senderBank;
  final int amount;
  final String? localProofPath;
  final String? remoteProofUrl;
  final String status; // 'PENDING', 'VERIFIED', 'REJECTED'
  final String? notes;
  final DateTime createdAt;

  const PaymentRecord({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.senderBank,
    required this.amount,
    this.localProofPath,
    this.remoteProofUrl,
    this.status = 'PENDING',
    this.notes,
    required this.createdAt,
  });

  PaymentRecord copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userEmail,
    String? senderBank,
    int? amount,
    String? localProofPath,
    String? remoteProofUrl,
    String? status,
    String? notes,
    DateTime? createdAt,
  }) {
    return PaymentRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      senderBank: senderBank ?? this.senderBank,
      amount: amount ?? this.amount,
      localProofPath: localProofPath ?? this.localProofPath,
      remoteProofUrl: remoteProofUrl ?? this.remoteProofUrl,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'userEmail': userEmail,
        'senderBank': senderBank,
        'amount': amount,
        'localProofPath': localProofPath,
        'remoteProofUrl': remoteProofUrl,
        'status': status,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
        id: json['id'] as String? ?? 'PAY-${DateTime.now().millisecondsSinceEpoch}',
        userId: json['userId'] as String? ?? '',
        userName: json['userName'] as String? ?? '',
        userEmail: json['userEmail'] as String? ?? '',
        senderBank: json['senderBank'] as String? ?? 'QRIS',
        amount: (json['amount'] as num?)?.toInt() ?? 15000,
        localProofPath: json['localProofPath'] as String?,
        remoteProofUrl: json['remoteProofUrl'] as String?,
        status: json['status'] as String? ?? 'PENDING',
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}
