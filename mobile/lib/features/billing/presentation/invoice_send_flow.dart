// features/billing/presentation/invoice_send_flow.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../data/billing_repository.dart';
import 'billing_invoice_helpers.dart';
import 'billing_providers.dart';
import 'whatsapp_reminder.dart';

String _formatYmd(dynamic raw) {
  final d = invoiceCalendarDate(raw);
  return d == null ? '—' : DateFormat('d MMM yyyy').format(d);
}

/// Confirm → mark the draft as sent (tenant sees it + in-app notification)
/// → offer a prefilled WhatsApp message. Returns true when the invoice was sent.
Future<bool> confirmAndSendInvoice(
  BuildContext context,
  WidgetRef ref, {
  required String propertyId,
  required Map<String, dynamic> invoice,
  String? tenantName,
  String? phone,
}) async {
  final id = invoice['id']?.toString();
  if (id == null || id.isEmpty) return false;

  final name = (tenantName ?? invoice['full_name']?.toString() ?? 'Tenant').trim();
  final amount = invoiceRemaining(invoice);
  final dueLabel = _formatYmd(invoice['due_date'] ?? invoice['dueDate']);
  final periodLabel =
      '${_formatYmd(invoice['period_start'] ?? invoice['periodStart'])} – '
      '${_formatYmd(invoice['period_end'] ?? invoice['periodEnd'])}';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Send invoice?'),
      content: Text(
        '$name will see this invoice in the app and get a notification.\n\n'
        'Period: $periodLabel\n'
        'Amount: ${billingCurrency.format(amount)}\n'
        'Due: $dueLabel',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Send'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  Map<String, dynamic> sent;
  try {
    sent = await ref.read(billingRepositoryProvider).sendInvoice(propertyId, id);
  } catch (e) {
    var msg = '$e';
    if (e is DioException && e.response?.data is Map) {
      msg = (e.response!.data as Map)['error']?.toString() ?? msg;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send invoice: $msg'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
    return false;
  }
  ref.invalidate(invoicesProvider(propertyId));
  if (!context.mounted) return true;

  final resolvedPhone = phone ?? sent['phone']?.toString();
  final share = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Invoice sent'),
      content: Text(
        '$name has been notified in the app. '
        'Do you also want to share it on WhatsApp?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: whatsAppGreen),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.chat, size: 18),
          label: const Text('WhatsApp'),
        ),
      ],
    ),
  );
  if (share == true && context.mounted) {
    await sendWhatsAppReminder(
      context,
      phone: resolvedPhone,
      name: name,
      amount: invoiceRemaining(sent),
      message: whatsAppInvoiceMessage(
        name: name,
        amount: invoiceRemaining(sent),
        periodLabel: periodLabel,
        dueLabel: _formatYmd(sent['due_date'] ?? invoice['due_date']),
      ),
    );
  }
  return true;
}
