import 'package:flutter/material.dart';

enum PowerupType { wand, hint, bomb, fill }

class PowerupsBar extends StatelessWidget {
  final int wandCharges;
  final int hintCharges;
  final int bombCharges;
  final int fillCharges;
  final void Function(PowerupType) onTap;

  const PowerupsBar({
    super.key,
    required this.wandCharges,
    required this.hintCharges,
    required this.bombCharges,
    required this.fillCharges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _PowerupButton(
            emoji: '✨',
            label: 'Değnek',
            charges: wandCharges,
            color: const Color(0xFFB388FF),
            onTap: () => onTap(PowerupType.wand),
          ),
          _PowerupButton(
            emoji: '💡',
            label: 'İpucu',
            charges: hintCharges,
            color: const Color(0xFFFFD54F),
            onTap: () => onTap(PowerupType.hint),
          ),
          _PowerupButton(
            emoji: '💣',
            label: 'Bomba',
            charges: bombCharges,
            color: const Color(0xFFFF7043),
            onTap: () => onTap(PowerupType.bomb),
          ),
          _PowerupButton(
            emoji: '🎨',
            label: 'Doldur',
            charges: fillCharges,
            color: const Color(0xFF4DD0E1),
            onTap: () => onTap(PowerupType.fill),
          ),
        ],
      ),
    );
  }
}

class _PowerupButton extends StatefulWidget {
  final String emoji;
  final String label;
  final int charges;
  final Color color;
  final VoidCallback onTap;

  const _PowerupButton({
    required this.emoji,
    required this.label,
    required this.charges,
    required this.color,
    required this.onTap,
  });

  @override
  State<_PowerupButton> createState() => _PowerupButtonState();
}

class _PowerupButtonState extends State<_PowerupButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 80),
      lowerBound: 0.92,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _scaleController;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _scaleController.reverse().then((_) => _scaleController.forward());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasCharges = widget.charges > 0;

    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Button body
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: hasCharges
                        ? widget.color.withValues(alpha: 0.18)
                        : const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: hasCharges
                          ? widget.color.withValues(alpha: 0.6)
                          : const Color(0xFF30363D),
                      width: 1.5,
                    ),
                    boxShadow: hasCharges
                        ? [
                            BoxShadow(
                              color: widget.color.withValues(alpha: 0.25),
                              blurRadius: 8,
                              spreadRadius: 0,
                            )
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      widget.emoji,
                      style: TextStyle(
                        fontSize: 26,
                        color: hasCharges ? null : Colors.white24,
                      ),
                    ),
                  ),
                ),

                // Charge badge
                Positioned(
                  top: -6,
                  right: -6,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: child,
                    ),
                    child: hasCharges
                        ? Container(
                            key: ValueKey(widget.charges),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.color,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.color.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Text(
                              '×${widget.charges}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          )
                        : Container(
                            key: const ValueKey(0),
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF30363D),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 8,
                              color: Colors.white54,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: hasCharges ? widget.color : Colors.white30,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
