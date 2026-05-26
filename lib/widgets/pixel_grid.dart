import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class PixelGrid extends StatefulWidget {
  final int width;
  final int height;
  final Map<String, int> gridData;
  final Map<String, int> cellStates;
  final List<int> palette;
  final int selectedColorIndex;
  final void Function(int x, int y) onCellTap;

  const PixelGrid({
    super.key,
    required this.width,
    required this.height,
    required this.gridData,
    required this.cellStates,
    required this.palette,
    required this.selectedColorIndex,
    required this.onCellTap,
  });

  static double getCellSize(BuildContext context, int gridW, int gridH) {
    final sw = MediaQuery.of(context).size.width - 32;
    final sh = MediaQuery.of(context).size.height * 0.55;
    final cw = sw / gridW;
    final ch = sh / gridH;
    return (cw < ch ? cw : ch).clamp(4.0, 40.0);
  }

  @override
  State<PixelGrid> createState() => _PixelGridState();
}

class _PixelGridState extends State<PixelGrid> {
  int _activePointers = 0;

  void _handlePos(Offset pos, double cellSize) {
    if (_activePointers > 1) return; // ignore if zooming/panning
    final x = (pos.dx / cellSize).floor();
    final y = (pos.dy / cellSize).floor();
    if (x >= 0 && x < widget.width && y >= 0 && y < widget.height) {
      widget.onCellTap(x, y);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.width == 0 || widget.height == 0) {
      return const Center(
        child: Text('Grid yükleniyor...', style: TextStyle(color: Color(0xFF8B949E))),
      );
    }
    final cellSize = PixelGrid.getCellSize(context, widget.width, widget.height);

    // Listener captures raw pointer events without blocking InteractiveViewer's gestures
    return Listener(
      onPointerDown: (e) {
        setState(() => _activePointers++);
        if (_activePointers == 1) _handlePos(e.localPosition, cellSize);
      },
      onPointerMove: (e) {
        if (_activePointers == 1) _handlePos(e.localPosition, cellSize);
      },
      onPointerUp: (e) {
        setState(() => _activePointers = (_activePointers - 1).clamp(0, 99));
      },
      onPointerCancel: (e) {
        setState(() => _activePointers = (_activePointers - 1).clamp(0, 99));
      },
      child: CustomPaint(
        size: Size(cellSize * widget.width, cellSize * widget.height),
        painter: _PixelGridPainter(
          gridWidth: widget.width,
          gridHeight: widget.height,
          cellSize: cellSize,
          gridData: widget.gridData,
          cellStates: widget.cellStates,
          palette: widget.palette,
          selectedColorIndex: widget.selectedColorIndex,
          paintVersion: widget.cellStates.length,
        ),
      ),
    );
  }
}


class _PixelGridPainter extends CustomPainter {
  final int gridWidth;
  final int gridHeight;
  final double cellSize;
  final Map<String, int> gridData;
  final Map<String, int> cellStates;
  final List<int> palette;
  final int selectedColorIndex;
  final int paintVersion;

  static const double _gap = 0.8;

  const _PixelGridPainter({
    required this.gridWidth,
    required this.gridHeight,
    required this.cellSize,
    required this.gridData,
    required this.cellStates,
    required this.palette,
    required this.selectedColorIndex,
    required this.paintVersion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final showNumbers = cellSize >= 9;
    final gap = cellSize > 8 ? _gap : 0.4;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF8A9BB0),
    );

    final cellPaint = Paint()..isAntiAlias = false;
    final shinePaint = Paint()
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke;
    final shadowPaint = Paint()
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke;
    final Map<String, TextPainter> textCache = {};

    for (int y = 0; y < gridHeight; y++) {
      for (int x = 0; x < gridWidth; x++) {
        final cellKey = '${x}_$y';
        final left = x * cellSize + gap;
        final top = y * cellSize + gap;
        final w = cellSize - gap * 2;
        final h = cellSize - gap * 2;
        final rect = Rect.fromLTWH(left, top, w, h);

        final targetColorIndex = gridData[cellKey];
        final isColored = cellStates.containsKey(cellKey);
        final isHighlighted = selectedColorIndex >= 0 && targetColorIndex == selectedColorIndex;

        if (isColored) {
          final ci = cellStates[cellKey]!;
          final color = ci < palette.length ? Color(palette[ci]) : Colors.grey;
          cellPaint.color = color;
          canvas.drawRect(rect, cellPaint);

          if (cellSize >= 7) {
            shinePaint
              ..color = Colors.white.withValues(alpha: 0.30)
              ..strokeWidth = cellSize >= 14 ? 1.8 : 1.0;
            canvas.drawLine(rect.topLeft, rect.topRight, shinePaint);
            canvas.drawLine(rect.topLeft, rect.bottomLeft, shinePaint);

            shadowPaint
              ..color = Colors.black.withValues(alpha: 0.40)
              ..strokeWidth = cellSize >= 14 ? 1.4 : 0.8;
            canvas.drawLine(rect.bottomLeft, rect.bottomRight, shadowPaint);
            canvas.drawLine(rect.topRight, rect.bottomRight, shadowPaint);
          }
        } else {
          cellPaint.color = isHighlighted
              ? const Color(0xFFD8D4CC)
              : const Color(0xFFF5F2EC);
          canvas.drawRect(rect, cellPaint);

          if (showNumbers && targetColorIndex != null) {
            final numStr = '${targetColorIndex + 1}';
            final cacheKey = '${numStr}_${isHighlighted}_$selectedColorIndex';
            if (!textCache.containsKey(cacheKey)) {
              final fontSize = (cellSize * 0.44).clamp(6.0, 16.0);
              final tp = TextPainter(
                text: TextSpan(
                  text: numStr,
                  style: TextStyle(
                    color: const Color(0xFF3D4451),
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                textAlign: TextAlign.center,
                textDirection: ui.TextDirection.ltr,
              );
              tp.layout(maxWidth: cellSize);
              textCache[cacheKey] = tp;
            }
            final tp = textCache[cacheKey]!;
            tp.paint(
              canvas,
              Offset(
                rect.center.dx - tp.width / 2,
                rect.center.dy - tp.height / 2,
              ),
            );
          }

          if (isHighlighted) {
            final bp = Paint()
              ..color = const Color(0xFF888888)
              ..style = PaintingStyle.stroke
              ..strokeWidth = cellSize > 14 ? 1.2 : 0.7
              ..isAntiAlias = false;
            canvas.drawRect(rect, bp);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelGridPainter old) {
    return old.paintVersion != paintVersion ||
        old.selectedColorIndex != selectedColorIndex ||
        old.cellStates.length != cellStates.length;
  }
}
