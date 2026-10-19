import 'package:flutter/material.dart';

import '../omr/bangla.dart';
import '../theme.dart';

/// Card shell for one question: an accent strip on the left (its status
/// colour), a "প্রশ্ন N" pill with an optional tag, the question text, and
/// the options below.
class QuestionCard extends StatelessWidget {
  final int number;
  final String title;
  final Color accent;
  final Widget? tag;
  final bool highlighted;
  final Widget child;

  const QuestionCard({
    super.key,
    required this.number,
    required this.title,
    required this.accent,
    required this.child,
    this.tag,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: highlighted ? AppColors.warning : Colors.transparent,
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'প্রশ্ন ${toBanglaDigits('$number')}',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      ?tag,
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title.isEmpty ? 'প্রশ্ন ${toBanglaDigits('$number')}' : title,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 5,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded status label, e.g. "OMR", "বাকি", "সঠিক".
class StatusTag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const StatusTag(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
