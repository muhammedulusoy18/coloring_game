import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class ColorPaletteBar extends StatelessWidget {
  final List<int> palette;
  final int selectedIndex;
  final void Function(int index) onColorSelected;
  final Set<int> completedColors; // colors where all cells are filled

  const ColorPaletteBar({
    super.key,
    required this.palette,
    required this.selectedIndex,
    required this.onColorSelected,
    this.completedColors = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (palette.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderDark),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              const Text(
                'Renk Paleti',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Completed count badge
              if (completedColors.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 11, color: AppTheme.accentGreen),
                      const SizedBox(width: 3),
                      Text(
                        '${completedColors.length}/${palette.length}',
                        style: TextStyle(
                          color: AppTheme.accentGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else if (selectedIndex >= 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Color(palette[selectedIndex]).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Color(palette[selectedIndex]).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'Seçili: ${selectedIndex + 1}',
                    style: TextStyle(
                      color: Color(palette[selectedIndex]),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 58,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: palette.length,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final color = Color(palette[index]);
                final isSelected = index == selectedIndex;
                final isCompleted = completedColors.contains(index);
                final luminance = color.computeLuminance();
                final textColor = luminance > 0.5 ? Colors.black87 : Colors.white;

                return GestureDetector(
                  onTap: () => isCompleted ? null : onColorSelected(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: 54,
                    height: 54,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isCompleted ? color.withValues(alpha: 0.5) : color,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isCompleted
                            ? AppTheme.accentGreen
                            : isSelected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.1),
                        width: isCompleted ? 2.5 : isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected && !isCompleted
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.6),
                                blurRadius: 16,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : isCompleted
                              ? [
                                  BoxShadow(
                                    color: AppTheme.accentGreen.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                    ),
                    child: AnimatedScale(
                      scale: isSelected && !isCompleted ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isCompleted)
                            // Completed: show checkmark
                            Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 26,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                ),
                              ],
                            )
                          else
                            Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
