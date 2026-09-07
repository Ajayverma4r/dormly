// features/billing/presentation/invoices_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import 'billing_providers.dart';
import 'create_invoice_screen.dart';
import 'live_collection_tab.dart';
import 'reports_history_tab.dart';

export 'billing_providers.dart'
    show invoicesProvider, receivedThisMonthProvider;

const _accent = Color(0xFF7C3AED);
const _accentSoft = Color(0xFFF3E8FF);

enum PaymentsSegment { liveCollection, reports }

class InvoicesListScreen extends ConsumerStatefulWidget {
  final String propertyId;
  final bool asTab;

  const InvoicesListScreen({
    super.key,
    required this.propertyId,
    this.asTab = false,
  });

  @override
  ConsumerState<InvoicesListScreen> createState() => _InvoicesListScreenState();
}

class _InvoicesListScreenState extends ConsumerState<InvoicesListScreen> {
  PaymentsSegment _segment = PaymentsSegment.liveCollection;
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
  }

  List<DateTime> get _monthOptions {
    final now = DateTime.now();
    return List.generate(24, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return DateTime(d.year, d.month, 1);
    });
  }

  Future<void> _openNewInvoice() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(propertyId: widget.propertyId),
      ),
    );
    if (created == true) {
      ref.invalidate(invoicesProvider(widget.propertyId));
      ref.invalidate(receivedThisMonthProvider(widget.propertyId));
      ref.invalidate(paymentsProvider(widget.propertyId));
    }
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
                  title: Text(DateFormat('MMMM yyyy').format(m)),
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
    if (picked != null) {
      setState(() => _selectedMonth = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: widget.asTab
          ? null
          : AppBar(title: const Text('Rent & Billing')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _PaymentsHeader(
                selectedMonth: _selectedMonth,
                onMonthTap: _pickMonth,
                onNewInvoice: _openNewInvoice,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _PaymentsSegmentControl(
                segment: _segment,
                onChanged: (s) => setState(() => _segment = s),
              ),
            ),
            Expanded(
              child: _segment == PaymentsSegment.liveCollection
                  ? LiveCollectionTab(
                      propertyId: widget.propertyId,
                      selectedMonth: _selectedMonth,
                    )
                  : ReportsHistoryTab(propertyId: widget.propertyId),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentsHeader extends StatelessWidget {
  final DateTime selectedMonth;
  final VoidCallback onMonthTap;
  final VoidCallback onNewInvoice;

  const _PaymentsHeader({
    required this.selectedMonth,
    required this.onMonthTap,
    required this.onNewInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(selectedMonth);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Payments',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: onMonthTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        monthLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: Colors.grey.shade600,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onNewInvoice,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(
            'New Invoice',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _PaymentsSegmentControl extends StatelessWidget {
  final PaymentsSegment segment;
  final ValueChanged<PaymentsSegment> onChanged;

  const _PaymentsSegmentControl({
    required this.segment,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentChip(
              label: 'Live Collection',
              selected: segment == PaymentsSegment.liveCollection,
              onTap: () => onChanged(PaymentsSegment.liveCollection),
            ),
          ),
          Expanded(
            child: _SegmentChip(
              label: 'Reports',
              selected: segment == PaymentsSegment.reports,
              onTap: () => onChanged(PaymentsSegment.reports),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: selected
                ? Border.all(color: _accent.withValues(alpha: 0.35))
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? _accent : AppColors.slate,
            ),
          ),
        ),
      ),
    );
  }
}
