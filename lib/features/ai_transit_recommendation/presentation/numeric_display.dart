String _groupInteger(String value) {
  final sign = value.startsWith('-') ? '-' : '';
  final digits = sign.isEmpty ? value : value.substring(1);
  final grouped = digits.replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$sign$grouped';
}

String displayCount(num value) => _groupInteger(value.round().toString());

String displayDecimal(num value) {
  final text = value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  final parts = text.split('.');
  return parts.length == 1 ? _groupInteger(parts.first) : '${_groupInteger(parts.first)}.${parts.last}';
}

String displayMoney(num value) => 'RM ${_groupInteger(value.toStringAsFixed(2).split('.').first)}.${value.toStringAsFixed(2).split('.').last}';
