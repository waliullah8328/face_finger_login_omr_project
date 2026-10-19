import 'package:flutter/material.dart';

import '../theme.dart';

enum OptionState {
  idle,
  selected,

  /// Given and correct.
  correct,

  /// Given but wrong.
  wrong,

  /// The correct option, which was not given.
  missedCorrect,
}

/// One answer option: a lettered bubble plus the option text.
class OptionTile extends StatelessWidget {
  final String label;
  final String text;
  final OptionState state;
  final VoidCallback? onTap;

  const OptionTile({
    super.key,
    required this.label,
    required this.text,
    this.state = OptionState.idle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = state == OptionState.selected;
    final (Color border, Color background, Color bubble, Color bubbleText) =
        switch (state) {
      OptionState.idle => (
          AppColors.border,
          Colors.white,
          AppColors.primary.withValues(alpha: 0.07),
          AppColors.primary,
        ),
      // Only the bubble is filled (with the brand gradient below), like a
      // mark on a paper OMR sheet; the option itself stays plain.
      OptionState.selected => (
          AppColors.primary,
          Colors.white,
          AppColors.primary,
          Colors.white,
        ),
      OptionState.correct => (
          AppColors.success,
          AppColors.success.withValues(alpha: 0.08),
          AppColors.success,
          Colors.white,
        ),
      OptionState.wrong => (
          AppColors.danger,
          AppColors.danger.withValues(alpha: 0.08),
          AppColors.danger,
          Colors.white,
        ),
      OptionState.missedCorrect => (
          AppColors.success,
          Colors.white,
          AppColors.success.withValues(alpha: 0.15),
          AppColors.success,
        ),
    };
    final icon = switch (state) {
      OptionState.correct => Icons.check_rounded,
      OptionState.wrong => Icons.close_rounded,
      _ => null,
    };

    final textColor = text.isEmpty ? AppColors.muted : AppColors.text;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: border,
          width: state == OptionState.idle ? 1 : 1.6,
        ),
      ),
      child: Padding(
        // The bubble's own tap padding (6) makes up the rest of the inset.
        padding: const EdgeInsets.fromLTRB(4, 5, 10, 5),
        child: Row(
          children: [
            // Only the bubble is tappable, as on a paper OMR sheet; the
            // padding around it keeps the touch target finger-sized.
            Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? null : bubble,
                    gradient: selected ? AppColors.headerGradient : null,
                    shape: BoxShape.circle,
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: icon != null
                      ? Icon(icon, size: 18, color: bubbleText)
                      : Text(
                          label,
                          style: TextStyle(
                            color: bubbleText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text.isEmpty ? 'অপশন $label' : text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: state == OptionState.idle
                      ? FontWeight.w500
                      : FontWeight.w700,
                ),
              ),
            ),
            if (state == OptionState.missedCorrect)
              const Icon(Icons.check_circle_outline,
                  size: 18, color: AppColors.success),
          ],
        ),
      ),
    );
  }
}

/// Lays options out two per row when they are short, one per row otherwise.
class OptionGrid extends StatelessWidget {
  final List<String> texts;
  final Widget Function(int index) builder;

  const OptionGrid({super.key, required this.texts, required this.builder});

  @override
  Widget build(BuildContext context) {
    final twoColumns = texts.every((t) => t.trim().length <= 18);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = twoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < texts.length; i++)
              SizedBox(width: width, child: builder(i)),
          ],
        );
      },
    );
  }
}
