import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/cloudinary_service.dart';
import '../utils/formatters.dart';

/// Circular profile picture that falls back to the user's initials.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.name,
    this.photoUrl,
    this.radius = 20,
    super.key,
  });

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      initialsFor(name),
      style: TextStyle(fontSize: radius * 0.65, fontWeight: FontWeight.w700),
    );
    final url = photoUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(radius: radius, child: initials);
    }
    final pixels = (radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .round();
    return CircleAvatar(
      radius: radius,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: cloudinaryAvatarUrl(url, size: pixels),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (_, _) => initials,
          errorWidget: (_, _, _) => initials,
        ),
      ),
    );
  }
}
