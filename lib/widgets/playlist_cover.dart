import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/playlist.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class PlaylistCover extends StatefulWidget {
  final Playlist playlist;
  final double size;
  final VoidCallback? onChanged;

  const PlaylistCover({
    super.key,
    required this.playlist,
    this.size = 56,
    this.onChanged,
  });

  @override
  State<PlaylistCover> createState() => _PlaylistCoverState();
}

class _PlaylistCoverState extends State<PlaylistCover> {
  final _picker = ImagePicker();
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (picked == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/playlist_cover_${widget.playlist.id}.jpg');
      await File(picked.path).copy(dest.path);
      await StorageService().updateCover(widget.playlist.id, dest.path);
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not pick cover')),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.playlist.coverPath;
    final hasCustom = path != null && path.isNotEmpty;
    return GestureDetector(
      onTap: _picking ? null : _pick,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: hasCustom
              ? null
              : const LinearGradient(
                  colors: [AppColors.mist, AppColors.line],
                ),
        ),
        child: hasCustom
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              )
            : const Icon(Icons.queue_music,
                color: AppColors.mute, size: 24),
      ),
    );
  }
}