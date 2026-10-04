import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WhahApp());
}

// ======================= ألوان بطراز Claude (أزرق داكن) =======================
const kBg = Color(0xFF0F1419);
const kSide = Color(0xFF151B23);
const kSurface = Color(0xFF1C2430);
const kSurface2 = Color(0xFF243044);
const kText = Color(0xFFE8EEF5);
const kMuted = Color(0xFF8B9BB0);
const kAccent = Color(0xFF3B82F6); // أزرق Claude-like
const kAccentSoft = Color(0xFF2563EB);
const kCyan = Color(0xFF38BDF8);
const kCode = Color(0xFF0B1220);
const kUserBubble = Color(0xFF1E3A5F);
const kBorder = Color(0xFF2A3544);
const kSuccess = Color(0xFF34D399);
const kDanger = Color(0xFFF87171);

const kSystem = '''
أنت whah ai، مساعد ذكي سريع ودقيق بطراز Claude.
- أجب بنفس لغة المستخدم بوضوح وإيجاز مفيد.
- متخصص في: البرمجة (كل اللغات)، Flutter/Kotlin/Android/Gradle، Linux/bash،
  Enigma2 (Python plugins, skin XML, IPK, opkg)، تحليل البيانات، والمستندات.
- اكتب الكود داخل كتل ``` مع اسم اللغة ثم شرح مختصر.
- إذا أُرفق ملف أو صورة: حلّل المحتوى المعطى واستخرج المطلوب بدقة.
- للصور/الفيديو/التطبيقات: اقترح خطوات عملية أو كود توليد/معالجة ضمن قدراتك النصية.
- لا تختلق معلومات؛ إن لم تعرف قل ذلك.
''';

bool isRtl(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

// ======================= النماذج =======================
class AiProvider {
  String id;
  String name;
  String url;
  String key;
  String model;
  String hint;
  bool enabled;
  bool needsKey;
  bool builtIn;
  bool supportsStream;

  AiProvider({
    required this.id,
    required this.name,
    required this.url,
    required this.model,
    this.key = '',
    this.hint = '',
    this.enabled = true,
    this.needsKey = true,
    this.builtIn = false,
    this.supportsStream = true,
  });

  bool get ready => enabled && (!needsKey || key.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'key': key,
        'model': model,
        'hint': hint,
        'enabled': enabled,
        'needsKey': needsKey,
        'builtIn': builtIn,
        'supportsStream': supportsStream,
      };

  factory AiProvider.fromJson(Map<String, dynamic> j) => AiProvider(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        key: (j['key'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        hint: (j['hint'] ?? '').toString(),
        enabled: j['enabled'] != false,
        needsKey: j['needsKey'] != false,
        builtIn: j['builtIn'] == true,
        supportsStream: j['supportsStream'] != false,
      );
}

List<AiProvider> defaultProviders() => [
      AiProvider(
        id: 'groq',
        name: 'Groq (سريع جداً)',
        url: 'https://api.groq.com/openai/v1/chat/completions',
        model: 'llama-3.3-70b-versatile',
        builtIn: true,
        supportsStream: true,
        hint: 'مفتاح مجاني: console.groq.com — الأسرع عملياً',
      ),
      AiProvider(
        id: 'cerebras',
        name: 'Cerebras (سريع)',
        url: 'https://api.cerebras.ai/v1/chat/completions',
        model: 'llama-3.3-70b',
       
... 
