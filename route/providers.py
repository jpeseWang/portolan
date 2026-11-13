"""Read-only subscription quota adapters. Credentials never leave the provider adapter."""
from __future__ import annotations
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import time
from datetime import datetime, timezone

HOME = Path.home()

class ProviderError(Exception):
    def __init__(self, state, message):
        super().__init__(message)
        self.state = state


def load_json(path):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        raise ProviderError('login_required', 'Chưa tìm thấy thông tin đăng nhập CLI.') from None
    except (ValueError, OSError):
        raise ProviderError('credential_error', 'Không đọc được thông tin đăng nhập CLI.') from None


def request(url, token=None, body=None, headers=None):
    # curl uses the macOS trust store. Secrets travel over stdin, never process arguments.
    config = ['silent', 'show-error', 'max-time = 20', 'connect-timeout = 8',
              'max-redirs = 0', 'proto = "=https"', f'url = {json.dumps(url)}',
              'write-out = "\\n%{http_code}"', 'header = "Accept: application/json"']
    if token:
        config.append(f'header = {json.dumps("Authorization: Bearer " + token)}')
    for key, value in (headers or {}).items():
        config.append(f'header = {json.dumps(key + ": " + value)}')
    if body is not None:
        config += ['header = "Content-Type: application/json"',
                   f'data = {json.dumps(json.dumps(body))}']
    try:
        result = subprocess.run(['/usr/bin/curl', '--config', '-'], input='\n'.join(config),
                                text=True, capture_output=True, timeout=25, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise ProviderError('network_error', 'Không kết nối được dịch vụ quota.') from None
    if result.returncode:
        raise ProviderError('network_error', 'Kết nối quota thất bại hoặc hết thời gian chờ.')
    payload, _, status = result.stdout.rpartition('\n')
    if status == '401':
        raise ProviderError('auth_expired', 'Đăng nhập đã hết hạn. Mở CLI và đăng nhập lại.')
    if status == '403':
        raise ProviderError('forbidden', 'Tài khoản hoặc token không được phép đọc quota này.')
    if status == '429':
        raise ProviderError('rate_limited', 'Dịch vụ quota giới hạn lượt đọc. Monitor sẽ thử lại sau.')
    if status != '200':
        raise ProviderError('provider_error', f'Dịch vụ quota trả HTTP {status or "unknown"}.')
    try:
        return json.loads(payload)
    except ValueError:
        raise ProviderError('invalid_response', 'Dịch vụ quota trả dữ liệu không nhận dạng được.') from None


def claims(token):
    try:
        part = token.split('.')[1]
        return json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
    except (ValueError, IndexError, TypeError):
        return {}


def percentage(value):
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or not 0 <= value <= 100:
        return None
    return round(max(0, min(100, value)), 2)


def timestamp(value):
    try:
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return datetime.fromtimestamp(value, timezone.utc).isoformat()
        if isinstance(value, str):
            return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc).isoformat()
    except (ValueError, OverflowError, OSError):
        pass
    return None


def window(label, remaining, reset=None, models=None):
    return {'label': label, 'remainingPercent': percentage(remaining),
            'resetsAt': timestamp(reset), 'models': models or []}


def claude_credentials():
    path = Path(os.environ.get('CLAUDE_CONFIG_DIR', str(HOME / '.claude'))) / '.credentials.json'
    if path.is_file():
        return load_json(path).get('claudeAiOauth', {})
    try:
        for service in claude_keychain_services():
            result = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', service, '-w'],
                                    capture_output=True, text=True, timeout=10, check=False)
            if result.returncode == 0:
                return json.loads(result.stdout).get('claudeAiOauth', {})
        raise ProviderError('login_required', 'Không đọc được đăng nhập Claude Code trong Keychain.')
    except (OSError, ValueError, subprocess.TimeoutExpired):
        raise ProviderError('credential_error', 'Không đọc được đăng nhập Claude Code.') from None


def claude_keychain_services(env=None):
    """Keychain items to try. With CLAUDE_CONFIG_DIR set, Claude Code stores the login under a name
    suffixed with a hash of that path; the plain name belongs to the default config and is another account."""
    env = os.environ if env is None else env
    cfg = env.get('CLAUDE_CONFIG_DIR')
    if not cfg:
        return ['Claude Code-credentials']
    names = []
    for path in (cfg, cfg.rstrip('/')):
        name = 'Claude Code-credentials-' + hashlib.sha256(path.encode()).hexdigest()[:8]
        if name not in names:
            names.append(name)
    return names


def claude_account_label():
    cfg = os.environ.get('CLAUDE_CONFIG_DIR')
    return 'Claude Code (%s)' % os.path.basename(cfg.rstrip('/')) if cfg else 'Claude Code (default config)'


def fetch_claude():
    auth = claude_credentials()
    token = auth.get('accessToken')
    if not token:
        raise ProviderError('login_required', 'Claude Code chưa đăng nhập bằng tài khoản thuê bao.')
    data = request('https://api.anthropic.com/api/oauth/usage', token,
                   headers={'anthropic-beta': 'oauth-2025-04-20'})
    labels = {'five_hour': '5 giờ', 'seven_day': 'Hàng tuần',
              'seven_day_sonnet': 'Sonnet · hàng tuần', 'seven_day_opus': 'Opus · hàng tuần',
              'seven_day_oauth_apps': 'OAuth apps · hàng tuần'}
    windows = []
    for key, label in labels.items():
        item = data.get(key)
        if isinstance(item, dict):
            used = percentage(item.get('utilization'))
            windows.append(window(label, None if used is None else 100 - used, item.get('resets_at')))
    return {'plan': auth.get('subscriptionType') or 'Claude subscription',
            'account': claude_account_label(), 'windows': windows,
            'source': 'Anthropic OAuth usage'}


