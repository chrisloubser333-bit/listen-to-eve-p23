import 'dart:typed_data';

/// Represents a reference image supplied to an AI provider for identity-conditioned
/// image generation or visual editing.
///
/// Follows AGENTS.md character system & provider abstraction rules:
/// - Vendor-independent representation of image bytes and metadata.
/// - Carries character identity context without coupling to vendor SDK schemas.
class ImageReference {
  final Uint8List bytes;
  final String mimeType;
  final String? characterId;
  final String? description;

  const ImageReference({
    required this.bytes,
    this.mimeType = 'image/jpeg',
    this.characterId,
    this.description,
  });
}
