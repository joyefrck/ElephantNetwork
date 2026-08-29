class XboardAccount {
  const XboardAccount({
    required this.email,
    required this.balance,
    required this.upload,
    required this.download,
    required this.planTransferEnable,
    required this.planUsedTraffic,
    required this.planRemainingTraffic,
    required this.trafficPackageTotal,
    required this.trafficPackageRemaining,
    required this.effectiveTransferEnable,
    required this.effectiveRemainingTraffic,
    this.planId,
    this.expiredAt,
    this.nextResetAt,
  });

  factory XboardAccount.fromJson(Map<String, Object?> json) {
    final upload = _int(json['u']);
    final download = _int(json['d']);
    final transferEnable = _int(json['transfer_enable']);
    final planTransferEnable = _int(
      json['plan_transfer_enable'],
      fallback: transferEnable,
    );
    final planUsedTraffic = _int(
      json['plan_used_traffic'],
      fallback: upload + download,
    );
    final planRemainingTraffic = _int(
      json['plan_remaining_traffic'],
      fallback: (planTransferEnable - planUsedTraffic).clamp(
        0,
        planTransferEnable,
      ),
    );
    final trafficPackageRemaining = _int(json['traffic_package_remaining']);
    final effectiveTransferEnable = _int(
      json['effective_transfer_enable'],
      fallback: transferEnable,
    );
    final effectiveRemainingTraffic = _int(
      json['effective_remaining_traffic'],
      fallback: (planRemainingTraffic + trafficPackageRemaining).clamp(
        0,
        effectiveTransferEnable,
      ),
    );
    return XboardAccount(
      email: json['email'] as String? ?? '',
      balance: _int(json['balance']),
      upload: upload,
      download: download,
      planId: _nullableInt(json['plan_id']),
      expiredAt: _nullableInt(json['expired_at']),
      nextResetAt: _nullableInt(json['next_reset_at']),
      planTransferEnable: planTransferEnable,
      planUsedTraffic: planUsedTraffic,
      planRemainingTraffic: planRemainingTraffic,
      trafficPackageTotal: _int(json['traffic_package_total']),
      trafficPackageRemaining: trafficPackageRemaining,
      effectiveTransferEnable: effectiveTransferEnable,
      effectiveRemainingTraffic: effectiveRemainingTraffic,
    );
  }

  final String email;
  final int balance;
  final int upload;
  final int download;
  final int? planId;
  final int? expiredAt;
  final int? nextResetAt;
  final int planTransferEnable;
  final int planUsedTraffic;
  final int planRemainingTraffic;
  final int trafficPackageTotal;
  final int trafficPackageRemaining;
  final int effectiveTransferEnable;
  final int effectiveRemainingTraffic;

  bool get isExpired {
    final value = expiredAt;
    if (value == null) return false;
    return DateTime.now().millisecondsSinceEpoch >= value * 1000;
  }

  String get accountId => email.trim().toLowerCase();

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    return _int(value);
  }
}

class XboardSession {
  const XboardSession({required this.token, required this.account});

  final String token;
  final XboardAccount account;
}

enum XboardSessionStatus {
  loading,
  authenticating,
  unauthenticated,
  authenticated,
  unavailable,
}

class XboardSessionState {
  const XboardSessionState({required this.status, this.session, this.error});

  const XboardSessionState.loading()
    : status = XboardSessionStatus.loading,
      session = null,
      error = null;

  const XboardSessionState.unauthenticated([this.error])
    : status = XboardSessionStatus.unauthenticated,
      session = null;

  const XboardSessionState.authenticating()
    : status = XboardSessionStatus.authenticating,
      session = null,
      error = null;

  const XboardSessionState.authenticated(this.session, {this.error})
    : status = XboardSessionStatus.authenticated;

  const XboardSessionState.unavailable(this.error)
    : status = XboardSessionStatus.unavailable,
      session = null;

  final XboardSessionStatus status;
  final XboardSession? session;
  final Object? error;

  bool get isAuthenticated => status == XboardSessionStatus.authenticated;
}
