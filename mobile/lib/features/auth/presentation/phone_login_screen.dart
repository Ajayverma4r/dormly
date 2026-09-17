// features/auth/presentation/phone_login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_repository.dart';

/// Brand blue for login CTA / cursor — not the app-wide Payments purple.
const _dormlyBlue = Color(0xFF0127C6);

class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  late final TextEditingController _controller;
  late final FocusNode _phoneFocus;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _phoneFocus = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = '+91${_controller.text.trim()}';
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).requestOtp(phone);
      if (mounted) context.push('/otp', extra: phone);
    } catch (e) {
      setState(() => _error = 'Could not send OTP: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = !_loading && _controller.text.trim().length >= 10;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1 — background only (not interactive).
        Positioned.fill(
          child: Image.asset(
            'assets/images/login_bg.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        // Layer 2 — MUST be last so it receives all taps / focus.
        Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          // Explicitly no drawers / FABs that could paint a menu control.
          drawer: null,
          endDrawer: null,
          floatingActionButton: null,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Dormly',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'One Platform.\nEvery Property.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 56),
                  const Text(
                    'Continue with your phone number',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        primary: _dormlyBlue,
                      ),
                      textSelectionTheme: TextSelectionThemeData(
                        cursorColor: _dormlyBlue,
                        selectionHandleColor: _dormlyBlue,
                        selectionColor: _dormlyBlue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: TextFormField(
                      controller: _controller,
                      focusNode: _phoneFocus,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      maxLength: 10,
                      cursorColor: _dormlyBlue,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => setState(() {}),
                      onFieldSubmitted: (_) {
                        if (canContinue) _sendOtp();
                      },
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter phone number',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            '🇮🇳 +91',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 88,
                          minHeight: 48,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Material (not ElevatedButton) so app purple theme cannot win.
                  Material(
                    color: canContinue
                        ? _dormlyBlue
                        : _dormlyBlue.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: canContinue ? _sendOtp : null,
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 54,
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontSize: 17,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'By continuing you agree to our\nTerms of Service & Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
