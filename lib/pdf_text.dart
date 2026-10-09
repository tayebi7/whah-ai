import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// استخراج نص من PDF بدون مكتبات خارجية (يعمل مع ملفات PDF النصية الشائعة).
/// الملفات الممسوحة ضوئياً أو ذات الخطوط المشفّرة قد لا تعطي نتيجة؛ في هذه الحالة
/// يُعاد نص فارغ ويُنصح بإرسال صفحات الملف كصور.
class PdfText {
  static String extract(Uint8List bytes, {int maxChars = 400000}) {
    final s = latin1.decode(bytes);
    final out = StringBuffer();
    var pos = 0;
    while (out.length < maxChars) {
      final i = s.indexOf('stream', pos);
      if (i < 0) break;
      if (i >= 3 && s.substring(i - 3, i) == 'end') {
        pos = i + 6;
        continue;
      }
      var start = i + 6;
      if (start < s.length && s.codeUnitAt(start) == 13) start++;
      if (start < s.length && s.codeUnitAt(start) == 10) start++;
      final end = s.indexOf('endstream', start);
      if (end < 0) break;
      final dictStart = s.lastIndexOf('obj', i);
      final dict = dictStart >= 0 ? s.substring(dictStart, i) : '';
      pos = end + 9;
      if (dict.contains('/Image') || dict.contains('/FontFile')) continue;

      var e2 = end;
      while (e2 > start && (bytes[e2 - 1] == 10 || bytes[e2 - 1] == 13)) {
        e2--;
      }
      List<int> data = bytes.sublist(start, e2);
      if (dict.contains('FlateDecode')) {
        try {
          data = zlib.decode(data);
        } catch (_) {
          continue;
        }
      }
      final content = latin1.decode(data, allowInvalid: true);
      if (!content.contains('BT')) continue;
      final t = _fromContent(content);
      if (t.trim().isNotEmpty) {
        out.writeln(t.trim());
        out.writeln();
      }
    }
    final text = out.toString();
    return quality(text) >= 0.6 ? text : '';
  }

  /// نسبة الأحرف "المقروءة" في النص (0..1)
  static double quality(String t) {
    if (t.trim().isEmpty) return 0;
    final good = RegExp(r'''[\p{L}\p{N}\s.,;:!?()\-/%$€@#&*+=_\[\]{}"']''',
        unicode: true);
    var ok = 0;
    var total = 0;
    for (final r in t.runes) {
      total++;
      if (good.hasMatch(String.fromCharCode(r))) ok++;
    }
    return total == 0 ? 0 : ok / total;
  }

  static bool _isNumChar(int c) =>
      (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E;

  static bool _isAlpha(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x27 ||
      c == 0x22 ||
      c == 0x2A;

  static String _fromContent(String c) {
    final out = StringBuffer();
    final line = StringBuffer();
    final nums = <double>[];
    double? lastY;
    final n = c.length;
    var i = 0;

    void flush(String sep) {
      if (line.isNotEmpty) {
        out.write(line.toString());
        line.clear();
      }
      if (out.isNotEmpty) out.write(sep);
    }

    while (i < n) {
      final ch = c.codeUnitAt(i);
      if (ch == 0x28) {
        // literal string
        var depth = 1;
        i++;
        final sb = StringBuffer();
        while (i < n && depth > 0) {
          final x = c.codeUnitAt(i);
          if (x == 0x5C) {
            i++;
            if (i >= n) break;
            final e = c.codeUnitAt(i);
            if (e == 0x6E) {
              sb.write('\n');
            } else if (e == 0x72) {
              sb.write('\r');
            } else if (e == 0x74) {
              sb.write('\t');
            } else if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              var k = 0;
              while (k < 2 && i + 1 < n) {
                final d = c.codeUnitAt(i + 1);
                if (d >= 0x30 && d <= 0x37) {
                  v = v * 8 + (d - 0x30);
                  i++;
                  k++;
                } else {
                  break;
                }
              }
              sb.writeCharCode(v);
            } else {
              sb.writeCharCode(e);
            }
            i++;
            continue;
          }
          if (x == 0x28) {
            depth++;
          } else if (x == 0x29) {
            depth--;
            if (depth == 0) {
              i++;
              break;
            }
          }
          sb.writeCharCode(x);
          i++;
        }
        line.write(sb.toString());
        continue;
      }
      if (ch == 0x3C) {
        if (i + 1 < n && c.codeUnitAt(i + 1) == 0x3C) {
          i += 2;
          continue;
        }
        final close = c.indexOf('>', i + 1);
        if (close < 0) break;
        final hex = c.substring(i + 1, close).replaceAll(RegExp(r'\s'), '');
        i = close + 1;
        line.write(_hexToText(hex));
        continue;
      }
      if (_isNumChar(ch)) {
        final st = i;
        while (i < n && _isNumChar(c.codeUnitAt(i))) {
          i++;
        }
        final v = double.tryParse(c.substring(st, i));
        if (v != null) {
          nums.add(v);
          if (nums.length > 6) nums.removeAt(0);
          if (v < -250 && line.isNotEmpty) line.write(' ');
        }
        continue;
      }
      if (_isAlpha(ch)) {
        final st = i;
        while (i < n && _isAlpha(c.codeUnitAt(i))) {
          i++;
        }
        final w = c.substring(st, i);
        switch (w) {
          case 'Td':
          case 'TD':
            final ty = nums.isNotEmpty ? nums.last : 0;
            flush(ty.abs() > 0.5 ? '\n' : ' ');
            nums.clear();
            break;
          case 'Tm':
            final y = nums.length >= 6 ? nums[5] : 0.0;
            final newLine = lastY == null || (y - lastY).abs() > 1;
            lastY = y;
            flush(newLine ? '\n' : ' ');
            nums.clear();
            break;
          case 'T*':
          case "'":
          case '"':
          case 'ET':
            flush('\n');
            nums.clear();
            break;
          default:
            if (w == 'Tj' || w == 'TJ') nums.clear();
        }
        continue;
      }
      i++;
    }
    flush('');
    return out.toString().replaceAll(RegExp(r'[ \t]+\n'), '\n');
  }

  static String _hexToText(String hex) {
    if (hex.length < 2) return '';
    final h = hex.length.isOdd ? '${hex}0' : hex;
    final bytes = <int>[];
    for (var k = 0; k + 1 < h.length; k += 2) {
      final v = int.tryParse(h.substring(k, k + 2), radix: 16);
      if (v == null) return '';
      bytes.add(v);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16be(bytes.sublist(2));
    }
    // أزواج بايت عالية/منخفضة (UTF-16BE بدون BOM) بأحرف لاتينية
    if (bytes.length >= 2 &&
        bytes.length.isEven &&
        bytes.where((b) => b == 0).length >= bytes.length ~/ 2) {
      return _utf16be(bytes);
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  static String _utf16be(List<int> b) {
    final units = <int>[];
    for (var k = 0; k + 1 < b.length; k += 2) {
      units.add((b[k] << 8) | b[k + 1]);
    }
    return String.fromCharCodes(units);
  }
}
