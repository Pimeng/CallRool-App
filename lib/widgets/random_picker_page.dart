import 'dart:math';

import 'package:flutter/material.dart';

import '../models/attendance.dart';

/// 抽签候选人快照。
///
/// 只传递必要的只读信息，避免页面持有会变化的 [Person] 引用。
class RandomCandidate {
  const RandomCandidate({required this.id, required this.name});

  final int id;
  final String name;
}

/// 随机点人（抽签）二级页面。
///
/// 候选人由调用方筛选后传入（仅正常到勤人员），本页面负责：
/// - 单次或批量抽取；
/// - 可选「不重复抽取」，在本轮内排除已抽中的人；
/// - 展示本轮抽取历史并支持重置。
class RandomPickerPage extends StatefulWidget {
  const RandomPickerPage({super.key, required this.candidates, this.random});

  /// 候选人列表，调用方需保证仅包含正常到勤人员。
  final List<RandomCandidate> candidates;

  /// 可注入的随机源，便于测试时固定结果。
  final Random? random;

  @override
  State<RandomPickerPage> createState() => _RandomPickerPageState();
}

class _RandomPickerPageState extends State<RandomPickerPage>
    with SingleTickerProviderStateMixin {
  static const _spinDuration = Duration(milliseconds: 2600);

  /// 滚动期间的名字切换次数。
  ///
  /// 与 [_handleTick] 里的 easeOutCubic 配合：换名频率 ∝ 3(1-t)²，
  /// 前段约每帧换一次（快的模糊感），后段越来越慢，
  /// 最后一步会停住约 0.65s，停留片刻后才揭晓结果。
  static const _rollSteps = 60;

  late final Random _random;
  late final AnimationController _controller;

  /// 本轮已抽中的人（按抽取顺序），启用不重复时用于排除。
  final List<RandomCandidate> _history = [];
  final Set<int> _historyIds = {};

  /// 本次抽取结果，动画结束后填充。
  List<RandomCandidate> _results = const [];

  /// 本次抽签在动画开始前就已确定的名单。
  List<RandomCandidate> _pending = const [];

  /// 滚动过程中展示的姓名。
  String _displayName = '';

  /// 上次换名对应的步进值，用于判断何时切换姓名。
  int _lastStep = -1;

  int _batchCount = 1;
  bool _noRepeat = true;

  /// 是否播放滚动抽签动画；关闭后点击抽取会直接揭晓结果。
  bool _playAnimation = true;
  bool _spinning = false;

  @override
  void initState() {
    super.initState();
    _random = widget.random ?? Random();
    _controller = AnimationController(vsync: this, duration: _spinDuration);
    _controller
      ..addListener(_handleTick)
      ..addStatusListener(_handleStatus);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTick)
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  /// 当前可抽签的人：启用不重复时排除本轮已抽中的人。
  List<RandomCandidate> get _pool {
    if (!_noRepeat) return widget.candidates;
    return widget.candidates
        .where((candidate) => !_historyIds.contains(candidate.id))
        .toList(growable: false);
  }

  int get _maxCount => max(1, _pool.length);

  int get _effectiveCount => _batchCount.clamp(1, _maxCount);

  void _handleCountChanged(int value) {
    if (_spinning) return;
    setState(() => _batchCount = value.clamp(1, _maxCount));
  }

  void _handleNoRepeatChanged(bool value) {
    setState(() {
      _noRepeat = value;
      final maxCount = max(1, _pool.length);
      if (_batchCount > maxCount) _batchCount = maxCount;
    });
  }

  void _handlePlayAnimationChanged(bool value) {
    setState(() => _playAnimation = value);
  }

  /// 揭晓本轮结果：写入结果与本轮历史，并清空待定名单。
  ///
  /// 播放动画与不播放动画两条路径共用，保证结果处理完全一致。
  void _commitPending() {
    _spinning = false;
    _results = _pending;
    for (final candidate in _pending) {
      if (_historyIds.add(candidate.id)) _history.add(candidate);
    }
    _pending = const [];
    // 不重复模式下抽空了候选人，需要把人数收敛回可用范围。
    _batchCount = _batchCount.clamp(1, _maxCount);
  }

  void _startDraw() {
    final pool = List<RandomCandidate>.of(_pool);
    if (_spinning || pool.isEmpty) return;
    pool.shuffle(_random);
    _pending = pool.take(_effectiveCount).toList(growable: false);

    if (!_playAnimation) {
      // 关闭动画时直接揭晓结果，不做滚动。
      setState(_commitPending);
      return;
    }

    _results = const [];
    _spinning = true;
    _lastStep = -1;
    _controller.forward(from: 0);
    setState(() {});
  }

  void _handleTick() {
    if (!mounted) return;
    // 滚动展示的是候选池，而不是已经抽出的中奖者，
    // 否则单抽时名字会一直是同一个人，看起来像没在随机。
    final source = _pool.isNotEmpty ? _pool : widget.candidates;
    if (source.isEmpty) return;

    // easeOutCubic：换名频率 ∝ 3(1-t)²，从快到慢且末段趋近于 0，
    // 于是越到后面换得越慢、最后一步停得越久，形成“慢慢停下来”的手感。
    final progress = _controller.value;
    final eased = 1 - pow(1 - progress, 3);
    final step = (eased * _rollSteps).floor();
    if (step == _lastStep) return;
    _lastStep = step;

    // 最后一步直接停在真正的中奖者上：慢下来之后“才到”的就是结果本人，
    // 避免最后又停在某个无关的名字上。批量抽取时中奖者不唯一，继续随机滚动。
    final settled = _pending.length == 1 && step >= _rollSteps - 1;
    setState(() {
      _displayName = settled ? _pending.first.name : _nextName(source);
    });
  }

  /// 随机取一个与当前显示不同的名字，避免出现“卡住不动”的错觉。
  String _nextName(List<RandomCandidate> source) {
    if (source.length == 1) return source.first.name;
    String next;
    do {
      next = source[_random.nextInt(source.length)].name;
    } while (next == _displayName);
    return next;
  }

  void _handleStatus(AnimationStatus status) {
    if (!mounted || status != AnimationStatus.completed) return;
    setState(_commitPending);
  }

  void _resetRound() {
    if (_spinning) return;
    setState(() {
      _history.clear();
      _historyIds.clear();
      _results = const [];
      _pending = const [];
      _batchCount = _batchCount.clamp(1, _maxCount);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presentColor = AttendanceStatus.present.adaptiveColor(context);
    final pool = _pool;
    final exhausted = pool.isEmpty;
    final total = widget.candidates.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('随机点人'),
        actions: [
          if (_history.isNotEmpty)
            TextButton(
              onPressed: _spinning ? null : _resetRound,
              child: const Text('重置本轮'),
            ),
        ],
      ),
      body: SafeArea(
        child: total == 0
            ? const _EmptyCandidates()
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _buildSummary(scheme, presentColor, total, pool.length),
                      const SizedBox(height: 12),
                      _buildOptionsCard(scheme, presentColor, exhausted),
                      const SizedBox(height: 16),
                      _buildResultPanel(scheme, presentColor),
                      if (_history.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _buildHistory(scheme),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: total == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _spinning || exhausted ? null : _startDraw,
                        icon: const Icon(Icons.casino_rounded, size: 20),
                        label: Text(
                          exhausted ? '已全部抽完' : '抽取 $_effectiveCount 人',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// 人员概况不再单独占一张卡片，压缩成一行副标题即可。
  Widget _buildSummary(
    ColorScheme scheme,
    Color presentColor,
    int total,
    int remaining,
  ) {
    return Row(
      key: const ValueKey('random-picker-summary'),
      children: [
        Icon(Icons.verified_user_rounded, color: presentColor, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '正常到勤 $total 人，剩余可抽 $remaining 人',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsCard(
    ColorScheme scheme,
    Color presentColor,
    bool exhausted,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _noRepeat,
            onChanged: _spinning ? null : _handleNoRepeatChanged,
            secondary: Icon(Icons.repeat_rounded, color: presentColor),
            title: const Text('不重复抽取'),
            subtitle: const Text('本轮内不会再次抽到已抽中的人'),
          ),
          const Divider(height: 1, indent: 56),
          SwitchListTile(
            value: _playAnimation,
            onChanged: _spinning ? null : _handlePlayAnimationChanged,
            secondary: Icon(Icons.slow_motion_video_rounded, color: presentColor),
            title: const Text('播放抽签动画'),
            subtitle: const Text('关闭后点击直接显示抽取结果'),
          ),
          const Divider(height: 1, indent: 56),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(Icons.groups_rounded, color: scheme.onSurfaceVariant),
                const SizedBox(width: 16),
                const Expanded(child: Text('抽取人数')),
                IconButton.filledTonal(
                  tooltip: '减少人数',
                  onPressed: _spinning || _effectiveCount <= 1
                      ? null
                      : () => _handleCountChanged(_effectiveCount - 1),
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    '$_effectiveCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '增加人数',
                  onPressed: _spinning || _effectiveCount >= _maxCount
                      ? null
                      : () => _handleCountChanged(_effectiveCount + 1),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          if (exhausted)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已抽完全部正常到勤人员，可重置本轮后继续。',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 抽签前后共享同一套排版（字号、留白、面板最小高度），
  /// 这样滚动状态与结果状态之间切换时不会出现字号跳变或框体伸缩。
  static const _nameFontSize = 36.0;
  static const _panelGap = 16.0;
  static const _panelFooterHeight = 22.0;
  static const _panelMinHeight = 146.0;

  Widget _panelShell({
    required List<Widget> children,
    required Color background,
    required Color borderColor,
    Key? key,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: _panelMinHeight),
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }

  Widget _panelName(String text, {required Color color, Key? key}) {
    return Text(
      text,
      key: key,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: _nameFontSize,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    );
  }

  /// 固定高度的底部区域：滚动时放进度条，结束后放“恭喜被抽中”，
  /// 高度一致才能让面板在两种状态间保持同样的尺寸。
  Widget _panelFooter(Widget child) {
    return SizedBox(
      height: _panelFooterHeight,
      child: Center(child: child),
    );
  }

  /// 结果面板统一的底部文案：奖杯图标 + 一行说明。
  Widget _resultFooter(String text, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.emoji_events_rounded, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 结果面板里展示姓名的小标签，单人/多人共用同一套样式。
  ///
  /// 姓名只靠底色区分，不再描边——外层已经有面板边框，
  /// 标签再加一圈框会显得层层套框。
  Widget _resultChip(String name, Color presentColor) {
    return Chip(
      label: Text(name),
      labelStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: presentColor,
      ),
      backgroundColor: presentColor.withValues(alpha: .14),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Widget _buildResultPanel(ColorScheme scheme, Color presentColor) {
    if (_spinning) {
      return _panelShell(
        background: scheme.surfaceContainerHighest,
        borderColor: scheme.outlineVariant,
        children: [
          _panelName(
            _displayName,
            key: const ValueKey('random-picker-rolling-name'),
            color: scheme.onSurface,
          ),
          const SizedBox(height: _panelGap),
          _panelFooter(const LinearProgressIndicator(minHeight: 4)),
        ],
      );
    }

    final results = _results;
    if (results.isEmpty) {
      return _panelShell(
        background: presentColor.withValues(alpha: .08),
        borderColor: scheme.outlineVariant,
        children: [
          Icon(Icons.casino_outlined, size: 30, color: presentColor),
          const SizedBox(height: 10),
          Text(
            '点击下方按钮开始抽签',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    if (results.length == 1) {
      return _panelShell(
        key: const ValueKey('random-picker-result-panel'),
        background: AttendanceStatus.present.adaptiveSoftColor(context),
        borderColor: presentColor,
        children: [
          _panelName(
            results.single.name,
            key: const ValueKey('random-picker-result-name'),
            color: presentColor,
          ),
          const SizedBox(height: _panelGap),
          _panelFooter(_resultFooter('恭喜被抽中', presentColor)),
        ],
      );
    }

    // 多人抽取沿用同一个结果面板：同样的底色、边框、留白与底部文案，
    // 只是把姓名换成一组标签，避免单人和多人看起来像两套界面。
    return _panelShell(
      key: const ValueKey('random-picker-result-panel'),
      background: AttendanceStatus.present.adaptiveSoftColor(context),
      borderColor: presentColor,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final candidate in results)
              _resultChip(candidate.name, presentColor),
          ],
        ),
        const SizedBox(height: _panelGap),
        _panelFooter(_resultFooter('抽中 ${results.length} 人', presentColor)),
      ],
    );
  }

  Widget _buildHistory(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '本轮已抽中 ${_history.length} 人',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        // 姓名自身已有标签底色，不再额外套一层外框。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < _history.length; index++)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text('${index + 1}. ${_history[index].name}'),
                labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                backgroundColor: scheme.surfaceContainerHighest,
                side: BorderSide(color: scheme.outlineVariant),
              ),
          ],
        ),
      ],
    );
  }
}

class _EmptyCandidates extends StatelessWidget {
  const _EmptyCandidates();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sentiment_dissatisfied_rounded,
              size: 42,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            const Text(
              '没有可抽签的人员',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '只有标记为「正常」的人员才会参与抽签，请先完成点名。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
