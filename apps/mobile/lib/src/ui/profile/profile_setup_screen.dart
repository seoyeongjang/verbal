import 'package:flutter/material.dart';

import '../../models/messenger_models.dart';
import '../../services/handle_policy.dart';
import '../../services/messenger_backend.dart';

const _kLogoBlack = Color(0xFF111111);
const _kSurface = Color(0xFF1C211F);
const _kBorder = Color(0xFF29332F);
const _kLightInk = Color(0xFFF7F7F8);
const _kLightMuted = Color(0xFFB7BBC3);
const _kAccent = Color(0xFF00A86B);

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _handleController;
  String? _error;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.displayName);
    _handleController = TextEditingController(text: widget.user.handle);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handleError = _handleController.text.trim().isEmpty
        ? null
        : validateHandle(_handleController.text);
    final canSave =
        !_saving &&
        _nameController.text.trim().isNotEmpty &&
        validateHandle(_handleController.text) == null;
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(inputDecorationTheme: profileSetupInputTheme()),
      child: Scaffold(
        backgroundColor: _kLogoBlack,
        appBar: AppBar(
          title: const Text('프로필 설정'),
          backgroundColor: _kLogoBlack,
          foregroundColor: _kLightInk,
          surfaceTintColor: _kLogoBlack,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF35C987), Color(0xFF00A86B)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '대화에서 보일 이름을 정해 주세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _kLightInk,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '아이디로 친구가 대화를 시작할 수 있습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _kLightMuted),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        color: _kLightInk,
                        fontWeight: FontWeight.w800,
                      ),
                      cursorColor: _kAccent,
                      decoration: const InputDecoration(
                        labelText: '이름',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _handleController,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        color: _kLightInk,
                        fontWeight: FontWeight.w800,
                      ),
                      cursorColor: _kAccent,
                      decoration: InputDecoration(
                        labelText: '아이디',
                        prefixText: '@',
                        prefixStyle: const TextStyle(
                          color: _kLightMuted,
                          fontWeight: FontWeight.w800,
                        ),
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                        helperText: '한글, 영어, 일본어, 중국어, 숫자, _ 3~30자',
                        helperStyle: const TextStyle(color: _kLightMuted),
                        errorText: handleError,
                      ),
                      onSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: canSave ? _save : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: const Text('시작하기'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
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
      ),
    );
  }

  Future<void> _save() async {
    final displayName = _nameController.text.trim();
    final handleError = validateHandle(_handleController.text);
    if (displayName.isEmpty || handleError != null) {
      setState(() {
        _error = displayName.isEmpty ? '이름을 입력해 주세요.' : handleError;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await BackendScope.of(context).saveProfile(
        displayName: _nameController.text,
        handle: _handleController.text,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

InputDecorationTheme profileSetupInputTheme() {
  return const InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
      borderSide: BorderSide.none,
    ),
    filled: true,
    fillColor: _kSurface,
    labelStyle: TextStyle(color: _kLightMuted, fontWeight: FontWeight.w700),
    floatingLabelStyle: TextStyle(color: _kAccent, fontWeight: FontWeight.w900),
    prefixIconColor: _kLightInk,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
      borderSide: BorderSide(color: _kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
      borderSide: BorderSide(color: _kAccent, width: 1.5),
    ),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
  );
}
