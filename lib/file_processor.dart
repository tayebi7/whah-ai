import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'ai_service.dart' show ImagePart;
import 'cp1256.dart';
import 'models.dart';
import 'net_utils.dart';
import 'pdf_text.dart';

enum FileKind { text, image, video, office, pdf, other }

class ProcessedFile {
  final String name;
  FileKind kind;
  String text;
  final List<ImagePart> images;
  final List<String> notes;

  ProcessedFile(this.name, this.kind)
      : text = '',
        images = [],
        notes = [];
}

/// قراءة أي ملف يرفقه المستخدم وتحويله إلى نص و/أو صور يفهمها النموذج.
/// يعتمد على محتوى الملف الحقيقي وليس على الامتداد فقط.
class FileProcessor {
  static const Set<String> textExts = {
    'txt', 'md', 'markdown', 'rst', 'csv', 'tsv', 'json', 'jsonl', 'ndjson',
    'xml', 'html', 'htm', 'xhtml', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf',
    'env', 'log', 'sql', 'srt', 'vtt', 'ass', 'tex', 'bib', 'js', 'mjs', 'ts',
    'jsx', 'tsx', 'py', 'java', 'kt', 'kts', 'dart', 'c', 'h', 'cpp', 'cc',
    'hpp', 'cs', 'go', 'rs', 'rb', 'php', 'swift', 'sh', 'bash', 'zsh', 'bat',
    'cmd', 'ps1', 'gradle', 'properties', 'css', 'scss', 'sass', 'less', 'vue',
    'svelte', 'lua', 'r', 'pl', 'scala', 'dockerfile', 'makefile', 'gitignore',
    'ipynb', 'svg', 'plist', 'tf', 'proto', 'graphql', 'vcf', 'ics', 'eml',
    'text', 'rtf',
  };
  static const Set<String> imageExts = {
    'png', 'jpg', 'jpeg', 'jpe', 'jfif', 'webp', 'gif', 'bmp', 'heic', 'heif',
    'avif', 'tif', 'tiff', 'ico', 'dng',
  };
  static const Set<String> videoExts = {
    'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', '3gp', '3g2', 'flv', 'wmv',
    'mpg', 'mpeg', 'ts', 'mts', 'm2ts', 'ogv',
  };
  static const Set<String> officeExts = {
    'docx', 'docm', 'dotx', 'xlsx', 'xlsm', 'xltx', 'pptx', 'pptm', 'odt',
    'ods', 'odp', 'epub',
  };
  static const Set<String> legacyOfficeExts = {'doc', 'xls', 'ppt'};

  static String extOf(String name) {
    final n = name.toLowerCase();
    final i = n.lastIndexOf('.');
    if (i < 0) return n; // مثل Dockerfile
    return n.substring(i + 1);
  }

  static FileKind kindOf(String name) {
    final e = extOf(name);
    if (e == 'ts') return FileKind.text; // TypeScript (وليس MPEG-TS)
    if (imageExts.contains(e)) return FileKind.image;
    if (videoExts.contains(e)) return FileKind.video;
    if (e == 'pdf') return FileKind.pdf;
    if (officeExts.contains(e)) return FileKind.office;
    if (textExts.contains(e)) return FileKind.text;
    return FileKind.other;
  }

