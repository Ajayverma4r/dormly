// features/expenses/presentation/expense_history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../dashboard/presentation/property_dashboard_provider.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';

const _accent = AppColors.primary;

final _monthFormat = DateFormat('MMMM yyyy');
final _dayFormat = DateFormat('d MMM yyyy');
final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class ExpenseHistoryScreen extends ConsumerStatefulWidget {
  final String propertyId;

  const ExpenseHistoryScreen({super.key, required this.propertyId});

  @override
  ConsumerState<ExpenseHistoryScreen> createState() =>
      _ExpenseHistoryScreenState();
}

class _ExpenseHistoryScreenState extends ConsumerState<ExpenseHistoryScreen> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  List<DateTime> get _monthOptions {
    final now = DateTime.now();
    return List.generate(24, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return DateTime(d.year, d.month);
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Select month',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.ink,
                  ),
                ),
              ),
              for (final m in _monthOptions)
                ListTile(
                  title: Text(_monthFormat.format(m)),
                  trailing: m.year == _selectedMonth.year &&
                          m.month == _selectedMonth.month
                      ? const Icon(Icons.check, color: _accent)
                      : null,
                  onTap: () => Navigator.pop(context, m),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) setState(() => _selectedMonth = picked);
  }

  Future<void> _openDetail(Expense expense) async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ExpenseDetailSheet(
        expense: expense,
        propertyId: widget.propertyId,
      ),
    );
    if (deleted == true && mounted) {
      ref.invalidate(expensesProvider(widget.propertyId));
      ref.invalidate(propertyDashboardProvider(widget.propertyId));
    }
  }

  List<Expense> _forMonth(List<Expense> all) {
    return all
        .where((e) =>
            e.date.year == _selectedMonth.year &&
            e.date.month == _selectedMonth.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(expensesProvider(widget.propertyId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Expense History'),
        foregroundColor: _accent,
        titleTextStyle: const TextStyle(
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: const IconThemeData(color: _accent),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.calendar_month_outlined,
                    size: 18, color: _accent),
                label: Text(
                  _monthFormat.format(_selectedMonth),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
                backgroundColor: AppColors.primarySoft,
                side: const BorderSide(color: _accent),
                onPressed: _pickMonth,
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: _accent)),
              error: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not load expenses.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.slate),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => ref
                            .invalidate(expensesProvider(widget.propertyId)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (all) {
                final monthItems = _forMonth(all);
                return RefreshIndicator(
                  color: _accent,
                  onRefresh: () async {
                    ref.invalidate(expensesProvider(widget.propertyId));
                    await ref
                        .read(expensesProvider(widget.propertyId).future);
                  },
                  child: _ExpenseList(
                    expenses: monthItems,
                    emptyLabel:
                        'No expenses in ${_monthFormat.format(_selectedMonth)}',
                    onOpen: _openDetail,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseList extends StatelessWidget {
  final List<Expense> expenses;
  final String emptyLabel;
  final ValueChanged<Expense> onOpen;

  const _ExpenseList({
    required this.expenses,
    required this.emptyLabel,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.receipt_long_outlined,
              size: 48, color: AppColors.slate),
          const SizedBox(height: 12),
          Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.slate),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: expenses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ExpenseTile(
        expense: expenses[i],
        onTap: () => onOpen(expenses[i]),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final Expense expense;
  final VoidCallback onTap;
  const _ExpenseTile({required this.expense, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = _categoryMeta(expense.category);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primarySoft,
                child: Icon(meta.icon, color: _accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.title.isEmpty ? meta.label : expense.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${meta.label} · ${_dayFormat.format(expense.date)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _currency.format(expense.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                ),
              ),
              if (expense.hasReceipt)
                IconButton(
                  tooltip: 'View receipt',
                  onPressed: () => _showReceipt(context, expense),
                  icon: const Icon(Icons.receipt_long, color: _accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseDetailSheet extends ConsumerStatefulWidget {
  final Expense expense;
  final String propertyId;

  const _ExpenseDetailSheet({
    required this.expense,
    required this.propertyId,
  });

  @override
  ConsumerState<_ExpenseDetailSheet> createState() =>
      _ExpenseDetailSheetState();
}

class _ExpenseDetailSheetState extends ConsumerState<_ExpenseDetailSheet> {
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final id = widget.expense.id;
    setState(() => _deleting = true);
    try {
      await ref
          .read(expenseRepositoryProvider)
          .delete(widget.propertyId, id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete expense: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final meta = _categoryMeta(expense.category);
    final title = expense.title.isEmpty ? meta.label : expense.title;
    final notes = expense.title.isEmpty || expense.title == meta.label
        ? null
        : expense.title;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                height: 1.25,
              ),
            ),
            if (notes != null && notes != title) ...[
              const SizedBox(height: 6),
              Text(
                notes,
                style: const TextStyle(color: AppColors.slate, height: 1.4),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _currency.format(expense.amount),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Chip(
                  avatar: Icon(meta.icon, size: 16, color: _accent),
                  label: Text(
                    meta.label,
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: AppColors.primarySoft,
                  side: const BorderSide(color: _accent),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppColors.slate),
                const SizedBox(width: 6),
                Text(
                  _dayFormat.format(expense.date),
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Receipt',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            _ReceiptPanel(expense: expense),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _deleting ? null : _confirmDelete,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Delete Expense'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptPanel extends StatelessWidget {
  final Expense expense;
  const _ReceiptPanel({required this.expense});

  @override
  Widget build(BuildContext context) {
    final url = expense.receiptUrl?.trim();
    final isNetwork = url != null &&
        (url.startsWith('http://') || url.startsWith('https://'));

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: expense.hasReceipt ? AppColors.primarySoft : AppColors.canvas,
        child: InkWell(
          onTap: expense.hasReceipt
              ? () => _showReceipt(context, expense)
              : null,
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: expense.hasReceipt
                ? (isNetwork
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _ReceiptPlaceholder(
                          label: 'Receipt attached',
                        ),
                      )
                    : const _ReceiptPlaceholder(label: 'Receipt attached'))
                : const _ReceiptPlaceholder(
                    label: 'No Receipt Attached',
                    muted: true,
                  ),
          ),
        ),
      ),
    );
  }
}

void _showReceipt(BuildContext context, Expense expense) {
  final url = expense.receiptUrl?.trim();
  final isNetwork = url != null &&
      (url.startsWith('http://') || url.startsWith('https://'));

  showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long, color: _accent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Receipt',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 260,
                  width: double.infinity,
                  child: isNetwork
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _ReceiptPlaceholder(
                          label: 'Receipt preview',
                        ),
                      )
                      : const _ReceiptPlaceholder(label: 'Receipt preview'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                expense.title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.slate, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ReceiptPlaceholder extends StatelessWidget {
  final String label;
  final bool muted;

  const _ReceiptPlaceholder({
    required this.label,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppColors.slate : _accent;
    return ColoredBox(
      color: muted ? AppColors.canvas : AppColors.primarySoft,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            muted ? Icons.image_not_supported_outlined : Icons.receipt_long,
            size: 48,
            color: color,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryMeta {
  final String label;
  final IconData icon;
  const _CategoryMeta(this.label, this.icon);
}

_CategoryMeta _categoryMeta(String? raw) {
  switch ((raw ?? 'other').toLowerCase()) {
    case 'maintenance':
      return const _CategoryMeta('Maintenance', Icons.build_outlined);
    case 'utilities':
      return const _CategoryMeta('Utilities', Icons.bolt_outlined);
    case 'salaries':
    case 'salary':
      return const _CategoryMeta('Salary', Icons.payments_outlined);
    case 'supplies':
      return const _CategoryMeta('Supplies', Icons.inventory_2_outlined);
    case 'taxes':
      return const _CategoryMeta('Taxes', Icons.account_balance_outlined);
    default:
      return const _CategoryMeta('Other', Icons.category_outlined);
  }
}

