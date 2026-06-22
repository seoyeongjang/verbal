import 'package:flutter/material.dart';

import '../../services/messenger_backend.dart';

const _kAccent = Color(0xFF00A86B);
const _kLogoBlack = Color(0xFF111111);
const _kInk = Color(0xFFF7F7F8);
const _kMuted = Color(0xFFB7BBC3);
const _kFieldFill = Color(0xFF1C211F);
const _kFieldBorder = Color(0xFF29332F);

const _kTermsVersion = 'terms-2026-06-18';
const _kPrivacyVersion = 'privacy-2026-06-18';
const _kCommunityPolicyVersion = 'community-2026-06-18';

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.isDemoMode, super.key});

  final bool isDemoMode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final _smsController = TextEditingController();
  String? _verificationId;
  String? _error;
  var _loading = false;
  var _acceptedTerms = false;
  var _acceptedPrivacy = false;
  var _acceptedCommunityPolicy = false;

  bool get _hasRequiredConsent =>
      _acceptedTerms && _acceptedPrivacy && _acceptedCommunityPolicy;

  @override
  void dispose() {
    _phoneController.dispose();
    _smsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    return Scaffold(
      backgroundColor: _kLogoBlack,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandMark(),
                  const SizedBox(height: 22),
                  const Text(
                    'Verbal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 30,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '말하면 바로 메시지가 됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _kMuted, fontSize: 15),
                  ),
                  const SizedBox(height: 28),
                  _PolicyConsentPanel(
                    acceptedTerms: _acceptedTerms,
                    acceptedPrivacy: _acceptedPrivacy,
                    acceptedCommunityPolicy: _acceptedCommunityPolicy,
                    onTermsChanged: (value) =>
                        setState(() => _acceptedTerms = value),
                    onPrivacyChanged: (value) =>
                        setState(() => _acceptedPrivacy = value),
                    onCommunityPolicyChanged: (value) =>
                        setState(() => _acceptedCommunityPolicy = value),
                  ),
                  const SizedBox(height: 20),
                  if (widget.isDemoMode)
                    _DemoLogin(
                      loading: _loading,
                      canSubmit: _hasRequiredConsent,
                      onStart: () => _run(() async {
                        await backend.signInDemo();
                        await _saveRequiredPolicyConsent(backend);
                      }),
                    )
                  else
                    _PhoneLogin(
                      loading: _loading,
                      canSubmit: _hasRequiredConsent,
                      phoneController: _phoneController,
                      smsController: _smsController,
                      verificationId: _verificationId,
                      onRequestCode: () => _run(() async {
                        final id = await backend.startPhoneVerification(
                          _phoneController.text.trim(),
                        );
                        if (id == '__auto_verified__') {
                          await _saveRequiredPolicyConsent(backend);
                          return;
                        }
                        if (mounted) {
                          setState(() => _verificationId = id);
                        }
                      }),
                      onVerify: () => _run(() async {
                        await backend.verifySmsCode(
                          verificationId: _verificationId!,
                          smsCode: _smsController.text.trim(),
                        );
                        await _saveRequiredPolicyConsent(backend);
                      }),
                    ),
                  if (_loading) ...[
                    const SizedBox(height: 18),
                    const Center(
                      child: CircularProgressIndicator(color: _kAccent),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveRequiredPolicyConsent(MessengerBackend backend) {
    return backend.savePolicyConsent(
      termsVersion: _kTermsVersion,
      privacyVersion: _kPrivacyVersion,
      communityPolicyVersion: _kCommunityPolicyVersion,
    );
  }

  Future<void> _run(Future<void> Function() task) async {
    if (!_hasRequiredConsent) {
      setState(() {
        _error = '서비스 이용을 위해 필수 정책에 동의해 주세요.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF35C987), _kAccent],
          ),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 34),
      ),
    );
  }
}

class _PolicyConsentPanel extends StatelessWidget {
  const _PolicyConsentPanel({
    required this.acceptedTerms,
    required this.acceptedPrivacy,
    required this.acceptedCommunityPolicy,
    required this.onTermsChanged,
    required this.onPrivacyChanged,
    required this.onCommunityPolicyChanged,
  });

  final bool acceptedTerms;
  final bool acceptedPrivacy;
  final bool acceptedCommunityPolicy;
  final ValueChanged<bool> onTermsChanged;
  final ValueChanged<bool> onPrivacyChanged;
  final ValueChanged<bool> onCommunityPolicyChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: _kFieldFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              '필수 동의',
              style: TextStyle(
                color: _kInk,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _ConsentTile(
            key: const ValueKey('terms-consent-checkbox'),
            value: acceptedTerms,
            label: '이용약관에 동의합니다.',
            onChanged: onTermsChanged,
          ),
          _ConsentTile(
            key: const ValueKey('privacy-consent-checkbox'),
            value: acceptedPrivacy,
            label: '개인정보 처리방침에 동의합니다.',
            onChanged: onPrivacyChanged,
          ),
          _ConsentTile(
            key: const ValueKey('community-consent-checkbox'),
            value: acceptedCommunityPolicy,
            label: '커뮤니티 운영정책에 동의합니다.',
            onChanged: onCommunityPolicyChanged,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: Text(
              '메시지, 음성 transcript, 파일 등 사용자 생성 콘텐츠의 안전한 이용과 신고 처리를 위한 필수 동의입니다.',
              style: TextStyle(color: _kMuted, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (next) => onChanged(next ?? false),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: _kAccent,
      checkColor: Colors.white,
      side: const BorderSide(color: _kMuted, width: 1.4),
      title: Text(
        label,
        style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _DemoLogin extends StatelessWidget {
  const _DemoLogin({
    required this.loading,
    required this.canSubmit,
    required this.onStart,
  });

  final bool loading;
  final bool canSubmit;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kFieldFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kFieldBorder),
          ),
          child: const Text(
            '데모 모드에서 화면과 음성 전송 흐름을 먼저 확인할 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kInk),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: loading || !canSubmit ? null : onStart,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('데모로 시작'),
        ),
      ],
    );
  }
}

class _PhoneLogin extends StatelessWidget {
  const _PhoneLogin({
    required this.loading,
    required this.canSubmit,
    required this.phoneController,
    required this.smsController,
    required this.verificationId,
    required this.onRequestCode,
    required this.onVerify,
  });

  final bool loading;
  final bool canSubmit;
  final TextEditingController phoneController;
  final TextEditingController smsController;
  final String? verificationId;
  final VoidCallback onRequestCode;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800),
          cursorColor: _kAccent,
          decoration: _authInputDecoration(
            labelText: '전화번호',
            hintText: '+821012345678',
            prefixIcon: const Icon(Icons.phone_rounded),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: loading || !canSubmit ? null : onRequestCode,
          icon: const Icon(Icons.sms_outlined),
          label: const Text('인증번호 받기'),
        ),
        if (verificationId != null) ...[
          const SizedBox(height: 18),
          TextField(
            controller: smsController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: _kInk, fontWeight: FontWeight.w800),
            cursorColor: _kAccent,
            decoration: _authInputDecoration(
              labelText: '인증번호',
              prefixIcon: const Icon(Icons.password_rounded),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading || !canSubmit ? null : onVerify,
            icon: const Icon(Icons.login_rounded),
            label: const Text('로그인'),
          ),
        ],
      ],
    );
  }
}

InputDecoration _authInputDecoration({
  required String labelText,
  String? hintText,
  required Widget prefixIcon,
}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: _kFieldFill,
    labelStyle: const TextStyle(color: _kMuted, fontWeight: FontWeight.w700),
    floatingLabelStyle: const TextStyle(
      color: _kAccent,
      fontWeight: FontWeight.w900,
    ),
    hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.52)),
    prefixIconColor: _kInk,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: _kFieldBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: _kAccent, width: 1.5),
    ),
  );
}
