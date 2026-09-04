// features/expenses/domain/expense.dart

class Expense {
  final String id;
  final String title;
  final double amount;
  final DateTime date;
  final String? category;

  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    this.category,
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
    );
  }
}

double _asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
