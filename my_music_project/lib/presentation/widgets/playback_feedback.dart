import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../providers/audio_provider.dart';

class PlaybackFeedback extends ConsumerWidget {
  final Widget child;

  const PlaybackFeedback({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(audioProvider.select((state) => state.errorId),
        (before, after) {
      if (before == after || ModalRoute.of(context)?.isCurrent != true) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.playbackError)));
    });
    return child;
  }
}
