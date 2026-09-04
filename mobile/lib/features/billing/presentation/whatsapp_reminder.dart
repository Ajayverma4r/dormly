// features/billing/presentation/whatsapp_reminder.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

const whatsAppGreen = Color(0xFF25D366);

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Digits-only phone suitable for WhatsApp (`country_code` + number).
/// Indian 10-digit mobiles get a `91` prefix.
String? normalizeWhatsAppPhone(String? raw) {
  if (raw == null) return null;
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('0')) {
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
  }
  if (digits.length == 10) {
    digits = '91$digits';
  }
  if (digits.length < 10) return null;
  return digits;
}

String whatsAppReminderMessage(String name, double amount) {
  final displayName = name.trim().isEmpty ? 'there' : name.trim();
  final amountText = _currency.format(amount);
  return 'Hi $displayName, this is a gentle reminder that your pending '
      'rent/dues of $amountText are currently outstanding. Please clear them '
      'at your earliest convenience.';
}

/// Opens WhatsApp with a pre-filled dues reminder. Shows a SnackBar on failure.
Future<void> sendWhatsAppReminder(
  BuildContext context, {
  required String? phone,
  required String name,
  required double amount,
}) async {
  final normalized = normalizeWhatsAppPhone(phone);
  if (normalized == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid phone number on file for this tenant.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
    return;
  }

  final message = whatsAppReminderMessage(name, amount);
  final encoded = Uri.encodeComponent(message);

  final native = Uri.parse(
    'whatsapp://send?phone=$normalized&text=$encoded',
  );
  final web = Uri.parse('https://wa.me/$normalized?text=$encoded');

  try {
    if (await canLaunchUrl(native)) {
      final ok = await launchUrl(native, mode: LaunchMode.externalApplication);
      if (ok) return;
    }
    if (await canLaunchUrl(web)) {
      final ok = await launchUrl(web, mode: LaunchMode.externalApplication);
      if (ok) return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp is not installed on this device.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}
