import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/kid_parent_admin_corner.dart';
import 'widgets/kid_session_nav_button.dart';

const _achievementDefinitions = {
  'first_task': ('Første opgave', 'Færdiggjort din første opgave', '🎯'),
  'tasks_10': ('Første 10 opgaver', 'Færdiggjort 10 opgaver', '⭐'),
  'tasks_100': ('Første 100 opgaver', 'Færdiggjort 100 opgaver', '👑'),
  'streak_7': ('7 Dages streak', '7 dages streak', '🔥'),
  'streak_14': ('14 Dages streak', '14 dages streak', '💪'),
  'streak_30': ('30 Dages streak', '30 dages streak', '🏆'),
  'first_game_win': ('Første vundet spil', 'Vundet dit første spil', '🎮'),
  'games_10_wins': ('10 vundne spil', 'Vundet 10 spil', '🏅'),
  'avatars_10': ('Alfamon mester', '10 Alfamons fuldt udviklet', '🌟'),
  'alphabet_complete': ('Hele alfabetet', 'Alle 29 bogstaver låst op', '🔤'),
};

class KidAchievementsScreen extends StatefulWidget {
  final String kidId;

  const KidAchievementsScreen({super.key, required this.kidId});

  @override
  State<KidAchievementsScreen> createState() => _KidAchievementsScreenState();
}

