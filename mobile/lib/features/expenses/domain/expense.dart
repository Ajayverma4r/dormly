// features/expenses/domain/expense.dart

class Expense {
  final String id;
  final String title;
  final double amount;
  final DateTime date;
  final String? category;
  final String? receiptUrl;

  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    this.category,
    this.receiptUrl,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    final dateRaw =
        (json['expense_date'] ?? json['expenseDate'] ?? json['date'])
            ?.toString();
    final parsed = dateRaw != null ? DateTime.tryParse(dateRaw) : null;

    return Expense(
      id: (json['id'] ?? '').toString(),
      title: (json['description'] ?? json['title'] ?? '').toString(),
      amount: _asDouble(json['amount']),
      date: parsed ?? DateTime.now(),
      category: json['category']?.toString(),
      receiptUrl: (json['receipt_url'] ?? json['receiptUrl'])?.toString(),
    );
  }

  bool get hasReceipt {
    final url = receiptUrl?.trim();
    return url != null && url.isNotEmpty;
  }
}

double _asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
