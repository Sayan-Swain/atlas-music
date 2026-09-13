import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_background.dart';

/// First-run input. Content only — parent provides [LiquidBackground].
/// Redesigned: glass card with welcome prompt, no ugly underline input,
/// premium gradient continue button, clean typographic hierarchy.
class OnboardingContent extends StatefulWidget {
  final ValueChanged<String> onContinue;
  const OnboardingContent({super.key, required this.onContinue});

  @override
  State<OnboardingContent> createState() => _OnboardingContentState();
}

class _OnboardingContentState extends State<OnboardingContent>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _in;
  late final Animation<double> _fade;
  late final Animation<Offset> _rise;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
      vsync: this,
      duration: AppMotion.entrance,
    )..forward();
    _fade = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    _rise = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _in, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _in.dispose();
    super.dispose();
  }

  void _go() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    _focus.unfocus();
    widget.onContinue(v);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _rise,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: GlassPanel(
              radius: 28,
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 36),
              opacity: 0.09,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Decorative orb.
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Colors.white, Color(0xFFD4D4D8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white24,
                          blurRadius: 28,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.music_note_rounded,
                        color: AppColors.charcoal, size: 32),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    "What's your name?",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: AppColors.ink,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your music. Your atmosphere.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkSoft,
                          fontSize: 13,
                        ),
                  ),
                  const SizedBox(height: 28),
                  // Glass input — no underline.
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.mist,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.line,
                      ),
                    ),
                    child: TextField(
                      key: const ValueKey('name_input'),
                      controller: _ctrl,
                      focusNode: _focus,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter your name',
                        hintStyle: const TextStyle(
                          color: AppColors.mute,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        prefixIcon: const Icon(
                          Icons.person_outline_rounded,
                          size: 20,
                          color: AppColors.mute,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                      onSubmitted: (_) => _go(),
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Gradient continue button.
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Colors.white, Color(0xFFE4E4E7)],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.white24,
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        key: const ValueKey('name_continue'),
                        onPressed: _go,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.charcoal,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