def fetch_codex():
    auth = load_json(Path(os.environ.get('CODEX_HOME', str(HOME / '.codex'))) / 'auth.json')
    tokens = auth.get('tokens') or {}
    token = tokens.get('access_token')
    if not token:
        raise ProviderError('login_required', 'Codex chưa đăng nhập bằng ChatGPT. API key không có quota Plus.')
    headers = {'User-Agent': 'ALS-Quota/0.1'}
    if tokens.get('account_id'):
        headers['ChatGPT-Account-Id'] = tokens['account_id']
    data = request('https://chatgpt.com/backend-api/wham/usage', token, headers=headers)
    windows = []
    def add_limits(limits, prefix=''):
        if not isinstance(limits, dict):
            return
        for key, fallback in [('primary_window', 'Cửa sổ chính'), ('secondary_window', 'Hàng tuần')]:
            item = limits.get(key)
            if not isinstance(item, dict):
                continue
            seconds = item.get('limit_window_seconds')
            label = '5 giờ' if seconds == 18000 else 'Hàng tuần' if seconds == 604800 else fallback
            used = percentage(item.get('used_percent'))
            windows.append(window(prefix + label, None if used is None else 100 - used, item.get('reset_at')))
    add_limits(data.get('rate_limit'))
    for extra in data.get('additional_rate_limits') or []:
        if isinstance(extra, dict):
            add_limits(extra.get('rate_limit'), str(extra.get('limit_name') or extra.get('metered_feature') or 'Model') + ' · ')
    identity = claims(tokens.get('id_token', ''))
    return {'plan': data.get('plan_type') or 'ChatGPT', 'account': identity.get('email') or 'Đăng nhập Codex trên máy này',
            'windows': windows, 'source': 'ChatGPT Codex usage'}


def fetch_antigravity():
    import shutil
    binary = shutil.which('agy') or '/opt/homebrew/bin/agy'
    try:
        result = subprocess.run([binary, '--print', '/usage', '--output-format', 'json',
                                 '--print-timeout', '20s'], capture_output=True, text=True,
                                timeout=30, check=False)
    except FileNotFoundError:
        raise ProviderError('not_installed', 'Chưa tìm thấy Antigravity CLI (agy).') from None
    except (OSError, subprocess.TimeoutExpired):
        raise ProviderError('network_error', 'Antigravity CLI không trả quota trong30giây.') from None
    try:
        data = json.loads(result.stdout)
    except ValueError:
        raise ProviderError('login_required', 'Mở agy, kiểm tra đăng nhập rồi thử lại.') from None
    command = data.get('command') or {}
    if (result.returncode or data.get('status') != 'SUCCESS' or command.get('name') != 'usage'
            or data.get('num_turns') != 0 or (data.get('usage') or {}).get('total_tokens') != 0):
        raise ProviderError('provider_error', 'CLI không trả báo cáo /usage hợp lệ; không hiển thị số liệu suy đoán.')
    return {'account': 'Tài khoản đang đăng nhập trong agy', 'plan': 'Antigravity',
            'windows': parse_antigravity(command.get('data') or {}),
            'source': 'agy /usage · 0 lượt hội thoại, 0 token'}


def parse_antigravity(data):
    windows = []
    for group in data.get('groups') or []:
        if not isinstance(group, dict):
            continue
        for bucket in group.get('buckets') or []:
            if not isinstance(bucket, dict) or bucket.get('disabled'):
                continue
            fraction = bucket.get('remaining_fraction', bucket.get('remainingFraction'))
            remaining = percentage(fraction * 100) if isinstance(fraction, (int, float)) and not isinstance(fraction, bool) else None
            label = str(group.get('name') or group.get('displayName') or 'Model group')
            label += ' · ' + ('hàng tuần' if bucket.get('window') == 'weekly' else str(bucket.get('name') or 'Quota'))
            windows.append(window(label, remaining, bucket.get('reset_time') or bucket.get('resetTime'),
                                  [group.get('description', '')]))
    return windows


FETCHERS = {'claude': fetch_claude, 'codex': fetch_codex, 'antigravity': fetch_antigravity}


def fetch_provider(provider):
    now = datetime.now(timezone.utc).isoformat()
    try:
        data = FETCHERS[provider]()
        has_values = any(w['remainingPercent'] is not None for w in data['windows'])
        return {'id': provider, 'state': 'ok' if has_values else 'unavailable', 'checkedAt': now,
                'message': '' if has_values else 'Provider không trả quota theo định dạng được hỗ trợ.', **data}
    except ProviderError as error:
        return {'id': provider, 'state': error.state, 'checkedAt': now, 'message': str(error), 'windows': []}
    except Exception:
        # Do not reflect provider payloads or credential data into logs/UI on unexpected failures.
        return {'id': provider, 'state': 'error', 'checkedAt': now,
                'message': 'Không đọc được quota. Kiểm tra phiên đăng nhập CLI.', 'windows': []}
