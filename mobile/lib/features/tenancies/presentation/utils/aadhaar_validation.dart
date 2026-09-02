/// Strict Aadhaar format: 12 digits, first digit 2–9.
final RegExp aadhaarNumberPattern = RegExp(r'^[2-9][0-9]{11}$');

const String aadhaarValidationMessage =
    'Please enter a valid 12-digit ID number';

String? validateAadhaarNumber(String? value, {bool required = false}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return required ? aadhaarValidationMessage : null;
  }
  if (!aadhaarNumberPattern.hasMatch(trimmed)) {
    return aadhaarValidationMessage;
  }
  return null;
}
