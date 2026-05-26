class GameRoom {
  final String roomId;
  final String pin;
  final String hostId;
  String? guestId;
  String status; // 'waiting', 'processing', 'playing', 'completed'
  int gridWidth;
  int gridHeight;
  List<int> palette; // list of color values
  Map<String, int> gridData; // 'x_y' -> paletteIndex
  Map<String, int?> cellStates; // 'x_y' -> paletteIndex or null (uncolored)
  int totalCells;
  int coloredCells;

  GameRoom({
    required this.roomId,
    required this.pin,
    required this.hostId,
    this.guestId,
    this.status = 'waiting',
    this.gridWidth = 0,
    this.gridHeight = 0,
    this.palette = const [],
    this.gridData = const {},
    this.cellStates = const {},
    this.totalCells = 0,
    this.coloredCells = 0,
  });

  // toJson and fromJson methods for Firebase
  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'pin': pin,
    'hostId': hostId,
    'guestId': guestId,
    'status': status,
    'gridWidth': gridWidth,
    'gridHeight': gridHeight,
    'palette': palette,
    'totalCells': totalCells,
    'coloredCells': coloredCells,
  };

  factory GameRoom.fromJson(Map<dynamic, dynamic> json) {
    return GameRoom(
      roomId: json['roomId'] ?? '',
      pin: json['pin'] ?? '',
      hostId: json['hostId'] ?? '',
      guestId: json['guestId'],
      status: json['status'] ?? 'waiting',
      gridWidth: (json['gridWidth'] as num?)?.toInt() ?? 0,
      gridHeight: (json['gridHeight'] as num?)?.toInt() ?? 0,
      palette: (json['palette'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
      totalCells: (json['totalCells'] as num?)?.toInt() ?? 0,
      coloredCells: (json['coloredCells'] as num?)?.toInt() ?? 0,
    );
  }
}
