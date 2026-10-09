import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'theme.dart';

/// نمط Markdown موحّد بألوان Claude
MarkdownStyleSheet markdownStyle(BuildContext context) {
  final p = context.pal;
  final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
  return base.copyWith(
    p: TextStyle(fontSize: 16, height: 1.6, color: p.text),
    h1: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text),
    h2: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: p.text),
    h3: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
    listBullet: TextStyle(fontSize: 16, color: p.text),
    a: TextStyle(color: p.accent, decoration: TextDecoration.underline),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      color: p.codeText,
      backgroundColor: p.codeBg,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: p.codeBg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: p.border),
    ),
    blockquotePadding: const EdgeInsets.all(10),
    blockquoteDecoration: BoxDecoration(
      color: p.userBubble,
      borderRadius: BorderRadius.circular(8),
    ),
    tableBorder: TableBorder.all(color: p.border),
    tableCellsPadding: const EdgeInsets.all(8),
    tableHead: TextStyle(fontWeight: FontWeight.w700, color: p.text),
    tableBody: TextStyle(color: p.text),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: p.border)),
    ),
  );
}

Future<void> openLink(String? href) async {
  if (href == null) return;
  final uri = Uri.tryParse(href);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<void> shareFile(String path) async {
  try {
    await Share.shareXFiles([XFile(path)]);
  } catch (_) {}
}

Future<void> shareText(String text) async {
  try {
    await Share.share(text);
  } catch (_) {}
}

/// صورة محفوظة محلياً مع معالجة غياب الملف
class LocalImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  const LocalImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        width: width ?? 80,
        height: height ?? 80,
        color: p.userBubble,
        child: Icon(Icons.broken_image_outlined, color: p.text2),
      ),
    );
  }
}

class ImageViewerPage extends StatelessWidget {
  final String path;
  const ImageViewerPage({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'مشاركة / حفظ',
            icon: const Icon(Icons.ios_share),
            onPressed: () => shareFile(path),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 6,
          child: LocalImage(path: path, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// مشغّل فيديو مضمّن
class VideoCard extends StatefulWidget {
  final String path;
  const VideoCard({super.key, required this.path});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  VideoPlayerController? _c;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.file(File(widget.path));
    _c = c;
    c.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
    c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = _c;
    if (_error || c == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.userBubble,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.videocam_off_outlined, color: p.text2),
            const SizedBox(width: 10),
            const Expanded(child: Text('تعذر تشغيل الفيديو هنا')),
            TextButton(
              onPressed: () => shareFile(widget.path),
              child: const Text('فتح بتطبيق آخر'),
            ),
          ],
        ),
      );
    }
    if (!c.value.isInitialized) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: p.userBubble,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          GestureDetector(
            onTap: () => c.value.isPlaying ? c.pause() : c.play(),
            child: Container(
              color: Colors.transparent,
              child: AnimatedOpacity(
                opacity: c.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 4,
            child: IconButton(
              tooltip: 'مشاركة / حفظ',
              icon: const Icon(Icons.ios_share, color: Colors.white, size: 20),
              onPressed: () => shareFile(widget.path),
            ),
          ),
        ],
      ),
    );
  }
}

/// حقل نص LTR (للروابط والمفاتيح والنماذج) مع خيار إظهار/إخفاء القيمة
class LtrField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool secret;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final String? helper;

  const LtrField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.secret = false,
    this.keyboardType,
    this.onChanged,
    this.helper,
  });

  @override
  State<LtrField> createState() => _LtrFieldState();
}

class _LtrFieldState extends State<LtrField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: widget.secret && _hidden,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      keyboardType: widget.keyboardType,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: widget.onChanged,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        helperMaxLines: 3,
        hintTextDirection: TextDirection.ltr,
        prefixIcon: widget.icon == null ? null : Icon(widget.icon),
        suffixIcon: widget.secret
            ? IconButton(
                tooltip: _hidden ? 'إظهار' : 'إخفاء',
                icon: Icon(_hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
    );
  }
}

/// ورقة سفلية قياسية: مقبض + عنوان
class SheetScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final ScrollController? controller;

  const SheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: p.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: TextStyle(color: p.text2, fontSize: 13.5, height: 1.4)),
        ],
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

String hostOf(String url) {
  final u = Uri.tryParse(url.contains('://') ? url : 'https://$url');
  return u?.host ?? url;
}

String providerStatus(ProviderConfig p) {
  if (!p.enabled) return 'متوقف';
  if (p.endpoint.trim().isEmpty) return 'بلا عنوان';
  if (p.needsKey && p.apiKey.trim().isEmpty) return 'يحتاج مفتاح API';
  return 'جاهز';
}
