import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/alfamon_evolution.dart';
import 'alfamon_evolution_progress_bar.dart';
import '../../../widgets/asset_or_network_image.dart';

class CurrentAvatar extends StatefulWidget {
  final String kidId;
  final int refreshKey;
  final double? maxWidth;
  final double? maxHeight;

  const CurrentAvatar({
    super.key,
    required this.kidId,
    required this.refreshKey,
    this.maxWidth,
    this.maxHeight,
  });

  @override
  State<CurrentAvatar> createState() => _CurrentAvatarState();
}

class _CurrentAvatarState extends State<CurrentAvatar> {
  String? _imageUrl;
  String _avatarName = 'Alfamon';
  int _currentStage = 0;
  int _pointsTotal = 0;
  bool _hasAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CurrentAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey || oldWidget.kidId != widget.kidId) {
      _load();
    }
  }

  Future<void> _load() async {
    final active = await Supabase.instance.client
        .from('kid_active_avatar')
        .select('avatar_id,points_current')
        .eq('kid_id', widget.kidId)
        .maybeSingle();

    if (active == null || active['avatar_id'] == null) {
      setState(() {
        _hasAvatar = false;
        _imageUrl = null;
      });
      return;
    }

    setState(() => _hasAvatar = true);

    final avatarId = active['avatar_id'] as String;

    final libRes = await Supabase.instance.client
        .from('kid_avatar_library')
        .select('points_current')
        .eq('kid_id', widget.kidId)
        .eq('avatar_id', avatarId)
        .maybeSingle();

    // Én kilde til sandhed for udvikling: total point (samme som task completion).
    final points = libRes != null
        ? AlfamonEvolution.pointsFromJson(libRes['points_current'])
        : AlfamonEvolution.pointsFromJson(active['points_current']);

    final avatarRes = await Supabase.instance.client
        .from('avatars')
        .select('name,letter')
        .eq('id', avatarId)
        .single();

    final stagesRes = await Supabase.instance.client
        .from('avatar_stages')
        .select('stage_index')
        .eq('avatar_id', avatarId)
        .order('stage_index');

    final stages = stagesRes as List;
    final sorted = AlfamonEvolution.sortedStageIndicesFromRows(stages);
    final currentStage = AlfamonEvolution.stageIndexFromPoints(points, sorted);

    final stageData = await Supabase.instance.client
        .from('avatar_stages')
        .select('image_url')
        .eq('avatar_id', avatarId)
        .eq('stage_index', currentStage)
        .maybeSingle();

    setState(() {
      _avatarName = avatarRes['name'] as String? ?? 'Alfamon';
      _currentStage = currentStage;
      _pointsTotal = points;
      _imageUrl = stageData?['image_url'] as String?;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAvatar) {
      return GestureDetector(
        onTap: () => context.go('/kid/alfamons/${widget.kidId}'),
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black54, width: 2),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_books, size: 64),
              SizedBox(height: 12),
              Text(
                'Vælg en Alfamon under «Alfamons» og giv guldmønter for at udvikle den',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }

    const sidePadding = 10.0;
    const textAreaHeight = 168.0;
    final maxH = (widget.maxHeight != null && widget.maxHeight!.isFinite)
        ? widget.maxHeight!
        : 400.0;
    final maxW = (widget.maxWidth != null && widget.maxWidth!.isFinite)
        ? widget.maxWidth!
        : 400.0;
    final availHeight = maxH - textAreaHeight;
    final availWidth = maxW - sidePadding * 2;
    final imageSize = (availHeight < availWidth ? availHeight : availWidth)
        .clamp(80.0, 400.0);

    final barPoints = _pointsTotal.clamp(0, AlfamonEvolution.maxProgressPoints);
    final pointsLabel = _pointsTotal > AlfamonEvolution.maxProgressPoints
        ? '${AlfamonEvolution.maxProgressPoints} / ${AlfamonEvolution.maxProgressPoints} guldmønter brugt (maks. · $_pointsTotal i alt på denne Alfamon)'
        : '$_pointsTotal / ${AlfamonEvolution.maxProgressPoints} guldmønter på denne Alfamon';

    return GestureDetector(
      onTap: () => context.go('/kid/alfamons/${widget.kidId}'),
      child: SizedBox(
        width: imageSize + sidePadding * 2,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: sidePadding, vertical: 10),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black54, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasAvatar)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _imageUrl != null && _imageUrl!.isNotEmpty
                      ? AssetOrNetworkImage(
                          key: ValueKey('${_imageUrl}_$_currentStage'),
                          src: _imageUrl!,
                          width: imageSize,
                          height: imageSize,
                          fit: BoxFit.cover,
                        )
                      : Icon(Icons.person, size: imageSize),
                )
              else
                Icon(Icons.person, size: imageSize),
              const SizedBox(height: 12),
              Text(
                _avatarName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              AlfamonEvolutionProgressBar(points: barPoints),
              const SizedBox(height: 4),
              Text(
                pointsLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
