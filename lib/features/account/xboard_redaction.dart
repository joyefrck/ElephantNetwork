class XboardRedaction {
  const XboardRedaction._();

  static String text(Object? value) {
    var output = value?.toString() ?? '';
    output = output.replaceAllMapped(
      RegExp(
        r'(authorization\s*[:=]\s*bearer\s+)[^\s,}\]]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[REDACTED]',
    );
    output = output.replaceAllMapped(
      RegExp(
        r'(password|token|auth_data)(\s*[:=]\s*)[^\s,}&}\]]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}${match.group(2)}[REDACTED]',
    );
    output = output.replaceAllMapped(
      RegExp(r'https?://[^\s]+'),
      (match) => _redactUri(match.group(0)!),
    );
    return output;
  }

  static String _redactUri(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) return '[REDACTED_URL]';
    final path = uri.path.toLowerCase();
    final sensitivePath = path.contains('quick') || path.contains('subscribe');
    if (sensitivePath || uri.queryParameters.keys.any(_sensitiveKey)) {
      return '${uri.scheme}://${uri.host}/[REDACTED]';
    }
    return uri.replace(query: '').toString();
  }

  static bool _sensitiveKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('token') || normalized.contains('auth');
  }
}