class _KidAchievementsScreenState extends State<KidAchievementsScreen> {
  List<Map<String, dynamic>> _achievements = [];
  bool _tableExists = true;
  bool _loading = true;
  int _totalTasks = 0;
  int _totalPoints = 0;
  int _currentStreak = 0;
  int _completedAvatars = 0;
  int _gameWins = 0;
  int _unlockedLetters = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await Future.wait([_loadAchievements(), _loadStats()]);
    if (mounted) {
      await _checkAndAwardAchievements();
      setState(() => _loading = false);
    }
  }

  Future<void> _loadAchievements() async {
    try {
      final res = await Supabase.instance.client
          .from('achievements')
          .select('*')
          .eq('kid_id', widget.kidId)
          .order('unlocked_at', ascending: false);

      setState(() {
        _tableExists = true;
        _achievements = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('does not exist') ||
          msg.contains('relation') ||
          msg.contains('42P01') ||
          msg.contains('PGRST116')) {
        setState(() {
          _tableExists = false;
          _achievements = [];
        });
      } else {
        setState(() => _achievements = []);
      }
    }
  }

  Future<void> _loadStats() async {
    final client = Supabase.instance.client;

    // Færdige opgaver
    final taskRes = await client
        .from('task_instances')
        .select('id')
        .eq('kid_id', widget.kidId)
        .inFilter('status', ['completed', 'approved']);
    final taskCount = (taskRes as List).length;

    // Samlede point
    final ledgerRes = await client
        .from('points_ledger')
        .select('delta_points')
        .eq('kid_id', widget.kidId);
    int totalPoints = 0;
    for (final e in ledgerRes as List) {
      totalPoints += (e['delta_points'] as num?)?.toInt() ?? 0;
    }

    // Streak
    final instancesRes = await client
        .from('task_instances')
        .select('date')
        .eq('kid_id', widget.kidId)
        .inFilter('status', ['completed', 'approved'])
        .order('date', ascending: false);

    final completionDates = <String>{};
    for (final i in instancesRes as List) {
      completionDates.add(i['date'] as String);
    }

    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);
    int streakCount = 0;
    int startDay = completionDates.contains(todayStr) ? 0 : 1;
    for (var i = startDay; i < 365; i++) {
      final d = today.subtract(Duration(days: i));
      final dateStr = d.toIso8601String().substring(0, 10);
      if (completionDates.contains(dateStr)) {
        streakCount++;
      } else {
        break;
      }
    }

    // Færdige Alfamons (kid_avatar_history)
    final historyRes = await client
        .from('kid_avatar_history')
        .select('id')
        .eq('kid_id', widget.kidId);
    final completedAvatars = (historyRes as List).length;

    // Vundne spil (game_wins kan mangle)
    int gameWins = 0;
    try {
      final winsRes = await client
          .from('game_wins')
          .select('id')
          .eq('kid_id', widget.kidId);
      gameWins = (winsRes as List).length;
    } catch (_) {}

    // Låste op bogstaver
    final unlockedRes = await client
        .from('kid_unlocked_alphamons')
        .select('avatar_id,avatars(letter)')
        .eq('kid_id', widget.kidId);

    final letters = <String>{};
    for (final u in unlockedRes as List) {
      final av = u['avatars'];
      if (av != null) {
        final letter = (av is Map ? av['letter'] : null) as String?;
        if (letter != null && letter.isNotEmpty) {
          letters.add(letter.toLowerCase());
        }
      }
    }

    setState(() {
      _totalTasks = taskCount;
      _totalPoints = totalPoints;
      _currentStreak = streakCount;
      _completedAvatars = completedAvatars;
      _gameWins = gameWins;
      _unlockedLetters = letters.length;
    });
  }

  Future<void> _checkAndAwardAchievements() async {
    if (!_tableExists) return;

    final client = Supabase.instance.client;
    final allLettersUnlocked = _unlockedLetters >= 29;

    final checks = [
      ('first_task', _totalTasks >= 1),
      ('tasks_10', _totalTasks >= 10),
      ('tasks_100', _totalTasks >= 100),
      ('streak_7', _currentStreak >= 7),
      ('streak_14', _currentStreak >= 14),
      ('streak_30', _currentStreak >= 30),
      ('first_game_win', _gameWins >= 1),
      ('games_10_wins', _gameWins >= 10),
      ('avatars_10', _completedAvatars >= 10),
      ('alphabet_complete', allLettersUnlocked),
    ];

    for (final check in checks) {
      if (!check.$2) continue;

      final existing = await client
          .from('achievements')
          .select('id')
          .eq('kid_id', widget.kidId)
          .eq('achievement_type', check.$1)
          .maybeSingle();

      if (existing != null) continue;

      try {
        await client.from('achievements').insert({
          'kid_id': widget.kidId,
          'achievement_type': check.$1,
          'metadata': {
            'totalTasks': _totalTasks,
            'totalPoints': _totalPoints,
            'currentStreak': _currentStreak,
            'completedAvatars': _completedAvatars,
            'gameWins': _gameWins,
            'unlockedLetters': _unlockedLetters,
          },
        });
        await _loadAchievements();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;
    final bgAsset = isTablet
        ? 'assets/baggrund_roedipad.svg'
        : 'assets/baggrund_roediphone.svg';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: SvgPicture.asset(bgAsset, fit: BoxFit.cover),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Præstationer',
                    style: TextStyle(
                      fontSize: isTablet ? 28 : 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Se alle dine opnåede præstationer! 🏆',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (!_tableExists) _buildTableMissingWarning(),
                              if (_tableExists && _achievements.isEmpty)
                                _buildStatsCard(),
                              if (_tableExists) ...[
                                const SizedBox(height: 16),
                                ..._achievementDefinitions.entries.map((e) {
                                  final type = e.key;
                                  final def = e.value;
                                  final unlocked = _achievements
                                      .any((a) => a['achievement_type'] == type);
                                  final unlockedAt = () {
                                    final list = _achievements
                                        .where((a) => a['achievement_type'] == type)
                                        .map((a) => a['unlocked_at'])
                                        .toList();
                                    return list.isEmpty ? null : list.first;
                                  }();
                                  return _AchievementCard(
                                    name: def.$1,
                                    description: def.$2,
                                    emoji: def.$3,
                                    unlocked: unlocked,
                                    unlockedAt: unlockedAt != null
                                        ? DateTime.tryParse(unlockedAt.toString())
                                        : null,
                                  );
                                }),
                              ],
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: KidSessionNavButton(kidId: widget.kidId),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: const KidParentAdminCornerButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildTableMissingWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9C433).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black54, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚠️ Tabel mangler',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Achievements-tabellen findes ikke i databasen. Kør SQL i Supabase:',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SelectableText(
              'create table if not exists public.achievements (\n'
              '  id uuid primary key default gen_random_uuid(),\n'
              '  kid_id uuid references public.kids(id) on delete cascade,\n'
              '  achievement_type text not null,\n'
              '  unlocked_at timestamptz default now(),\n'
              '  metadata jsonb,\n'
              '  unique (kid_id, achievement_type)\n'
              ');\n'
              'create index if not exists achievements_kid_idx on public.achievements(kid_id);',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white30, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Statistik',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _StatChip('Færdige opgaver', '$_totalTasks'),
              _StatChip('Samlet point', '$_totalPoints'),
              _StatChip('Streak', '$_currentStreak dage'),
              _StatChip('Færdige Alfamons', '$_completedAvatars'),
              _StatChip('Vundne spil', '$_gameWins'),
              _StatChip('Bogstaver', '$_unlockedLetters/29'),
            ],
          ),
        ],
      ),
    );
  }

}

class _AchievementCard extends StatelessWidget {
  final String name;
  final String description;
  final String emoji;
  final bool unlocked;
  final DateTime? unlockedAt;

  const _AchievementCard({
    required this.name,
    required this.description,
    required this.emoji,
    required this.unlocked,
    this.unlockedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: unlocked
            ? const Color(0xFFF9C433).withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked ? Colors.amber : Colors.white24,
          width: unlocked ? 2 : 1,
        ),
        boxShadow: unlocked
            ? [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Text(
            emoji,
            style: TextStyle(
              fontSize: 40,
              color: unlocked ? null : Colors.grey,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: unlocked
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: unlocked
                        ? Colors.white.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                if (unlocked && unlockedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Opnået: ${_formatDate(unlockedAt!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (unlocked)
            const Icon(Icons.check_circle, color: Colors.amber, size: 28),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day}. ${_month(d.month)} ${d.year}';
  }

  String _month(int m) {
    const months = [
      'jan', 'feb', 'mar', 'apr', 'maj', 'jun',
      'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
    ];
    return months[m - 1];
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: TextStyle(
        fontSize: 13,
        color: Colors.white.withValues(alpha: 0.9),
      ),
    );
  }
}

