import 'dart:typed_data';
import 'package:image/image.dart' as img;

enum GameDifficulty {
  easy(20, 14, 'Kolay', '~280 bölge'),
  medium(35, 18, 'Orta', '~770 bölge'),
  hard(55, 22, 'Zor', '~1900 bölge'),
  expert(75, 28, 'Uzman', '~3500 bölge');

  final int gridSize;
  final int maxColors;
  final String label;
  final String description;
  const GameDifficulty(this.gridSize, this.maxColors, this.label, this.description);
}

class ProcessedImageResult {
  final int width;
  final int height;
  final List<int> palette;
  final Map<String, int> gridData;

  ProcessedImageResult({
    required this.width,
    required this.height,
    required this.palette,
    required this.gridData,
  });

  int get totalCells => width * height;
}

class ImageProcessorService {
  static Future<ProcessedImageResult> processImage(
    Uint8List imageBytes, {
    GameDifficulty difficulty = GameDifficulty.medium,
  }) async {
    final int maxGridSize = difficulty.gridSize;
    final int maxColors = difficulty.maxColors;

    img.Image? original = img.decodeImage(imageBytes);
    if (original == null) throw Exception('Could not decode image');

    // Boost contrast & saturation before quantizing — makes colors more distinct
    img.Image enhanced = img.adjustColor(
      original,
      saturation: 1.35,
      contrast: 1.15,
    );

    // Calculate target dimensions maintaining aspect ratio
    int targetWidth, targetHeight;
    if (enhanced.width >= enhanced.height) {
      targetWidth = maxGridSize;
      targetHeight = (enhanced.height * maxGridSize / enhanced.width).round();
    } else {
      targetHeight = maxGridSize;
      targetWidth = (enhanced.width * maxGridSize / enhanced.height).round();
    }
    targetWidth = targetWidth.clamp(4, maxGridSize);
    targetHeight = targetHeight.clamp(4, maxGridSize);

    // Downscale
    img.Image resized = img.copyResize(
      enhanced,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average,
    );

    // Extract pixel colors
    List<List<int>> pixelColors = [];
    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        pixelColors.add([pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()]);
      }
    }

    // Quantize with more passes for better color separation
    List<List<int>> palette = _medianCutQuantize(pixelColors, maxColors);

    // Remove near-duplicate palette colors (merge colors within threshold)
    palette = _mergeSimilarColors(palette, threshold: 1200);

    // Map pixels to palette
    Map<String, int> gridData = {};
    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        gridData['${x}_$y'] = _findNearestColor(
          [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()],
          palette,
        );
      }
    }

    // Convert palette to Flutter color ints
    List<int> paletteValues = palette.map((rgb) {
      return (0xFF << 24) | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2];
    }).toList();

    return ProcessedImageResult(
      width: targetWidth,
      height: targetHeight,
      palette: paletteValues,
      gridData: gridData,
    );
  }

  /// Merge palette colors that are too similar
  static List<List<int>> _mergeSimilarColors(List<List<int>> palette, {required int threshold}) {
    final List<List<int>> merged = [];
    final Set<int> used = {};
    for (int i = 0; i < palette.length; i++) {
      if (used.contains(i)) continue;
      bool wasMerged = false;
      for (int j = 0; j < merged.length; j++) {
        if (_colorDistance(palette[i], merged[j]) < threshold) {
          // Average them
          merged[j] = [
            ((merged[j][0] + palette[i][0]) / 2).round(),
            ((merged[j][1] + palette[i][1]) / 2).round(),
            ((merged[j][2] + palette[i][2]) / 2).round(),
          ];
          wasMerged = true;
          break;
        }
      }
      if (!wasMerged) merged.add(palette[i]);
      used.add(i);
    }
    return merged;
  }

  static List<List<int>> _medianCutQuantize(List<List<int>> colors, int targetCount) {
    if (colors.isEmpty) return [[128, 128, 128]];
    final unique = colors.toSet().toList();
    if (unique.length <= targetCount) return unique;

    List<List<List<int>>> buckets = [List.from(colors)];

    while (buckets.length < targetCount) {
      int maxRangeIndex = 0;
      int maxRange = 0;
      int splitChannel = 0;

      for (int i = 0; i < buckets.length; i++) {
        if (buckets[i].length <= 1) continue;
        for (int ch = 0; ch < 3; ch++) {
          int minVal = 255, maxVal = 0;
          for (var c in buckets[i]) {
            if (c[ch] < minVal) minVal = c[ch];
            if (c[ch] > maxVal) maxVal = c[ch];
          }
          final range = maxVal - minVal;
          if (range > maxRange) {
            maxRange = range;
            maxRangeIndex = i;
            splitChannel = ch;
          }
        }
      }

      if (maxRange == 0) break;

      List<List<int>> bucket = buckets.removeAt(maxRangeIndex);
      bucket.sort((a, b) => a[splitChannel].compareTo(b[splitChannel]));
      final mid = bucket.length ~/ 2;
      buckets.add(bucket.sublist(0, mid));
      buckets.add(bucket.sublist(mid));
    }

    return buckets.map((bucket) {
      if (bucket.isEmpty) return [128, 128, 128];
      int rSum = 0, gSum = 0, bSum = 0;
      for (var c in bucket) {
        rSum += c[0];
        gSum += c[1];
        bSum += c[2];
      }
      return [
        (rSum / bucket.length).round(),
        (gSum / bucket.length).round(),
        (bSum / bucket.length).round(),
      ];
    }).toList();
  }

  static int _findNearestColor(List<int> color, List<List<int>> palette) {
    int bestIndex = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < palette.length; i++) {
      final dist = _colorDistance(color, palette[i]);
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  static double _colorDistance(List<int> a, List<int> b) {
    final dr = a[0] - b[0];
    final dg = a[1] - b[1];
    final db = a[2] - b[2];
    return (dr * dr + dg * dg + db * db).toDouble();
  }
}
