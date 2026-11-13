import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatsCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const StatsCard({
    super.key,
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBorder = AppTheme.borderColor(isDark);
    final ink = AppTheme.inkColor(isDark);
    final muted = AppTheme.mutedColor(isDark);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? color.withOpacity(0.14) : color.withOpacity(0.08))
              : AppTheme.cardColor(isDark),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : baseBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withOpacity(0.18)
                        : AppTheme.subtleBg(isDark),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? color : muted,
                    size: 14,
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? color : Colors.transparent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.05,
                color: isSelected ? color : ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: -0.1,
                color: isSelected ? ink : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
