// features/billing/presentation/invoices_list_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'billing_providers.dart';
import 'create_invoice_screen.dart';
import 'live_collection_tab.dart';
import 'reports_history_tab.dart';

export 'billing_providers.dart'
    show invoicesProvider, receivedThisMonthProvider;

const _accent = Color(0xFF7C3AED);

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

  Future<void> _openNewInvoice() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(propertyId: widget.propertyId),
      ),
    );
    if (created == true) {
      ref.invalidate(invoicesProvider(widget.propertyId));
      ref.invalidate(receivedThisMonthProvider(widget.propertyId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: widget.asTab
          ? null
          : AppBar(title: const Text('Rent & Billing')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _PaymentsHeader(onNewInvoice: _openNewInvoice),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<PaymentsSegment>(
                  groupValue: _segment,
                  backgroundColor: AppColors.canvas,
                  thumbColor: AppColors.surface,
                  padding: const EdgeInsets.all(3),
                  children: {
                    PaymentsSegment.liveCollection: _segmentLabel(
                      'Live Collection',
                      selected: _segment == PaymentsSegment.liveCollection,
                    ),
                    PaymentsSegment.reports: _segmentLabel(
                      'Reports',
                      selected: _segment == PaymentsSegment.reports,
                    ),
                  },
                  onValueChanged: (value) {
                    if (value == null) return;
                    setState(() => _segment = value);
                  },
                ),
              ),
            ),
            Expanded(
              child: _segment == PaymentsSegment.liveCollection
                  ? LiveCollectionTab(propertyId: widget.propertyId)
                  : ReportsHistoryTab(propertyId: widget.propertyId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentLabel(String text, {required bool selected}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.ink : AppColors.slate,
        ),
      ),
    );
  }
}

class _PaymentsHeader extends StatelessWidget {
  final VoidCallback onNewInvoice;

  const _PaymentsHeader({required this.onNewInvoice});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'Payments',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.1,
                ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: onNewInvoice,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
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