  /// أرقام عربية/فارسية → لاتينية (مفيد للفواتير والحسابات)
  static String normalizeDigits(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final a = ar.indexOf(ch);
      final f = fa.indexOf(ch);
      if (a >= 0) {
        b.write(a);
      } else if (f >= 0) {
        b.write(f);
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }

  // ───────────── المعالجة الرئيسية ─────────────

  static Future<ProcessedFile> process(
    AttachedFile f, {
    required int maxChars,
    int maxVideoFrames = 6,
  }) async {
    var kind = kindOf(f.name);
    final pf = ProcessedFile(f.name, kind);
    try {
      final file = File(f.path);
      if (f.path.isEmpty || !await file.exists()) {
        pf.notes.add('الملف غير موجود على الجهاز (ربما حُذف من الذاكرة المؤقتة). أعد إرفاقه.');
        return pf;
      }

      // الفيديو: لا نقرأه كاملاً في الذاكرة
      if (kind == FileKind.video) {
        await _processVideo(f.path, pf, maxFrames: maxVideoFrames);
        return pf;
      }

      final len = await file.length();
      if (len > 60 * 1024 * 1024) {
        pf.notes.add('الملف كبير جداً (${(len / 1048576).toStringAsFixed(0)}MB). الحد 60MB.');
        return pf;
      }
      final bytes = await file.readAsBytes();

      // اكتشاف النوع الحقيقي (امتداد خاطئ مثل صورة باسم .txt)
      final det = detectType(bytes);
      if (det.kind == 'image' && kind != FileKind.image) {
        kind = FileKind.image;
        pf.notes.add('تم اكتشاف أن الملف صورة (${det.ext}) رغم امتداده.');
      } else if (det.kind == 'video' && kind != FileKind.video) {
        pf.kind = FileKind.video;
        pf.notes.add('تم اكتشاف أن الملف فيديو (${det.ext}) رغم امتداده.');
        await _processVideo(f.path, pf, maxFrames: maxVideoFrames);
        return pf;
      } else if (det.kind == 'pdf' && kind != FileKind.pdf) {
        kind = FileKind.pdf;
      } else if (det.kind == 'zip' &&
          (kind == FileKind.other || kind == FileKind.text)) {
        kind = FileKind.office;
      }
      pf.kind = kind;

      switch (kind) {
        case FileKind.image:
          await _processImage(bytes, pf, ext: extOf(f.name));
          break;
        case FileKind.pdf:
          final t = PdfText.extract(bytes);
          if (t.trim().isEmpty) {
            pf.notes.add(
                'تعذر استخراج نص من PDF (قد يكون ممسوحاً ضوئياً أو بخطوط مشفّرة). '
                'التقط صور الصفحات وأرسلها كصور ليقرأها نموذج الرؤية.');
          } else {
            pf.text = t;
          }
          break;
        case FileKind.office:
          await _processOffice(bytes, pf, extOf(f.name));
          break;
        case FileKind.text:
          pf.text = _processText(bytes, extOf(f.name));
          break;
        case FileKind.other:
          if (_looksLikeText(bytes)) {
            pf.kind = FileKind.text;
            pf.text = _processText(bytes, extOf(f.name));
          } else if (legacyOfficeExts.contains(extOf(f.name))) {
            pf.notes.add(
                'صيغة Office القديمة (.${extOf(f.name)}) غير مدعومة. احفظها بصيغة '
                '${extOf(f.name)}x (docx/xlsx/pptx) أو PDF وأعد الإرفاق.');
          } else {
            pf.notes.add('نوع الملف غير مدعوم للقراءة المباشرة.');
          }
          break;
        case FileKind.video:
          break;
      }
    } catch (e) {
      pf.notes.add('تعذر قراءة الملف: $e');
    }
    return pf;
  }

  // ───────────── النص ─────────────

  static bool _looksLikeText(Uint8List b) {
    final n = b.length < 4096 ? b.length : 4096;
    if (n == 0) return true;
    var bad = 0;
    for (var i = 0; i < n; i++) {
      final c = b[i];
      if (c == 0) return false;
      if (c < 9 || (c > 13 && c < 32)) bad++;
    }
    return bad * 20 < n;
  }

  /// فك ترميز النص: UTF-8 / UTF-16 / Windows-1256 (العربية القديمة)
  static String decodeText(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      return utf8.decode(b.sublist(3), allowMalformed: true);
    }
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
      return _utf16(b.sublist(2), false);
    }
    if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
      return _utf16(b.sublist(2), true);
    }
    if (b.length >= 4 && b[1] == 0 && b[3] == 0 && b[0] != 0) {
      return _utf16(b, false);
    }
    try {
      return utf8.decode(b);
    } catch (_) {
      return decodeCp1256(b);
    }
  }

  static String _utf16(List<int> b, bool bigEndian) {
    final units = <int>[];
    for (var i = 0; i + 1 < b.length; i += 2) {
      units.add(bigEndian ? (b[i] << 8) | b[i + 1] : (b[i + 1] << 8) | b[i]);
    }
    return String.fromCharCodes(units);
  }

  static String _processText(Uint8List bytes, String ext) {
    final raw = decodeText(bytes);
    switch (ext) {
      case 'json':
        try {
          final j = jsonDecode(raw);
          return const JsonEncoder.withIndent('  ').convert(j);
        } catch (_) {
          return raw;
        }
      case 'html':
      case 'htm':
      case 'xhtml':
        return htmlToText(raw);
      case 'ipynb':
        return _ipynb(raw);
      case 'rtf':
        return _rtfToText(raw);
      default:
        return raw;
    }
  }

  static String _ipynb(String raw) {
    try {
      final j = jsonDecode(raw);
      final cells = (j is Map ? j['cells'] : null) as List?;
      if (cells == null) return raw;
      final b = StringBuffer();
      for (final c in cells) {
        if (c is! Map) continue;
        final src = c['source'];
        final text = src is List ? src.join() : src?.toString() ?? '';
        b.writeln(c['cell_type'] == 'code' ? '```python\n$text\n```' : text);
        final outs = c['outputs'];
        if (outs is List) {
          for (final o in outs) {
            if (o is Map && o['text'] != null) {
              final t = o['text'];
              b.writeln('ناتج:\n${t is List ? t.join() : t}');
            }
          }
        }
        b.writeln();
      }
      return b.toString();
    } catch (_) {
      return raw;
    }
  }

  static String _rtfToText(String rtf) {
    var s = rtf.replaceAll(RegExp(r'\\par[d]?\b'), '\n');
    s = s.replaceAllMapped(
        RegExp(r"\\'([0-9a-fA-F]{2})"),
        (m) => decodeCp1256([int.parse(m.group(1)!, radix: 16)]));
    s = s.replaceAllMapped(RegExp(r'\\u(-?\d+)\??'), (m) {
      var v = int.parse(m.group(1)!);
      if (v < 0) v += 65536;
      return String.fromCharCode(v);
    });
    s = s.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '');
    s = s.replaceAll(RegExp(r'[{}]'), '');
    return s.trim();
  }

  static String htmlToText(String html) {
    var s = html;
    s = s.replaceAll(
        RegExp(r'<(script|style|head)\b[^>]*>.*?</\1>',
            caseSensitive: false, dotAll: true),
        ' ');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(
        RegExp(r'</(p|div|li|tr|h[1-6]|section|article|table)>',
            caseSensitive: false),
        '\n');
    s = s.replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), ' | ');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = unescapeXml(s);
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
    return s.trim();
  }

  static String unescapeXml(String s) {
    return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x')) {
        final v = int.tryParse(e.substring(2), radix: 16);
        return v == null ? m.group(0)! : String.fromCharCode(v);
      }
      if (e.startsWith('#')) {
        final v = int.tryParse(e.substring(1));
        return v == null ? m.group(0)! : String.fromCharCode(v);
      }
      switch (e) {
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'amp':
          return '&';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        case 'nbsp':
          return ' ';
        default:
          return m.group(0)!;
      }
    });
  }

  // ───────────── Office ─────────────

  static List<int> _content(ArchiveFile f) {
    final c = f.content;
    return c is List<int> ? c : <int>[];
  }

  static ArchiveFile? _find(Archive a, String name) {
    for (final f in a.files) {
      if (f.isFile && f.name == name) return f;
    }
    return null;
  }

  static String _read(Archive a, String name) {
    final f = _find(a, name);
    if (f == null) return '';
    return utf8.decode(_content(f), allowMalformed: true);
  }

  static Future<void> _processOffice(
      Uint8List bytes, ProcessedFile pf, String ext) async {
    Archive a;
    try {
      a = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      pf.notes.add('الملف تالف أو ليس بصيغة Office صالحة.');
      return;
    }
    final names = a.files.where((e) => e.isFile).map((e) => e.name).toList();

    if (names.contains('word/document.xml')) {
      pf.text = _docxText(_read(a, 'word/document.xml'));
      await _embeddedImages(a, 'word/media/', pf);
    } else if (names.contains('xl/workbook.xml')) {
      pf.text = _xlsxText(a);
    } else if (names.any((n) => n.startsWith('ppt/slides/slide'))) {
      pf.text = _pptxText(a, names);
      await _embeddedImages(a, 'ppt/media/', pf);
    } else if (names.contains('content.xml')) {
      pf.text = _odfText(_read(a, 'content.xml'));
    } else if (names.any((n) => n.endsWith('.xhtml') || n.endsWith('.html'))) {
      final htmls = names
          .where((n) =>
              n.endsWith('.xhtml') || n.endsWith('.html') || n.endsWith('.htm'))
          .toList()
        ..sort();
      final b = StringBuffer();
      for (final n in htmls) {
        b.writeln(htmlToText(_read(a, n)));
        b.writeln();
      }
      pf.text = b.toString();
    } else {
      pf.notes.add('أرشيف ZIP: يحتوي ${names.length} ملفاً. أرسل الملفات منفردة لقراءتها.');
      pf.text = 'محتويات الأرشيف:\n${names.take(80).join('\n')}';
      return;
    }
    if (pf.text.trim().isEmpty && pf.images.isEmpty) {
      pf.notes.add('لم يُعثر على نص داخل الملف.');
    }
  }

  static Future<void> _embeddedImages(
      Archive a, String prefix, ProcessedFile pf) async {
    var n = 0;
    for (final f in a.files) {
      if (n >= 3) break;
      if (!f.isFile || !f.name.startsWith(prefix)) continue;
      final b = Uint8List.fromList(_content(f));
      if (b.length < 4000) continue; // أيقونات صغيرة
      if (detectType(b).kind != 'image') continue;
      final part = await prepareImage(b);
      if (part != null) {
        pf.images.add(part);
        n++;
      }
    }
    if (n > 0) pf.notes.add('أُرفقت $n صورة مضمّنة داخل المستند.');
  }

  static String _docxText(String xml) {
    var s = xml;
    s = s.replaceAll(RegExp(r'<w:tab\s*/>'), '\t');
    s = s.replaceAll(RegExp(r'<w:(br|cr)\s*/?>'), '\n');
    s = s.replaceAll('</w:p>', '\n');
    s = s.replaceAll('</w:tc>', ' | ');
    s = s.replaceAll('</w:tr>', '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = unescapeXml(s);
    return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static String _pptxText(Archive a, List<String> names) {
    final slides = names
        .where((n) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(n))
        .toList();
    int num(String n) =>
        int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(n)?.group(1) ?? '') ?? 0;
    slides.sort((x, y) => num(x).compareTo(num(y)));
    final b = StringBuffer();
    var i = 1;
    for (final n in slides) {
      final xml = _read(a, n).replaceAll('</a:p>', '\n');
      final texts = RegExp(r'<a:t\b[^>]*>(.*?)</a:t>|\n', dotAll: true)
          .allMatches(xml)
          .map((m) => m.group(0) == '\n' ? '\n' : unescapeXml(m.group(1) ?? ''))
          .join();
      b.writeln('--- شريحة $i ---');
      b.writeln(texts.trim());
      b.writeln();
      i++;
    }
    return b.toString().trim();
  }

  static String _odfText(String xml) {
    var s = xml;
    s = s.replaceAll(RegExp(r'</text:(p|h)>'), '\n');
    s = s.replaceAll('</table:table-cell>', ' | ');
    s = s.replaceAll('</table:table-row>', '\n');
    s = s.replaceAll(RegExp(r'<text:line-break\s*/>'), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    return unescapeXml(s).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static String? _attr(String tag, String name) {
    final m = RegExp('\\b${RegExp.escape(name)}="([^"]*)"').firstMatch(tag);
    return m?.group(1);
  }

  static int _colIndex(String ref) {
    var n = 0;
    for (final c in ref.codeUnits) {
      if (c >= 65 && c <= 90) {
        n = n * 26 + (c - 64);
      } else if (c >= 97 && c <= 122) {
        n = n * 26 + (c - 96);
      } else {
        break;
      }
    }
    return n - 1;
  }

  static String _xlsxText(Archive a) {
    // النصوص المشتركة
    final shared = <String>[];
    final ss = _read(a, 'xl/sharedStrings.xml');
    for (final m in RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true).allMatches(ss)) {
      final inner = m.group(1) ?? '';
      shared.add(RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true)
          .allMatches(inner)
          .map((t) => unescapeXml(t.group(1) ?? ''))
          .join());
    }

    // أسماء الأوراق ومساراتها
    final wb = _read(a, 'xl/workbook.xml');
    final rels = _read(a, 'xl/_rels/workbook.xml.rels');
    final relTarget = <String, String>{};
    for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(rels)) {
      final tag = m.group(0)!;
      final id = _attr(tag, 'Id');
      final target = _attr(tag, 'Target');
      if (id != null && target != null) {
        var t = target;
        if (t.startsWith('/')) t = t.substring(1);
        relTarget[id] = t.startsWith('xl/') ? t : 'xl/$t';
      }
    }
    final sheets = <MapEntry<String, String>>[];
    for (final m in RegExp(r'<sheet\b[^>]*>').allMatches(wb)) {
      final tag = m.group(0)!;
      final name = unescapeXml(_attr(tag, 'name') ?? 'Sheet');
      final rid = _attr(tag, 'r:id');
      final path = rid != null ? relTarget[rid] : null;
      if (path != null) sheets.add(MapEntry(name, path));
    }
    if (sheets.isEmpty) {
      final files = a.files
          .where((f) => f.isFile && RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name))
          .map((f) => f.name)
          .toList()
        ..sort();
      for (var i = 0; i < files.length; i++) {
        sheets.add(MapEntry('Sheet${i + 1}', files[i]));
      }
    }

    final out = StringBuffer();
    for (final sh in sheets) {
      final xml = _read(a, sh.value);
      if (xml.isEmpty) continue;
      out.writeln('## ورقة: ${sh.key}');
      var rows = 0;
      for (final rm in RegExp(r'<row\b[^>]*?(?:/>|>(.*?)</row>)', dotAll: true)
          .allMatches(xml)) {
        final rowXml = rm.group(1) ?? '';
        if (rowXml.isEmpty) continue;
        final cells = <int, String>{};
        var maxCol = -1;
        for (final cm in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
            .allMatches(rowXml)) {
          final attrs = cm.group(1) ?? '';
          final inner = cm.group(2) ?? '';
          final ref = _attr(attrs, 'r') ?? '';
          final type = _attr(attrs, 't') ?? '';
          final col = ref.isEmpty ? maxCol + 1 : _colIndex(ref);
          if (col < 0 || col > 300) continue;
          String val = '';
          if (type == 'inlineStr') {
            val = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true)
                .allMatches(inner)
                .map((t) => unescapeXml(t.group(1) ?? ''))
                .join();
          } else {
            final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(inner)?.group(1);
            if (v != null) {
              if (type == 's') {
                final idx = int.tryParse(v) ?? -1;
                val = idx >= 0 && idx < shared.length ? shared[idx] : v;
              } else {
                val = unescapeXml(v);
              }
            }
          }
          if (val.isNotEmpty) {
            cells[col] = val.replaceAll('\n', ' ');
            if (col > maxCol) maxCol = col;
          }
        }
        if (maxCol < 0) continue;
        final line = List.generate(maxCol + 1, (i) => cells[i] ?? '').join(' | ');
        out.writeln(line);
        rows++;
        if (rows >= 3000) {
          out.writeln('… (اقتُطعت الصفوف بعد 3000)');
          break;
        }
      }
      out.writeln();
    }
    final t = out.toString().trim();
    if (t.isEmpty) return '';
    return '$t\n\n(ملاحظة: التواريخ في Excel قد تظهر كأرقام تسلسلية مثل 45123، والنسب كأعداد عشرية.)';
  }

  // ───────────── الصور ─────────────

  static Future<void> _processImage(Uint8List bytes, ProcessedFile pf,
      {required String ext}) async {
    if (ext == 'svg') {
      pf.text = utf8.decode(bytes, allowMalformed: true);
      pf.kind = FileKind.text;
      return;
    }
    final part = await prepareImage(bytes);
    if (part == null) {
      pf.notes.add(
          'تعذر فك ترميز الصورة (${detectType(bytes).ext}). جرّب حفظها بصيغة JPG/PNG.');
    } else {
      pf.images.add(part);
    }
  }

  /// يجهّز الصورة للنموذج: يحوّل أي صيغة (webp/bmp/gif/heic...) إلى PNG/JPEG
  /// ويصغّرها (حتى 1600px) كي لا يرفضها المزود بسبب الحجم.
  static Future<ImagePart?> prepareImage(Uint8List bytes) async {
    final det = detectType(bytes);
    // JPEG/PNG صغيرة: تمرّر كما هي
    if ((det.mime == 'image/jpeg' || det.mime == 'image/png') &&
        bytes.length <= 1500 * 1024) {
      return ImagePart(det.mime, base64Encode(bytes));
    }
    for (final maxSide in const [1600, 1024, 640]) {
      try {
        final probe = await ui.instantiateImageCodec(bytes);
        final frame = await probe.getNextFrame();
        final w = frame.image.width;
        final h = frame.image.height;
        frame.image.dispose();
        probe.dispose();

        ui.Codec codec;
        if (w >= h && w > maxSide) {
          codec = await ui.instantiateImageCodec(bytes, targetWidth: maxSide);
        } else if (h > w && h > maxSide) {
          codec = await ui.instantiateImageCodec(bytes, targetHeight: maxSide);
        } else {
          codec = await ui.instantiateImageCodec(bytes);
        }
        final fr = await codec.getNextFrame();
        final data = await fr.image.toByteData(format: ui.ImageByteFormat.png);
        fr.image.dispose();
        codec.dispose();
        if (data == null) continue;
        final png = data.buffer.asUint8List();
        if (png.length > 3500 * 1024 && maxSide != 640) continue;
        return ImagePart('image/png', base64Encode(png));
      } catch (_) {
        break;
      }
    }
    // فشل التحويل: إن كانت الصيغة مقبولة عالمياً أرسلها كما هي
    if (det.mime == 'image/jpeg' ||
        det.mime == 'image/png' ||
        det.mime == 'image/webp' ||
        det.mime == 'image/gif') {
      if (bytes.length < 5 * 1024 * 1024) {
        return ImagePart(det.mime, base64Encode(bytes));
      }
    }
    return null;
  }

  // ───────────── الفيديو ─────────────

  /// فهم الفيديو: يُستخرج عدة إطارات موزعة على مدته (أي صيغة يفكّها الجهاز:
  /// mp4, mov, mkv, webm, avi, 3gp ...) وتُرسل كصور لنموذج الرؤية.
  static Future<void> _processVideo(String path, ProcessedFile pf,
      {int maxFrames = 6}) async {
    var durMs = 0;
    try {
      final c = VideoPlayerController.file(File(path));
      await c.initialize();
      durMs = c.value.duration.inMilliseconds;
      await c.dispose();
    } catch (_) {}

    final times = <int>[];
    if (durMs > 0) {
      for (var i = 0; i < maxFrames; i++) {
        times.add(((durMs * (i + 0.5)) / maxFrames).round());
      }
    } else {
      times.addAll([0, 1000, 3000, 6000, 10000, 20000]);
    }

    for (final t in times) {
      try {
        final data = await VideoThumbnail.thumbnailData(
          video: path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 896,
          timeMs: t,
          quality: 75,
        );
        if (data != null && data.isNotEmpty) {
          pf.images.add(ImagePart('image/jpeg', base64Encode(data)));
        }
      } catch (_) {}
    }

    if (pf.images.isEmpty) {
      pf.notes.add(
          'تعذر قراءة الفيديو: صيغته غير مدعومة على هذا الجهاز. حوّله إلى MP4 (H.264) ثم أعد الإرفاق.');
      return;
    }
    final secs = durMs > 0 ? ' (المدة ≈ ${(durMs / 1000).round()} ثانية)' : '';
    pf.notes.add(
        'فيديو$secs: استُخرجت ${pf.images.length} لقطات موزعة على مدته بالترتيب الزمني. '
        'الصوت لا يُحلَّل — اعتمد على اللقطات المرئية فقط وصرّح بذلك عند الحاجة.');
  }

  // ───────────── تجميع السياق ─────────────

  /// يبني كتلة نصية من كل الملفات المعالجة لتُرسل مع السؤال
  static String buildContext(List<ProcessedFile> files,
      {required int maxChars, bool normalizeNumbers = false}) {
    final b = StringBuffer();
    var budget = maxChars * 3;
    for (final f in files) {
      var text = f.text.trim();
      if (normalizeNumbers) text = normalizeDigits(text);
      b.writeln('===== ملف: ${f.name} =====');
      if (text.isNotEmpty) {
        final limit = budget < maxChars ? budget : maxChars;
        if (limit <= 0) {
          b.writeln('(تم تجاوز الحد الكلي للنص — لم يُضمَّن هذا الملف)');
        } else if (text.length > limit) {
          b.writeln(text.substring(0, limit));
          b.writeln('… [اقتُطع ${text.length - limit} حرفاً من الملف لتجاوزه الحد]');
          budget -= limit;
        } else {
          b.writeln(text);
          budget -= text.length;
        }
      }
      if (f.images.isNotEmpty) {
        b.writeln('(مرفق ${f.images.length} صورة/لقطة لهذا الملف مع الرسالة)');
      }
      for (final n in f.notes) {
        b.writeln('ملاحظة: $n');
      }
      b.writeln('===== نهاية الملف =====');
      b.writeln();
    }
    return b.toString().trim();
  }
}
