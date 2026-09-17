// features/tenancies/domain/tenant_settlement.dart
//
// Fraud-proof final settlement model for move-out checkout.

enum SettlementStatus { pending, refunded, collected }

enum ElectricityInputMode { byMeterUnits, directAmount }

class SettlementDamageItem {
  final String id;
  final String title;
  final double amount;
  final String? photoPath;
  final String? note;

  const SettlementDamageItem({
    required this.id,
    required this.title,
    required this.amount,
    this.photoPath,
    this.note,
  });

  SettlementDamageItem copyWith({
    String? title,
    double? amount,
    String? photoPath,
    String? note,
  }) {
    return SettlementDamageItem(
      id: id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      photoPath: photoPath ?? this.photoPath,
      note: note ?? this.note,
    );
  }
}

class TenantSettlement {
  final double originalDeposit;
  final double pendingRent;
  final ElectricityInputMode electricityMode;
  final double? meterStartReading;
  final double? meterEndReading;
  final double? perUnitRate;
  final double? directElectricityAmount;
  final double standardCleaningCharge;
  final bool cleaningApplied;
  final List<SettlementDamageItem> customDeductions;
  final SettlementStatus settlementStatus;
  final String? paymentMode;
  final String? txnReferenceId;
  final DateTime? settledAt;

  const TenantSettlement({
    required this.originalDeposit,
    required this.pendingRent,
    this.electricityMode = ElectricityInputMode.byMeterUnits,
    this.meterStartReading,
    this.meterEndReading,
    this.perUnitRate,
    this.directElectricityAmount,
    this.standardCleaningCharge = 500,
    this.cleaningApplied = true,
    this.customDeductions = const [],
    this.settlementStatus = SettlementStatus.pending,
    this.paymentMode,
    this.txnReferenceId,
    this.settledAt,
  });

  double get electricityUnits {
    if (electricityMode != ElectricityInputMode.byMeterUnits) return 0;
    if (meterStartReading == null || meterEndReading == null) return 0;
    final units = meterEndReading! - meterStartReading!;
    return units > 0 ? units : 0;
  }

  double get electricityCharge {
    if (electricityMode == ElectricityInputMode.directAmount) {
      return (directElectricityAmount ?? 0).clamp(0, 1e12).toDouble();
    }
    if (perUnitRate == null) return 0;
    return electricityUnits * perUnitRate!;
  }

  double get cleaningCharge =>
      cleaningApplied ? standardCleaningCharge : 0;

  double get damagesTotal =>
      customDeductions.fold(0.0, (sum, d) => sum + d.amount);

  double get totalDeductions =>
      pendingRent + electricityCharge + cleaningCharge + damagesTotal;

  /// Deposit − all deductions. Positive = refund to tenant; negative = collect.
  double get netAmount => originalDeposit - totalDeductions;

  bool get isRefund => netAmount >= 0;

  TenantSettlement copyWith({
    double? originalDeposit,
    double? pendingRent,
    ElectricityInputMode? electricityMode,
    double? meterStartReading,
    double? meterEndReading,
    double? perUnitRate,
    double? directElectricityAmount,
    double? standardCleaningCharge,
    bool? cleaningApplied,
    List<SettlementDamageItem>? customDeductions,
    SettlementStatus? settlementStatus,
    String? paymentMode,
    String? txnReferenceId,
    DateTime? settledAt,
  }) {
    return TenantSettlement(
      originalDeposit: originalDeposit ?? this.originalDeposit,
      pendingRent: pendingRent ?? this.pendingRent,
      electricityMode: electricityMode ?? this.electricityMode,
      meterStartReading: meterStartReading ?? this.meterStartReading,
      meterEndReading: meterEndReading ?? this.meterEndReading,
      perUnitRate: perUnitRate ?? this.perUnitRate,
      directElectricityAmount:
          directElectricityAmount ?? this.directElectricityAmount,
      standardCleaningCharge:
          standardCleaningCharge ?? this.standardCleaningCharge,
      cleaningApplied: cleaningApplied ?? this.cleaningApplied,
      customDeductions: customDeductions ?? this.customDeductions,
      settlementStatus: settlementStatus ?? this.settlementStatus,
      paymentMode: paymentMode ?? this.paymentMode,
      txnReferenceId: txnReferenceId ?? this.txnReferenceId,
      settledAt: settledAt ?? this.settledAt,
    );
  }

  /// Persistable summary stored in tenancy notes.
  String toNotesBlock() {
    final buf = StringBuffer();
    buf.writeln(
      'SETTLEMENT ${settledAt?.toIso8601String().split('T').first ?? ''}',
    );
    buf.writeln('Deposit: $originalDeposit');
    buf.writeln('Pending rent: $pendingRent');
    if (electricityMode == ElectricityInputMode.directAmount) {
      buf.writeln('Electricity (direct): $electricityCharge');
    } else {
      buf.writeln(
        'Electricity: $electricityUnits units × ${perUnitRate ?? 0} = $electricityCharge',
      );
    }
    buf.writeln('Cleaning: $cleaningCharge');
    buf.writeln('Damages: $damagesTotal');
    for (final d in customDeductions) {
      buf.writeln(
        '  - ${d.title}: ${d.amount}'
        '${d.note != null && d.note!.isNotEmpty ? ' (${d.note})' : ''}'
        '${d.photoPath != null ? ' [photo]' : ''}',
      );
    }
    buf.writeln('Net: $netAmount');
    buf.writeln('Status: ${settlementStatus.name}');
    if (paymentMode != null) buf.writeln('Payment mode: $paymentMode');
    if (txnReferenceId != null && txnReferenceId!.isNotEmpty) {
      buf.writeln('Ref: $txnReferenceId');
    }
    return buf.toString();
  }
}
