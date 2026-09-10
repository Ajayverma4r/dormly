// features/billing/presentation/record_payment_dialog.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const _accent = AppColors.primary;

const paymentModes = [
  (value: 'upi', label: 'UPI'),
  (value: 'cash', label: 'Cash'),
  (value: 'bank', label: 'Bank'),
];

class RecordPaymentResult {
  final double amount;
  final String method;

  const RecordPaymentResult({
    required this.amount,
    required this.method,
  });
}

/// Shared Record Payment dialog with amount + payment mode (UPI / Cash / Bank).
Future<RecordPaymentResult?> showRecordPaymentDialog({
  required BuildContext context,
  String? headline,
  String? outstandingLabel,
  required double initialAmount,
  double? maxAmount,
  String initialMethod = 'upi',
}) {
  return showDialog<RecordPaymentResult>(
    context: context,
    builder: (ctx) => _RecordPaymentDialog(
      headline: headline,
      outstandingLabel: outstandingLabel,
      initialAmount: initialAmount,
      maxAmount: maxAmount,
      initialMethod: initialMethod,
    ),
  );
}

class _RecordPaymentDialog extends StatefulWidget {
  final String? headline;
  final String? outstandingLabel;
  final double initialAmount;
  final double? maxAmount;
  final String initialMethod;

  const _RecordPaymentDialog({
    this.headline,
    this.outstandingLabel,
    required this.initialAmount,
    this.maxAmount,
    required this.initialMethod,
  });

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  late final TextEditingController _amountController;
  late String _selectedPaymentMode;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final seed = widget.initialAmount;
    _amountController = TextEditingController(
      text: seed == seed.roundToDouble()
          ? seed.toStringAsFixed(0)
          : seed.toStringAsFixed(2),
    );
    _selectedPaymentMode = widget.initialMethod;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;
    Navigator.pop(
      context,
      RecordPaymentResult(amount: amount, method: _selectedPaymentMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record Payment'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.headline != null && widget.headline!.isNotEmpty) ...[
              Text(
                widget.headline!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
            ],
            if (widget.outstandingLabel != null &&
                widget.outstandingLabel!.isNotEmpty) ...[
              Text(
                widget.outstandingLabel!,
                style: const TextStyle(color: AppColors.slate, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _amountController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                labelText: 'Amount received',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter a valid amount';
                final max = widget.maxAmount;
                if (max != null && n > max + 0.01) {
                  return 'Cannot exceed outstanding balance';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Payment Mode',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in paymentModes)
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: _selectedPaymentMode == mode.value,
                    onSelected: (_) =>
                        setState(() => _selectedPaymentMode = mode.value),
                    selectedColor: AppColors.primarySoft,
                    checkmarkColor: _accent,
                    labelStyle: TextStyle(
                      color: _selectedPaymentMode == mode.value
                          ? _accent
                          : AppColors.ink,
                      fontWeight: _selectedPaymentMode == mode.value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                      color: _selectedPaymentMode == mode.value
                          ? _accent
                          : AppColors.hairline,
                      width: _selectedPaymentMode == mode.value ? 1.5 : 1,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: _accent),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
