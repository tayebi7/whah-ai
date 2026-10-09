import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'net_utils.dart';

/// التخزين المحلي. كل قائمة (مزودون، مهارات، موصلات) تُحفظ في مفتاح مستقل
/// وتُكتب فوراً عند أي تغيير (كان فقدان المزود الجديد بسبب أنه لا يُحفظ إلا بزر «حفظ» الرئيسي).
class LocalStorage {
  static const settingsKey = 'whah_settings_v4';
  static const providersKey = 'whah_providers_v1';
  static const skillsKey = 'whah_skills_v1';
  static const connectorsKey = 'whah_connectors_v1';
  static const historyKey = 'waha_history_v2';

  // قديم
  static const _legacySettingsV3 = 'waha_settings_v3';
  static const _legacySettingsV2 = 'waha_settings_v2';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return null;
  }

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final j = jsonDecode(raw);
      if (j is List) {
        return j
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // ─── الإعدادات ───

  static Future<AppSettings> loadSettings() async {
    final p = await _prefs;
    final cur = _decodeMap(p.getString(settingsKey));
    if (cur != null) return AppSettings.fromJson(cur);
    // ترحيل من الإصدار القديم
    final old = _decodeMap(p.getString(_legacySettingsV3)) ??
        _decodeMap(p.getString(_legacySettingsV2));
    final s = AppSettings();
    if (old != null) {
      if (old['streamEnabled'] is bool) s.streamEnabled = old['streamEnabled'] as bool;
      final sp = old['systemPrompt']?.toString() ?? '';
      if (sp.trim().isNotEmpty) s.systemPrompt = sp;
    }
    return s;
  }

  static Future<void> saveSettings(AppSettings s) async {
    final p = await _prefs;
    await p.setString(settingsKey, jsonEncode(s.toJson()));
  }

  // ─── المزودون ───

  static Future<List<ProviderConfig>> loadProviders() async {
    final p = await _prefs;
    final raw = p.getString(providersKey);
    if (raw != null && raw.isNotEmpty) {
      return _decodeList(raw).map(ProviderConfig.fromJson).toList();
    }
    final migrated = _migrateLegacyProviders(p);
    await saveProviders(migrated);
    return migrated;
  }

  static Future<void> saveProviders(List<ProviderConfig> list) async {
    final p = await _prefs;
    await p.setString(
        providersKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static ProviderPreset _presetByName(String name) =>
      kProviderPresets.firstWhere((e) => e.name == name);

  /// يحوّل إعدادات الإصدار القديم (مفاتيح البوابة + المزودون اليدويون + المزود المفرد)
  /// إلى قائمة مزودين موحّدة بدون فقدان أي مفتاح.
  static List<ProviderConfig> _migrateLegacyProviders(SharedPreferences p) {
    final out = <ProviderConfig>[];
    final old = _decodeMap(p.getString(_legacySettingsV3)) ??
        _decodeMap(p.getString(_legacySettingsV2));
    if (old != null) {
      const gwToPreset = {
        'Groq': 'Groq',
        'Gemini': 'Gemini',
        'NVIDIA': 'NVIDIA',
        'Cerebras': 'Cerebras',
        'OpenRouter': 'OpenRouter',
      };
      final keys = old['gatewayKeys'];
      final order = old['gatewayOrder'];
      final names = <String>[];
      if (order is List) {
        for (final o in order) {
          names.add(o.toString());
        }
      }
      if (keys is Map) {
        for (final k in keys.keys) {
          if (!names.contains(k.toString())) names.add(k.toString());
        }
      }
      for (final n in names) {
        final presetName = gwToPreset[n];
        if (presetName == null) continue;
        final key = Sanitize.key(keys is Map ? (keys[n]?.toString() ?? '') : '');
        if (key.isEmpty) continue;
        final cfg = _presetByName(presetName).toConfig();
        cfg.apiKey = key;
        out.add(cfg);
      }
      final customs = old['customProviders'];
      if (customs is List) {
        for (final c in customs) {
          if (c is Map) {
            final cfg = ProviderConfig.fromJson(Map<String, dynamic>.from(c));
            cfg.apiKey = Sanitize.key(cfg.apiKey);
            if (cfg.name.isNotEmpty && cfg.endpoint.isNotEmpty) out.add(cfg);
          }
        }
      }
      final single = Sanitize.key(old['apiKey']?.toString() ?? '');
      final endpoint = old['endpoint']?.toString() ?? '';
      if (old['mode'] == 'single' && single.isNotEmpty && endpoint.isNotEmpty) {
        final dup = out.any((e) => e.apiKey == single);
        if (!dup) {
          out.add(ProviderConfig(
            name: old['provider']?.toString() ?? 'مزود سابق',
            endpoint: endpoint,
            apiKey: single,
            model: old['model']?.toString() ?? '',
          ));
        }
      }
    }
    // Pollinations المجاني كاحتياط أخير
    out.add(_presetByName('Pollinations (مجاني)').toConfig());
    return out;
  }

  // ─── Skills (المخصصة فقط) ───

  static Future<List<Skill>> loadCustomSkills() async {
    final p = await _prefs;
    return _decodeList(p.getString(skillsKey)).map(Skill.fromJson).toList();
  }

  static Future<void> saveCustomSkills(List<Skill> list) async {
    final p = await _prefs;
    await p.setString(skillsKey,
        jsonEncode(list.where((s) => !s.builtIn).map((e) => e.toJson()).toList()));
  }

  // ─── الموصلات ───

  static Future<List<ConnectorConfig>> loadConnectors() async {
    final p = await _prefs;
    return _decodeList(p.getString(connectorsKey))
        .map(ConnectorConfig.fromJson)
        .toList();
  }

  static Future<void> saveConnectors(List<ConnectorConfig> list) async {
    final p = await _prefs;
    await p.setString(
        connectorsKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // ─── المحادثات ───

  static Future<List<ChatHistory>> loadHistory() async {
    final p = await _prefs;
    return _decodeList(p.getString(historyKey)).map(ChatHistory.fromJson).toList();
  }

  static Future<void> saveHistory(List<ChatHistory> history) async {
    final p = await _prefs;
    await p.setString(
        historyKey, jsonEncode(history.map((c) => c.toJson()).toList()));
  }
}
