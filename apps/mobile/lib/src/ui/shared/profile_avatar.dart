import 'package:flutter/material.dart';

const _namedProfiles = <String, ContactProfile>{
  '김민지': ContactProfile('김민지', 'assets/avatars/contact_mina.png'),
  '김하은': ContactProfile('김하은', 'assets/avatars/contact_haeun.png'),
  '이지훈': ContactProfile('이지훈', 'assets/avatars/contact_jihoon.png'),
  '정유나': ContactProfile('정유나', 'assets/avatars/contact_yuna.png'),
  '최아린': ContactProfile('최아린', 'assets/avatars/contact_arin.png'),
  '박서준': ContactProfile('박서준', 'assets/avatars/contact_seojun.png'),
  '한다은': ContactProfile('한다은', 'assets/avatars/contact_daeun.png'),
  '한지수': ContactProfile('한지수', 'assets/avatars/contact_jisoo.png'),
  'minji': ContactProfile('김민지', 'assets/avatars/contact_mina.png'),
  'jihoon song': ContactProfile('이지훈', 'assets/avatars/contact_jihoon.png'),
  'ricky padilla': ContactProfile('정유나', 'assets/avatars/contact_yuna.png'),
  'alex walker': ContactProfile('최아린', 'assets/avatars/contact_arin.png'),
};

const _syntheticProfiles = [
  ContactProfile('김하은', 'assets/avatars/contact_haeun.png'),
  ContactProfile('이지훈', 'assets/avatars/contact_jihoon.png'),
  ContactProfile('정유나', 'assets/avatars/contact_yuna.png'),
  ContactProfile('최아린', 'assets/avatars/contact_arin.png'),
  ContactProfile('박서준', 'assets/avatars/contact_seojun.png'),
  ContactProfile('한다은', 'assets/avatars/contact_daeun.png'),
  ContactProfile('한지수', 'assets/avatars/contact_jisoo.png'),
  ContactProfile('김민지', 'assets/avatars/contact_mina.png'),
];

class ContactProfile {
  const ContactProfile(this.displayName, this.avatarAsset);

  final String displayName;
  final String? avatarAsset;
}

ContactProfile contactProfileForLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return const ContactProfile('친구', null);
  }

  final known =
      _namedProfiles[trimmed] ?? _namedProfiles[trimmed.toLowerCase()];
  if (known != null) {
    return known;
  }

  if (_looksLikeTestIdentifier(trimmed)) {
    return _syntheticProfileFor(trimmed);
  }

  return ContactProfile(trimmed, null);
}

bool _looksLikeTestIdentifier(String value) {
  final lower = value.toLowerCase();
  return lower.startsWith('@') ||
      lower.startsWith('user') ||
      lower.startsWith('friend-') ||
      lower.startsWith('smoke_') ||
      lower.startsWith('e2e_') ||
      lower.contains('_e2e_') ||
      lower.contains('e2e_') ||
      RegExp(r'^\d{4,}$').hasMatch(lower);
}

ContactProfile _syntheticProfileFor(String seed) {
  final hash = seed.codeUnits.fold<int>(
    0,
    (value, unit) => ((value * 31) + unit) & 0x7fffffff,
  );
  return _syntheticProfiles[hash % _syntheticProfiles.length];
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.label,
    required this.size,
    this.assetPath,
    this.icon,
    super.key,
  });

  final String label;
  final double size;
  final String? assetPath;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final asset = assetPath;
    final initial = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();
    final colors = _avatarColors(label);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.045),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Container(
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        child: asset != null
            ? Image.asset(
                asset,
                width: size * 0.92,
                height: size * 0.92,
                fit: BoxFit.cover,
                semanticLabel: label,
              )
            : Container(
                width: size * 0.83,
                height: size * 0.83,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.last.withValues(alpha: 0.88),
                      colors.first.withValues(alpha: 0.88),
                    ],
                  ),
                ),
                child: icon == null
                    ? Text(
                        initial,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: size * 0.36,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: size * 0.44),
              ),
      ),
    );
  }
}

List<Color> _avatarColors(String seed) {
  final palettes = [
    const [Color(0xFF35C987), Color(0xFF00A86B)],
    const [Color(0xFF40D6A0), Color(0xFF009E74)],
    const [Color(0xFF5BDB91), Color(0xFF119B4F)],
    const [Color(0xFF48D39A), Color(0xFF008F6E)],
    const [Color(0xFF2ECF82), Color(0xFF0D9C87)],
  ];
  final hash = seed.codeUnits.fold<int>(0, (value, unit) => value + unit);
  return palettes[hash % palettes.length];
}
