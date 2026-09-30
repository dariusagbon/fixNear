import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';

/// A row of job photo thumbnails. Tapping one opens it full screen.
class JobPhotoStrip extends StatelessWidget {
  const JobPhotoStrip({required this.urls, super.key});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => Semantics(
            button: true,
            label: 'Open job photo ${index + 1} of ${urls.length}',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _open(context, index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: cloudinaryThumbnailUrl(urls[index], width: 216),
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: AppTheme.tint),
                  errorWidget: (_, _, _) => Container(
                    color: AppTheme.tint,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Photo ${index + 1} of ${urls.length}')),
          body: InteractiveViewer(
            child: Center(
              child: CachedNetworkImage(
                imageUrl: cloudinaryThumbnailUrl(urls[index], width: 1600),
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => const Text('Could not load photo.'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
