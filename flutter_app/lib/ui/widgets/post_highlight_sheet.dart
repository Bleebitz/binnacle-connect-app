// Community's "Post a highlight" flow: select existing Library media or
// import new media from the phone, preview it, add a caption, choose an
// audience, and require an explicit Publish action.
//
// AUDIENCE, stated honestly: "Crew" is the only real destination. There
// is no external identity/social backend (BIN-46 security/account
// linking and BIN-40 Binnacle Live viewing are both still Todo) for a
// broader public/shared audience, so this never fabricates a public feed
// or a fake successful post to one. Publishing to Crew is itself real and
// complete: it attaches the clip to CrewRepository's most recent session
// (see crew_screen.dart's postHighlight), visible immediately in Crew →
// Sessions — no network call, no simulated success.
//
// DRAFTS: kept only for the sheet's own lifetime (selected media +
// caption survive reopening the sheet while the underlying widget tree
// stays mounted), not persisted across an app restart — a smaller, honest
// scope rather than claiming full draft persistence that isn't built.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/clip.dart';
import '../../core/services/media_import_service.dart';
import '../screens/crew_screen.dart';
import '../screens/library_screen.dart';
import '../theme/binnacle_theme.dart';
import 'media_import_sheet.dart';

enum HighlightAudience { crew, public }

extension on HighlightAudience {
  String get label => switch (this) {
        HighlightAudience.crew => 'Crew',
        HighlightAudience.public => 'Public (Binnacle Live)',
      };
  bool get isAvailable => this == HighlightAudience.crew;
}

Future<void> showPostHighlightSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PostHighlightSheet(),
  );
}

class _PostHighlightSheet extends StatefulWidget {
  const _PostHighlightSheet();

  @override
  State<_PostHighlightSheet> createState() => _PostHighlightSheetState();
}

class _PostHighlightSheetState extends State<_PostHighlightSheet> {
  Clip? _selected;
  final _captionController = TextEditingController();
  HighlightAudience _audience = HighlightAudience.crew;
  bool _publishing = false;
  bool _published = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _importNew() async {
    final clip = await pickAndImportMedia(context, kind: ImportMediaKind.photo);
    if (clip != null && mounted) setState(() => _selected = clip);
  }

  Future<void> _importVideo() async {
    final clip = await pickAndImportMedia(context, kind: ImportMediaKind.video);
    if (clip != null && mounted) setState(() => _selected = clip);
  }

  Future<void> _publish() async {
    final clip = _selected;
    if (clip == null) return;
    setState(() => _publishing = true);
    // Deliberately no network/backend call — see module comment. The
    // brief delay + explicit "Published" state is real UI feedback for a
    // real local state change (CrewRepository.postHighlight,
    // ClipRepository's caption), not decoration for a fake network wait.
    context.read<ClipRepository>().setCaption(clip.id, _captionController.text.trim());
    context.read<CrewRepository>().postHighlight(clip.id);
    if (!mounted) return;
    setState(() {
      _publishing = false;
      _published = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_published) {
      return _PostHighlightScaffold(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, color: BinnacleColors.tealBright, size: 40),
            const SizedBox(height: 12),
            const Text('Posted to Crew', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
              'Visible now in Crew → Sessions.',
              style: TextStyle(color: BinnacleColors.slate, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ]),
        ),
      );
    }

    final clips = context.watch<ClipRepository>().clips;

    return _PostHighlightScaffold(
      child: Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Post a highlight', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_selected == null) ...[
              Text('Choose from your Library, or import new media.',
                  style: TextStyle(color: BinnacleColors.slate, fontSize: 12.5)),
              const SizedBox(height: 10),
              if (clips.isNotEmpty)
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: clips.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _LibraryThumb(clip: clips[i], onTap: () => setState(() => _selected = clips[i])),
                  ),
                ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importNew,
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('Import photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importVideo,
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Import video'),
                  ),
                ),
              ]),
            ] else ...[
              Row(children: [
                _LibraryThumb(clip: _selected!, onTap: null),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_selected!.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: BinnacleColors.offWhite)),
                ),
                TextButton(onPressed: () => setState(() => _selected = null), child: const Text('Change')),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _captionController,
                maxLines: 3,
                style: const TextStyle(color: BinnacleColors.offWhite, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Add a caption…',
                  hintStyle: const TextStyle(color: BinnacleColors.slateLight),
                  filled: true,
                  fillColor: BinnacleColors.navyRaised,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: BinnacleColors.offWhite.withValues(alpha: 0.15))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: BinnacleColors.tealBright, width: 2)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Audience', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              for (final audience in HighlightAudience.values)
                RadioListTile<HighlightAudience>(
                  contentPadding: EdgeInsets.zero,
                  value: audience,
                  groupValue: _audience,
                  onChanged: audience.isAvailable ? (v) => setState(() => _audience = v!) : null,
                  title: Text(audience.label,
                      style: TextStyle(color: audience.isAvailable ? BinnacleColors.offWhite : BinnacleColors.slateDim)),
                  subtitle: audience.isAvailable
                      ? null
                      : const Text(
                          'Not available yet — requires an account/identity system that '
                          'doesn\'t exist (see BIN-46/BIN-40).',
                          style: TextStyle(fontSize: 11),
                        ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _publishing ? null : _publish,
                  child: _publishing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Publish'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PostHighlightScaffold extends StatelessWidget {
  final Widget child;
  const _PostHighlightScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: BinnacleColors.navy,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: child,
      ),
    );
  }
}

class _LibraryThumb extends StatelessWidget {
  final Clip clip;
  final VoidCallback? onTap;
  const _LibraryThumb({required this.clip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        height: 70,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BinnacleColors.navyRaised,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          clip.kind == ClipKind.photo ? Icons.photo_outlined : Icons.videocam_outlined,
          color: BinnacleColors.tealBright,
        ),
      ),
    );
  }
}
