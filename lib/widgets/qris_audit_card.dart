import 'package:flutter/material.dart';

import '../services/qris_audit_service.dart';
import '../theme/app_theme.dart';

/// Kartu hasil audit QRIS: skor, kesimpulan, dan daftar temuan.
class QrisAuditCard extends StatefulWidget {
  const QrisAuditCard({
    super.key,
    required this.result,
    this.initiallyExpanded = false,
  });

  final QrisAuditResult result;
  final bool initiallyExpanded;

  @override
  State<QrisAuditCard> createState() => _QrisAuditCardState();
}

class _QrisAuditCardState extends State<QrisAuditCard> {
  late bool _expanded = widget.initiallyExpanded;

  static const int _collapsedCount = 2;

  Color _accent(bool isDark) => switch (widget.result.verdict) {
        AuditVerdict.safe => AppTheme.qrisGreen,
        AuditVerdict.review => AppTheme.qrAmber,
        AuditVerdict.suspicious =>
          isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C),
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = widget.result;
    final accent = _accent(isDark);
    final findings = r.sortedFindings;
    final visible =
        _expanded ? findings : findings.take(_collapsedCount).toList();
    final hidden = findings.length - visible.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: accent.withOpacity(isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ScoreBadge(score: r.score, accent: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.headline,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppTheme.inkColor(isDark),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(r),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: AppTheme.mutedColor(isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (findings.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final f in visible) _FindingRow(finding: f, isDark: isDark),
            if (hidden > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = true),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Lihat $hidden temuan lain',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (_expanded && findings.length > _collapsedCount)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Sembunyikan',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mutedColor(isDark),
                    ),
                  ),
                ),
              ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.verified_rounded, size: 14, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Semua pemeriksaan lolos: struktur, CRC, NMID, dan mata uang.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: AppTheme.mutedColor(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(QrisAuditResult r) {
    final parts = <String>[
      if (r.crcValid) 'CRC valid' else 'CRC tidak valid',
      r.isDynamic ? 'Dinamis' : 'Statis',
      if (r.nmid.isNotEmpty) 'NMID ${r.nmid}',
    ];
    return parts.join(' · ');
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score, required this.accent});

  final int score;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 4,
              backgroundColor: accent.withOpacity(0.18),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.inkColor(isDark),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding, required this.isDark});

  final AuditFinding finding;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (finding.severity) {
      AuditSeverity.critical => (
          Icons.error_outline_rounded,
          isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C),
        ),
      AuditSeverity.warning => (Icons.warning_amber_rounded, AppTheme.qrAmber),
      AuditSeverity.info => (
          Icons.info_outline_rounded,
          AppTheme.mutedColor(isDark),
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finding.title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkColor(isDark),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  finding.detail,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: AppTheme.mutedColor(isDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
