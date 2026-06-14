class NumberRecord {
  NumberRecord({
    required this.redBalls,
    required this.blueBall,
    required this.sourceFileName,
  });

  final List<int> redBalls;
  final int blueBall;
  final String sourceFileName;

  String get display {
    final reds = redBalls.map(_pad).join('.');
    return '$reds+${_pad(blueBall)}';
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');
}

class ParsedFileResult {
  ParsedFileResult({
    required this.fileName,
    required this.records,
    required this.errors,
  });

  final String fileName;
  final List<NumberRecord> records;
  final List<String> errors;
}

class ReferenceNumber {
  ReferenceNumber({
    required this.redBalls,
    required this.blueBall,
  });

  final List<int> redBalls;
  final int blueBall;

  String get display {
    final reds = redBalls.map((e) => e.toString().padLeft(2, '0')).join('.');
    return '$reds+${blueBall.toString().padLeft(2, '0')}';
  }
}
