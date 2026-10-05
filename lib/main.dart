import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const WahaAI());
}

class WahaAI extends StatelessWidget {
  const WahaAI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Waha AI',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF60A5FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
      ),
      home: const ChatPage(),
    );
  }
}

// ============================================================
// MESSAGE
// ============================================================

class ChatMessage {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final List<AttachedFile> files;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.files = const [],
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'files': files.map((file) => file.toJson()).toList(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];

    final parsedFiles = <AttachedFile>[];

    if (rawFiles is List) {
      for (final item in rawFiles) {
        if (item is Map) {
          parsedFiles.add(
            AttachedFile.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }

    return ChatMessage(
      id: json['id']?.toString(),
      role: json['role']?.toString() ?? 'user',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(
            json['createdAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
      files: parsedFiles,
    );
  }
}

// ============================================================
// ATTACHED FILE
// ============================================================

class AttachedFile {
  final String name;
  final String path;
  final int size;
  final String extension;

  AttachedFile({
    required this.name,
    required this.path,
    required this.size,
    required this.extension,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'size': size,
      'extension': extension,
    };
  }

  factory AttachedFile.fromJson(Map<String, dynamic> json) {
    return AttachedFile(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      size: int.tryParse(
            json['size']?.toString() ?? '0',
