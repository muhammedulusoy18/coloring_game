class CellUpdate {
  final int x;
  final int y;
  final int colorIndex;
  final String playerId;
  final int timestamp;

  CellUpdate({
    required this.x,
    required this.y,
    required this.colorIndex,
    required this.playerId,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'c': colorIndex,
    'p': playerId,
    't': timestamp,
  };

  factory CellUpdate.fromJson(Map<dynamic, dynamic> json) {
    return CellUpdate(
      x: json['x'] ?? 0,
      y: json['y'] ?? 0,
      colorIndex: json['c'] ?? 0,
      playerId: json['p'] ?? '',
      timestamp: json['t'] ?? 0,
    );
  }

  String get cellKey => '${x}_$y';
}
