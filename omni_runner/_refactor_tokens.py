#!/usr/bin/env python3
"""Batch-replace hardcoded Colors, EdgeInsets, and BorderRadius with DesignTokens."""

import re
import os

base_dir = '/home/usuario/project-running/omni_runner/lib/presentation/screens/'
import_line = "import 'package:omni_runner/core/theme/design_tokens.dart';"

files = [
    'challenge_create_screen.dart',
    'challenge_details_screen.dart',
    'challenge_invite_screen.dart',
    'challenge_join_screen.dart',
    'challenge_result_screen.dart',
    'challenges_list_screen.dart',
    'coaching_group_details_screen.dart',
    'friend_profile_screen.dart',
    'friends_activity_feed_screen.dart',
    'friends_screen.dart',
    'group_details_screen.dart',
    'group_events_screen.dart',
    'group_evolution_screen.dart',
    'group_members_screen.dart',
    'group_rankings_screen.dart',
    'groups_screen.dart',
    'invite_friends_screen.dart',
    'invite_qr_screen.dart',
    'join_assessoria_screen.dart',
    'partner_assessorias_screen.dart',
    'streaks_leaderboard_screen.dart',
    'leaderboards_screen.dart',
    'league_screen.dart',
    'matchmaking_screen.dart',
    'coach_insights_screen.dart',
]

spacing_map = {
    '4': 'DesignTokens.spacingXs',
    '8': 'DesignTokens.spacingSm',
    '16': 'DesignTokens.spacingMd',
    '24': 'DesignTokens.spacingLg',
    '32': 'DesignTokens.spacingXl',
    '48': 'DesignTokens.spacingXxl',
}

radius_map = {
    '8': 'DesignTokens.radiusSm',
    '12': 'DesignTokens.radiusMd',
    '16': 'DesignTokens.radiusLg',
    '24': 'DesignTokens.radiusXl',
}


def add_import(content):
    if import_line in content:
        return content
    lines = content.split('\n')
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.strip().startswith('import '):
            last_import_idx = i
    if last_import_idx >= 0:
        lines.insert(last_import_idx + 1, import_line)
    return '\n'.join(lines)


def replace_colors(content):
    # --- shade variants (most specific first) ---
    grey_shade_map = {
        '50': 'DesignTokens.borderSubtle',
        '100': 'DesignTokens.borderSubtle',
        '200': 'DesignTokens.border',
        '300': 'DesignTokens.border',
        '400': 'DesignTokens.textMuted',
        '500': 'DesignTokens.textMuted',
        '600': 'DesignTokens.textSecondary',
        '700': 'DesignTokens.textSecondary',
        '800': 'DesignTokens.textPrimary',
        '900': 'DesignTokens.textPrimary',
    }
    for shade, token in grey_shade_map.items():
        content = content.replace(f'Colors.grey.shade{shade}', token)
        content = content.replace(f'Colors.grey[{shade}]', token)

    color_shades = [
        ('Colors.orange.shade', 'DesignTokens.warning'),
        ('Colors.amber.shade', 'DesignTokens.warning'),
        ('Colors.green.shade', 'DesignTokens.success'),
        ('Colors.blue.shade', 'DesignTokens.primary'),
        ('Colors.red.shade', 'DesignTokens.error'),
        ('Colors.brown.shade', 'DesignTokens.warning'),
    ]
    for prefix, token in color_shades:
        for shade in ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900']:
            content = content.replace(f'{prefix}{shade}', token)

    # Named compound colors (before plain)
    content = re.sub(r'\bColors\.deepOrange\b', 'DesignTokens.warning', content)
    content = re.sub(r'\bColors\.deepPurple\b', 'DesignTokens.info', content)
    content = re.sub(r'\bColors\.amberAccent\b', 'DesignTokens.warning', content)

    # Plain colors
    plain_map = [
        (r'\bColors\.orange\b', 'DesignTokens.warning'),
        (r'\bColors\.amber\b', 'DesignTokens.warning'),
        (r'\bColors\.green\b', 'DesignTokens.success'),
        (r'\bColors\.blue\b', 'DesignTokens.primary'),
        (r'\bColors\.red\b', 'DesignTokens.error'),
        (r'\bColors\.teal\b', 'DesignTokens.info'),
        (r'\bColors\.cyan\b', 'DesignTokens.info'),
        (r'\bColors\.purple\b', 'DesignTokens.info'),
        (r'\bColors\.indigo\b', 'DesignTokens.primary'),
        (r'\bColors\.grey\b', 'DesignTokens.textMuted'),
    ]
    for pattern, token in plain_map:
        content = re.sub(pattern, token, content)

    # .withOpacity → .withValues(alpha:)
    content = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', content)

    # Specific hex colors
    content = content.replace('Color(0xFFFFA000)', 'DesignTokens.warning')

    return content


def replace_edgeinsets(content):
    # EdgeInsets.all(N)
    for val, token in spacing_map.items():
        content = re.sub(
            rf'(EdgeInsets\.all\(\s*){val}(?:\.0)?(\s*\))',
            rf'\g<1>{token}\2',
            content,
        )

    # Named params: horizontal, vertical, left, right, top, bottom
    for val, token in spacing_map.items():
        content = re.sub(
            rf'((?:horizontal|vertical|left|right|top|bottom):\s*){val}(?:\.0)?(?=\s*[,\)])',
            rf'\g<1>{token}',
            content,
        )

    # EdgeInsets.fromLTRB positional args
    def _replace_fromLTRB(m):
        args = m.group(1).split(',')
        new_args = []
        for arg in args:
            s = arg.strip()
            norm = s.rstrip('0').rstrip('.') if '.' in s else s
            new_args.append(spacing_map.get(norm, s))
        return f'EdgeInsets.fromLTRB({", ".join(new_args)})'

    content = re.sub(r'EdgeInsets\.fromLTRB\(([^)]+)\)', _replace_fromLTRB, content)
    return content


def replace_border_radius(content):
    for val, token in radius_map.items():
        content = re.sub(
            rf'(BorderRadius\.circular\(\s*){val}(?:\.0)?(\s*\))',
            rf'\g<1>{token}\2',
            content,
        )
    return content


changed = 0
for fname in files:
    filepath = os.path.join(base_dir, fname)
    with open(filepath, 'r') as f:
        original = f.read()

    content = add_import(original)
    content = replace_colors(content)
    content = replace_edgeinsets(content)
    content = replace_border_radius(content)

    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        changed += 1
        print(f'  OK  {fname}')
    else:
        print(f'  --  {fname} (no changes)')

print(f'\nDone: {changed}/{len(files)} files modified.')
