import 'dart:math';
import 'package:flutter/material.dart';

class ConfettiBurst extends StatefulWidget {
  final Color primaryColor;
  final bool active;

  const ConfettiBurst({
    super.key,
    required this.primaryColor,
    required this.active,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<_Particle> _particles;
  final Random _rnd = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _ctrl.addListener(() => setState(() {}));
    _spawnParticles();
  }

  @override
  void didUpdateWidget(ConfettiBurst old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _spawnParticles();
      _ctrl.forward(from: 0);
    }
  }

  void _spawnParticles() {
    final colors = [
      widget.primaryColor,
      Colors.white,
      Colors.yellowAccent,
      Colors.pinkAccent,
      Colors.lightBlueAccent,
      Colors.orangeAccent,
    ];
    _particles = List.generate(60, (i) {
      final angle = _rnd.nextDouble() * 2 * pi;
      final speed = 180 + _rnd.nextDouble() * 280;
      return _Particle(
        color: colors[_rnd.nextInt(colors.length)],
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 120,
        size: 5 + _rnd.nextDouble() * 8,
        rotation: _rnd.nextDouble() * 2 * pi,
        rotationSpeed: (_rnd.nextDouble() - 0.5) * 8,
        isCircle: _rnd.nextBool(),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && _ctrl.value == 0) return const SizedBox.shrink();

    final t = _ctrl.value;
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height * 0.4;

    return IgnorePointer(
      child: CustomPaint(
        size: Size(size.width, size.height),
        painter: _ConfettiPainter(
          particles: _particles,
          t: t,
          cx: cx,
          cy: cy,
        ),
      ),
    );
  }
}

class _Particle {
  final Color color;
  final double vx, vy, size, rotation, rotationSpeed;
  final bool isCircle;
  _Particle({
    required this.color,
    required this.vx,
    required this.vy,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
    required this.isCircle,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final double cx, cy;

  const _ConfettiPainter({
    required this.particles,
    required this.t,
    required this.cx,
    required this.cy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    const gravity = 500.0;

    for (final p in particles) {
      final x = cx + p.vx * t;
      final y = cy + p.vy * t + 0.5 * gravity * t * t;
      final opacity = (1.0 - t * 0.85).clamp(0.0, 1.0);
      final rot = p.rotation + p.rotationSpeed * t;
      final s = p.size * (1.0 - t * 0.3);

      paint.color = p.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, s / 2, paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.5), paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.t != t;
}
