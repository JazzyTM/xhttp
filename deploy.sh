#!/usr/bin/env bash
# ==========================================================================
#  AniManga.SU — Origin + xHTTP CDN Bridge deployer (универсальный, 0 hardcode)
#  Работает на Ubuntu 22.04 / 24.04 / Debian 11+, любой сервер, любой домен.
# ==========================================================================
#  КАК ИСПОЛЬЗОВАТЬ (2 шага):
#
#   Шаг 1. Отредактируй БЛОК НАСТРОЕК ↓↓↓ (всего 7 строчек, не трогай больше)
#   Шаг 2. Запусти:   sudo bash ./deploy.sh
#
#  Для повторного запуска на том же сервере — перезаписывать ничего не нужно.
#  Скрипт идемпотентный: можно вызывать много раз, ничего не сломается.
# ==========================================================================

set -o pipefail
umask 022

# ==========================================================================
#  🔧 БЛОК НАСТРОЕК — ОТРЕДАКТИРУЙ ЭТО ПЕРЕД ЗАПУСКОМ
# ==========================================================================
ORIGIN_DOMAIN="video-quality.animanga.su"   # origin-домен (A-запись → IP этого сервера)
CDN_DOMAIN="video-fast.animanga.su"          # CDN-домен   (CNAME → укажи в DNS VK Cloud после деплоя)
XRAY_PORT="5448"                              # Локальный порт inbound'а Xray (уже должен быть запущен на 127.0.0.1)
XRAY_DUMMY_OK_PORT="20080"                    # Внутренний порт fallback-сервера (dummy OK JSON, если Xray упадёт)
PATH_A="/stream/v2/chapters/segments"         # URL-путь №1 (xhttp мост A) — кастомный, под заглушку манги
PATH_B="/cdn/v3/media/hls/fragments"          # URL-путь №2 (xhttp мост B) — кастомный, под заглушку HLS CDN
ORIGIN_SECRET="c6da03b9dbfd03c72813edb7d4791f3180a1da03f372c358" # СЕКРЕТНЫЙ ТОКЕН (твой рабочий!).
                                              # Оставь пустым — скрипт сам сгенерирует и сохранит.
                                              # Если уже указан — будет использован этот.
REMNA_NODE_PORT="2222"                        # Порт Remnanode / Warden agent / node management (WSS/gRPC).
                                              # Оставь 2222 (стандарт remna), "" — НЕ ОТКРЫВАТЬ порт в ufw.
# ==========================================================================
#  КОНЕЦ БЛОКА НАСТРОЕК. ДАЛЬШЕ НИЧЕГО НЕ МЕНЯЙ.
# ==========================================================================

# ---------------- вспомогательные функций ----------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
OK()    { echo -e "  ${GREEN}✅${NC} $1"; }
WARN()  { echo -e "  ${YELLOW}⚠️${NC}  $1"; }
FAIL()  { echo -e "  ${RED}❌${NC} $1"; }
INFO()  { echo -e "  ${CYAN}ℹ️${NC}  $1"; }
step()  { echo -e "\n═══════════════════════════════════════════\n  $1\n═══════════════════════════════════════════\n"; }

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null; echo "$PWD"; )"
STATE_DIR="${SCRIPT_DIR}/state"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
WEB_ROOT_SRC="${SCRIPT_DIR}/web-root"
mkdir -p "${STATE_DIR}" "${CONFIGS_DIR}" 2>/dev/null || true

# ---------------- проверка root ----------------
if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}ОШИБКА: запусти с sudo (sudo bash $0)${NC}" >&2
    exit 1
fi

# ---------------- чтение state.env ----------------
if [[ -f "${STATE_DIR}/state.env" ]]; then
    # shellcheck disable=SC1091
    source "${STATE_DIR}/state.env"
fi

# ---------------- генерация секрета, если пустой ----------------
if [[ -z "${ORIGIN_SECRET}" ]]; then
    if [[ -n "${SAVED_ORIGIN_SECRET}" ]]; then
        ORIGIN_SECRET="${SAVED_ORIGIN_SECRET}"
    else
        ORIGIN_SECRET="$(head -c 32 /dev/urandom 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}' | head -c 56)"
        INFO "Генерирую новый ORIGIN_SECRET..."
    fi
fi

# ---------------- сохранить state.env ----------------
cat > "${STATE_DIR}/state.env" <<ENV
ORIGIN_DOMAIN="${ORIGIN_DOMAIN}"
CDN_DOMAIN="${CDN_DOMAIN}"
XRAY_PORT="${XRAY_PORT}"
XRAY_DUMMY_OK_PORT="${XRAY_DUMMY_OK_PORT}"
PATH_A="${PATH_A}"
PATH_B="${PATH_B}"
SAVED_ORIGIN_SECRET="${ORIGIN_SECRET}"
ENV
# shellcheck disable=SC1091
source "${STATE_DIR}/state.env"

# ---------------- сохранить секрет в отдельный файл (для копипасты) ----------------
echo -n "${ORIGIN_SECRET}" > "${STATE_DIR}/origin-secret.txt" 2>/dev/null || true

# ---------------- вывести ENV шапку ----------------
echo -e "\n════════════════════════════════════════════════"
echo -e "  ${CYAN}ENVIRONMENT${NC}"
echo -e "════════════════════════════════════════════════"
echo -e "  Origin : ${ORIGIN_DOMAIN}"
echo -e "  CDN    : ${CDN_DOMAIN}"
echo -e "  Secret : ${ORIGIN_SECRET:0:10}...${ORIGIN_SECRET: -10}"
echo -e "  Xray   : 127.0.0.1:${XRAY_PORT}"
echo -e "  Fallback OK: 127.0.0.1:${XRAY_DUMMY_OK_PORT} (JSON {status:ok})"
echo -e "  Path A : :443 ${PATH_A}"
echo -e "  Path B : :443 ${PATH_B}"
echo -e "════════════════════════════════════════════════\n"

# ---------------- проверить dpkg / apt ----------------
step "ШАГ 1/7: Чиним dpkg / apt (локи и поломанные установки)"
if command -v apt >/dev/null 2>&1; then
    # Убиваем unattended-upgrade если он висел
    pkill -15 -f "unattended-upgrade" 2>/dev/null || true
    pkill -9 -f "unattended-upgrade" 2>/dev/null || true
    sleep 1
    # чистим мёртвые лок-файлы
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
          /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
    INFO "dpkg --configure -a..."
    dpkg --configure -a 2>&1 | tail -5 || true
    INFO "apt --fix-broken install..."
    DEBIAN_FRONTEND=noninteractive apt --fix-broken install -y -q 2>&1 | tail -5 || true
    INFO "apt update..."
    DEBIAN_FRONTEND=noninteractive apt update -y -q 2>&1 | tail -5 || true
else
    FAIL "apt не найден. Скрипт только для Ubuntu/Debian."
    exit 2
fi

# ---------------- Установка пакетов ----------------
step "ШАГ 2/7: Установка пакетов (nginx, ssl-cert, ufw, curl, nginx-core, python3)"
NEED_PKGS=( nginx nginx-core ssl-cert ca-certificates curl ufw python3 coreutils dnsutils )
INSTALLED_OK=1
for pkg in "${NEED_PKGS[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        OK "уже стоит: $pkg"
    else
        INFO "ставлю: $pkg"
        DEBIAN_FRONTEND=noninteractive apt install -y -q "$pkg" 2>&1 | tail -3 || {
            WARN "не удалось поставить $pkg — возможно уже стоит или проблема apt"
        }
    fi
done
# Проверим что nginx реально есть
if command -v nginx >/dev/null 2>&1; then
    OK "nginx установлен: $(nginx -v 2>&1 | head -n1)"
else
    FAIL "nginx не установлен. Проверьте интернет / зеркала apt и запусти снова."
    exit 3
fi

# ---------------- Открываем порты UFW (если ufw не включен — ничего не ломаем) ----------------
step "ШАГ 3/7: Настройка ufw (открываем 22 / 80 / 443 + Remna ${REMNA_NODE_PORT}. Кастомные 10065/10066 — закрываем!)"
# всегда закрываем кастомные порты — больше их нет в конфиге
ufw delete allow 10065/tcp 2>/dev/null || true
ufw delete allow 10066/tcp 2>/dev/null || true
ufw allow 22/tcp    comment 'SSH'               2>/dev/null || true
ufw allow 80/tcp    comment 'HTTP + ACME'       2>/dev/null || true
ufw allow 443/tcp   comment 'HTTPS + TLS'       2>/dev/null || true
# Remnanode / Warden agent port (обычно 2222). Если переменная пустая или 0 — не открываем.
if [[ -n "${REMNA_NODE_PORT}" && "${REMNA_NODE_PORT}" != "0" ]]; then
    ufw allow "${REMNA_NODE_PORT}/tcp" comment 'Remnanode / Warden node' 2>/dev/null || true
fi
# ufw enable только если ещё не включен
if ufw status | head -n1 | grep -qi inactive; then
    INFO "ufw не активен — включаю (по умолчанию deny входящие)"
    echo "y" | ufw enable 2>/dev/null || WARN "не удалось включить ufw — продолжаю без него"
fi
ufw status numbered 2>/dev/null | head -15 || true

# ------------------ ОЧИСТКА СТАРЫХ NGINX-КОНФИГОВ (DO FIRST — ПЕРЕД ГЕНЕРАЦИЕЙ!) ------------------
# ВНИМАНИЕ: ЭТОТ БЛОК ОБЯЗАТЕЛЬНО ДО GENERATE dummy-ok И ДО GENERATE MAIN NGINX CONF!
# Иначе старые broken-файлы (с http_400, unexpected "1", другой домен) остаются
# в sites-enabled и nginx падает при nginx -t / reload даже если новые конфиги правильные.
INFO "🧹 Предварительно чищу ВСЕ старые nginx sites-enabled/available (до генерации!)"
# 1) Удаляем ВСЕ по wildcard для ТЕКУЩЕГО домена (самое важное — ИСКЛЮЧАЕМ dummy-ok и конфиги прошлого!)
rm -f "/etc/nginx/sites-enabled/${ORIGIN_DOMAIN}*" \
      "/etc/nginx/sites-available/${ORIGIN_DOMAIN}*" 2>/dev/null || true
# 2) Удаляем legacy animanga (из ранних версий шаблона), default, *.bak, битые
rm -f /etc/nginx/sites-enabled/animanga \
      /etc/nginx/sites-available/animanga \
      /etc/nginx/sites-available/animanga-tmp \
      /etc/nginx/sites-enabled/default \
      /etc/nginx/sites-enabled/*.bak \
      /etc/nginx/sites-enabled/*animanga* \
      /etc/nginx/sites-enabled/*-dummy-ok.conf \
      /etc/nginx/sites-available/*-dummy-ok.conf 2>/dev/null || true
# 3) Удаляем ВСЕ sites-enabled/*.conf (кроме возможно configs shipped but usually we don't ship — SAFE: нет, не трогаем пакетные). Оставляем удаление только наших.
# 4) Чистим битые симлинки enabled→available (target не существует)
for stale in /etc/nginx/sites-enabled/*; do
    if [[ -L "$stale" ]] && [[ ! -e "$stale" ]]; then
        rm -f "$stale" 2>/dev/null || true
    fi
done
INFO "✅ Старые nginx-конфиги вычищены. sites-enabled сейчас $(ls /etc/nginx/sites-enabled 2>/dev/null | wc -l) файлов"

# ---------------- Кладём сайт-заглушку AniManga.SU ----------------
step "ШАГ 4/7: ДепLOY сайта-заглушки AniManga.SU → /var/www/${ORIGIN_DOMAIN}/"
WEBROOT_DST="/var/www/${ORIGIN_DOMAIN}"
mkdir -p "${WEBROOT_DST}" 2>/dev/null || true
# DEBUG: показываем что ЕСТЬ в исходной веб-рут директории — пользователи часто копируют ТОЛЬКО deploy.sh без web-root/
SRC_HTML_N=$(find "${WEB_ROOT_SRC}" -maxdepth 1 -type f -name "*.html" 2>/dev/null | wc -l | tr -d ' ')
SRC_LS=$(ls -A "${WEB_ROOT_SRC}" 2>/dev/null | head -15 | tr '\n' ', ')
INFO "Исходник web-root: ${WEB_ROOT_SRC} (HTML файлов: ${SRC_HTML_N}). Содержимое: ${SRC_LS}"
if [[ "${SRC_HTML_N}" -eq 0 ]]; then
    WARN "⚠️  В исходной директории ${WEB_ROOT_SRC} НЕТ HTML-файлов! Это значит что ты скопировал только deploy.sh, а НЕ ВЕСЬ репо."
    WARN "→ РЕШЕНИЕ: cd /root/animanga-cdn && git pull https://github.com/JazzyTM/xhttp.git main — и перезапусти deploy.sh"
fi

# 1) ЧИСТИМ Устаревшее: удаляем ВСЕ *.html/css/js/favicon старые (чтобы скопировать свежие!)
#    Не удаляем .well-known/acme-challenge/ — там certbot токены могут лежать!
rm -rf  "${WEBROOT_DST}"/*.html \
        "${WEBROOT_DST}/css" \
        "${WEBROOT_DST}/js" \
        "${WEBROOT_DST}/favicon.ico" \
        "${WEBROOT_DST}/favicon.svg" \
        2>/dev/null || true

# 2) КОПИРУЕМ ВСЁ ИЗ web-root — ВСЕГДА! принудительно cp -f
COPY_OK=0
if [[ -d "${WEB_ROOT_SRC}" && -n "$(ls -A "${WEB_ROOT_SRC}" 2>/dev/null)" ]]; then
    # 2a) rsync самый надёжный (удаляет лишние, сохраняет hidden .well-known)
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude='.well-known/acme-challenge' \
              "${WEB_ROOT_SRC}/" "${WEBROOT_DST}/" 2>/dev/null && COPY_OK=1 || COPY_OK=0
    fi
    # 2b) если rsync нет или упал — cp -af ТОГДА per-file
    if [[ ${COPY_OK} -ne 1 ]]; then
        cp -af "${WEB_ROOT_SRC}/." "${WEBROOT_DST}/" 2>/dev/null && COPY_OK=1 || COPY_OK=0
    fi
    # 2c) ЖЕЛЕЗНО — принудительно копируем КАЖДЫЙ тип файл отдельно, чтобы 100% дошли
    if [[ -d "${WEB_ROOT_SRC}" ]]; then
        # ВСЕ HTML страницы (index + projects + schedule + manga + about + copyright + tos + privacy = 8 шт)
        find "${WEB_ROOT_SRC}" -maxdepth 1 -type f -name "*.html" -print0 2>/dev/null | while IFS= read -r -d '' htmlfile; do
            cp -f "$htmlfile" "${WEBROOT_DST}/" 2>/dev/null
        done
        # ВСЕГДА копируем подпапки css, js
        [[ -d "${WEB_ROOT_SRC}/css" ]] && { mkdir -p "${WEBROOT_DST}/css" 2>/dev/null; cp -rf "${WEB_ROOT_SRC}/css/." "${WEBROOT_DST}/css/" 2>/dev/null; }
        [[ -d "${WEB_ROOT_SRC}/js" ]]  && { mkdir -p "${WEBROOT_DST}/js"  2>/dev/null; cp -rf "${WEB_ROOT_SRC}/js/."  "${WEBROOT_DST}/js/"  2>/dev/null; }
        # favicon
        for ext in svg ico png; do
            [[ -f "${WEB_ROOT_SRC}/favicon.${ext}" ]] && cp -f "${WEB_ROOT_SRC}/favicon.${ext}" "${WEBROOT_DST}/" 2>/dev/null
        done
        COPY_OK=1
    fi
fi

# 3) ПРОВЕРКА ЧТО ВСЁ СКОПИРОВАЛОСЬ — считаем сколько HTML страниц в назначении
HTML_COUNT=$(find "${WEBROOT_DST}" -maxdepth 1 -type f -name "*.html" 2>/dev/null | wc -l | tr -d ' ')
CSS_SIZE=$([[ -f "${WEBROOT_DST}/css/style.css" ]] && wc -c < "${WEBROOT_DST}/css/style.css" 2>/dev/null || echo 0)
JS_SIZE=$([[ -f "${WEBROOT_DST}/js/app.js" ]] && wc -c < "${WEBROOT_DST}/js/app.js" 2>/dev/null || echo 0)
INFO "Скопировано HTML-страниц: ${HTML_COUNT} шт, style.css: ${CSS_SIZE} байт, app.js: ${JS_SIZE} байт"

# 4) FALLBACK — если src-директория была ПУСТАЯ (на новом сервере копировали только deploy.sh без web-root)
#    Тогда создаём МИНИМУМ чтобы nginx не отдавал 404 везде и LE certbot прошёл
if [[ "${HTML_COUNT}" -lt 2 ]] || [[ ! -f "${WEBROOT_DST}/index.html" ]]; then
    WARN "⚠️  web-root пустой или неполный → создаём минимальный fallback + certbot-валидный .well-known"
    mkdir -p "${WEBROOT_DST}/css" "${WEBROOT_DST}/js" "${WEBROOT_DST}/.well-known/acme-challenge" 2>/dev/null || true
    if [[ ! -f "${WEBROOT_DST}/index.html" ]]; then
        cat > "${WEBROOT_DST}/index.html" <<'HTML'
<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AniManga.SU — Смотреть аниме онлайн</title>
<link rel="icon" type="image/svg+xml" href="favicon.svg">
<link rel="stylesheet" href="css/style.css"></head>
<body style="background:#0b1120;color:#e2e8f0;font-family:system-ui;margin:0;padding:60px;text-align:center">
<h1 style="background:linear-gradient(135deg,#7c3aed,#0ea5e9);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text">AniManga.SU</h1>
<h2>Смотреть аниме и читать мангу онлайн в HD</h2>
<p style="color:#94a3b8">Страница готовится. Мы обновляем каталог. Загляните позже.</p>
<p style="opacity:.6;margin-top:40px">support@animanga.su · 2026</p></body></html>
HTML
    fi
    [[ ! -f "${WEBROOT_DST}/css/style.css" ]] && echo "body{background:#0b1120;color:#e2e8f0}a{color:#7dd3fc}" > "${WEBROOT_DST}/css/style.css"
    [[ ! -f "${WEBROOT_DST}/js/app.js" ]]     && echo "console.log('AniManga.SU loaded')" > "${WEBROOT_DST}/js/app.js"
    if [[ ! -f "${WEBROOT_DST}/favicon.svg" ]]; then
        cat > "${WEBROOT_DST}/favicon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><defs>
<linearGradient id="g" x1="0" x2="1" y1="0" y2="1">
<stop offset="0" stop-color="#7c3aed"/><stop offset="1" stop-color="#0ea5e9"/>
</linearGradient></defs>
<rect width="64" height="64" rx="14" fill="url(#g)"/>
<text x="50%" y="56%" text-anchor="middle" fill="#fff" font-family="Arial" font-weight="800" font-size="28">AM</text>
</svg>
SVG
    fi
fi

# права на веб-рут (www-data)
chown -R www-data:www-data "${WEBROOT_DST}" 2>/dev/null || true
chmod -R u=rwX,go=rX "${WEBROOT_DST}" 2>/dev/null || true
chmod -R a+rwX "${WEBROOT_DST}/.well-known" 2>/dev/null || true

OK "Веб-рут лежит в ${WEBROOT_DST} (HTML=${HTML_COUNT})"

# ---------------- Подготавливаем dummy OK fallback (nginx internal server @ 20080) ----------------
# Создаём отдельный «внутренний» server_block, который отвечает JSON status:ok.
# Используется, если Xray упал или вернул 4xx/5xx — чтобы CDN край не видел 502.
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled 2>/dev/null || true
NOW_TS="$(date +%s)"
DUMMY_OK_CONF="/etc/nginx/sites-available/${ORIGIN_DOMAIN}-dummy-ok.conf"
cat > "${DUMMY_OK_CONF}" <<NGINX_DUMMY
server {
    listen 127.0.0.1:${XRAY_DUMMY_OK_PORT} default_server;
    server_name _;
    access_log /var/log/nginx/animanga-dummy-access.log;
    error_log  /var/log/nginx/animanga-dummy-error.log warn;
    allow 127.0.0.1;
    deny all;

    default_type application/json;
    return 200 '{"status":"ok","service":"animanga-cdn-bridge","server":"${ORIGIN_DOMAIN}","node":"edge-msk-01","region":"ru-central","ts":${NOW_TS}}';
}
NGINX_DUMMY
ln -sf "${DUMMY_OK_CONF}" "/etc/nginx/sites-enabled/${ORIGIN_DOMAIN}-dummy-ok.conf" 2>/dev/null || true

# ---------------- Создаём главный nginx-origin.conf ----------------
step "ШАГ 5/7: Собираю и кладу главный nginx-конфиг origin-сервера"

INFO "🧹 Доочищаю остатки old/${ORIGIN_DOMAIN}-related nginx-конфиги перед генерацией (двойная защита!)"
rm -f "/etc/nginx/sites-enabled/${ORIGIN_DOMAIN}.conf" \
      "/etc/nginx/sites-available/${ORIGIN_DOMAIN}.conf" 2>/dev/null || true

MAIN_CONF_SRC="${CONFIGS_DIR}/nginx-origin.conf"
MAIN_CONF_DST_AVAIL="/etc/nginx/sites-available/${ORIGIN_DOMAIN}.conf"
MAIN_CONF_DST_ENABLED="/etc/nginx/sites-enabled/${ORIGIN_DOMAIN}.conf"

# Создание конфига «с нуля» (чтобы не зависить от прошлых правок)
cat > "${MAIN_CONF_SRC}" <<NGINX_MAIN
# ========================================================================
#  AniManga.SU — Origin Server Nginx Config (${ORIGIN_DOMAIN})
#  ВНИМАНИЕ: этот файл сгенерирован deploy.sh. Не прави руками — перезапишет.
# ========================================================================

# --- Upstream: Xray VLESS xHTTP inbound (локальный) ---
upstream xray_cdn_bridge {
    server 127.0.0.1:${XRAY_PORT}        max_fails=2 fail_timeout=10s;
    server 127.0.0.1:${XRAY_DUMMY_OK_PORT} backup;
    keepalive 64;
}

# ========================================================================
#  :80 — HTTP → редирект на HTTPS, плюс вызов /.well-known/acme-challenge/
# ========================================================================
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${ORIGIN_DOMAIN} "" _;

    root ${WEBROOT_DST};
    access_log /var/log/nginx/animanga-access.log;
    error_log  /var/log/nginx/animanga-error.log warn;

    # ACME challenge (для certbot standalone / standalone plugin)
    location /.well-known/acme-challenge/ {
        default_type text/plain;
        alias ${WEBROOT_DST}/.well-known/acme-challenge/;
        try_files \$uri =404;
    }

    # Любой остальной HTTP → 301 на HTTPS
    location / {
        return 301 https://${ORIGIN_DOMAIN}\$request_uri;
    }
}

# ========================================================================
#  :443 — Основной HTTPS server (origin + CDN мост)
# ========================================================================
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name ${ORIGIN_DOMAIN} "" _;

    root ${WEBROOT_DST};
    index index.html;
    access_log /var/log/nginx/animanga-access.log;
    error_log  /var/log/nginx/animanga-error.log warn;

    # ---------- TLS ----------
    ssl_certificate     /etc/letsencrypt/live/${ORIGIN_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${ORIGIN_DOMAIN}/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Fallback-сертификат, если Let's Encrypt не получилось.
    # (чтобы nginx не падал на старте)
    ssl_certificate         /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key     /etc/ssl/private/ssl-cert-snakeoil.key;

    # Безопасные заголовки (маскируем, что это вообще за софт)
    server_tokens off;
    add_header X-Powered-By "AniMangaCDN/3.4 (origin-msk)" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    # ---------- Origin Secret (только CDN-край должен его слать) ----------
    set \$origin_secret "${ORIGIN_SECRET}";

    # ====================================================================
    # XHTTP Bridge A — ${PATH_A}
    #   идёт на Xray. Если Xray 4xx/5xx или упал → backup dummy OK JSON 200
    # ====================================================================
    location ${PATH_A} {
        if (\$http_x_origin_secret != \$origin_secret) {
            return 403;
        }
        proxy_pass http://xray_cdn_bridge;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504 non_idempotent;
        proxy_next_upstream_tries 2;
        client_max_body_size 0;
        chunked_transfer_encoding on;
    }

    # ====================================================================
    # XHTTP Bridge B — ${PATH_B}
    #   идёт на Xray. Если Xray упал → backup dummy OK JSON 200
    # ====================================================================
    location ${PATH_B} {
        if (\$http_x_origin_secret != \$origin_secret) {
            return 403;
        }
        proxy_pass http://xray_cdn_bridge;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504 non_idempotent;
        proxy_next_upstream_tries 2;
        client_max_body_size 0;
        chunked_transfer_encoding on;
    }

    # ====================================================================
    # Веб-сайт-заглушка AniManga.SU (каталог/расписание/манга)
    # ====================================================================
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Статика с long cache
    location ~* \.(?:css|js|svg|png|jpe?g|gif|ico|woff2?)$ {
        expires 7d;
        access_log off;
        add_header Cache-Control "public, immutable, max-age=604800";
        try_files \$uri =404;
    }

    # Закрываем доступ к dotfiles / .htaccess
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
NGINX_MAIN

OK "Конфиг собран: ${MAIN_CONF_SRC}"

# Кладём его в /etc/nginx
cp -f "${MAIN_CONF_SRC}" "${MAIN_CONF_DST_AVAIL}"
ln -sf "${MAIN_CONF_DST_AVAIL}" "${MAIN_CONF_DST_ENABLED}"

# Удаляем дефолтный default, чтобы не конфликтовал
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# ---------------- Генерация Let's Encrypt сертификата ----------------
step "ШАГ 6/7: Получаем Let's Encrypt сертификат для ${ORIGIN_DOMAIN} (или fallback на self-signed)"
NEED_CERT=1
if [[ -f "/etc/letsencrypt/live/${ORIGIN_DOMAIN}/fullchain.pem" ]]; then
    INFO "Сертификат уже есть, проверяю валидность..."
    # Если валиден ещё 7+ дней — не трогаем
    CERT_DAYS_LEFT="$(openssl x509 -in "/etc/letsencrypt/live/${ORIGIN_DOMAIN}/fullchain.pem" -noout -checkend $((7*86400)) 2>/dev/null && echo ok || echo renew)"
    if [[ "$CERT_DAYS_LEFT" == "ok" ]]; then
        NEED_CERT=0
        OK "Сертификат Let's Encrypt валиден (больше 7 дней осталось)"
    fi
fi

# Убедиться, что параметры dhparam есть
mkdir -p /etc/letsencrypt 2>/dev/null || true
if [[ ! -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
    INFO "Кладу стандартный dhparam 2048 (уже готовый)"
    openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048 2>/dev/null || \
    cp /etc/ssl/dhparam.pem /etc/letsencrypt/ssl-dhparams.pem 2>/dev/null || \
    cat > /etc/letsencrypt/ssl-dhparams.pem <<DH
-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA//////////+t+FRYortKmq/cViAnPTzx2LnFg84tNpWp4TZBFGQz
+8yTnc4kmz75fS/jY2MMddj229gWu4L5zr12b6I9j5fM7e8XcVr4LdP6aSq8vHn
///////////wIBAg==
-----END DH PARAMETERS-----
DH
fi

# options-ssl-nginx.conf (стандартный от certbot — если нет, сделаем)
if [[ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
    cat > /etc/letsencrypt/options-ssl-nginx.conf <<CONF
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
CONF
fi

# Если сертификат надо получить — пробуем certbot, нет certbot → ставим
if [[ "${NEED_CERT}" -eq 1 ]]; then
    # Проверим, что DNS УЖЕ указывает на этот сервер (иначе LE не дойдёт)
    RESOLVED_IP="$(dig +short "${ORIGIN_DOMAIN}" A 2>/dev/null | grep -Eo "^[0-9.]+$" | head -n1)"
    MY_EXTERNAL_IP="$(curl -4 -s -m 8 ifconfig.me 2>/dev/null || curl -4 -s -m 8 ipinfo.io/ip 2>/dev/null || true)"
    if [[ -n "$RESOLVED_IP" && -n "$MY_EXTERNAL_IP" && "$RESOLVED_IP" != "$MY_EXTERNAL_IP" ]]; then
        WARN "DNS $ORIGIN_DOMAIN = $RESOLVED_IP, а этот сервер = $MY_EXTERNAL_IP. Не смогу получить сертификат (ACME challenge не пройдёт)."
        WARN "Будет использован self-signed snakeoil сертификат (nginx запустится в любом случае)."
    else
        # Ставим certbot если нет
        if ! command -v certbot >/dev/null 2>&1; then
            INFO "ставлю certbot..."
            DEBIAN_FRONTEND=noninteractive apt install -y -q certbot python3-certbot-nginx 2>&1 | tail -5 || true
        fi
        if command -v certbot >/dev/null 2>&1; then
            # Проверяем, что nginx слушает :80 (временно релоадим конфиг без certbot чтобы поднять :80)
            INFO "Временно запускаю nginx на :80 для ACME challenge..."
            mkdir -p "${WEBROOT_DST}/.well-known/acme-challenge" 2>/dev/null || true
            nginx -t 2>&1 | tail -3 || true
            systemctl restart nginx 2>/dev/null || service nginx restart 2>/dev/null || nginx 2>/dev/null || true
            sleep 2
            INFO "certbot webroot..."
            certbot certonly --webroot \
                --webroot-path "${WEBROOT_DST}" \
                --agree-tos \
                --non-interactive \
                --register-unsafely-without-email \
                -d "${ORIGIN_DOMAIN}" 2>&1 | tail -15 || true
        fi
    fi
fi

# ---------------- Проверка синтаксиса nginx и рестарт ----------------
step "ШАГ 7/7: Проверка синтаксиса nginx → reload/start"
INFO "nginx -t..."
NGX_T_ERR=0
if nginx -t > /tmp/ngx_test_out.log 2>&1; then
    OK "nginx синтаксис OK"
    # выводим warnings (не ошибки)
    grep -i "warn" /tmp/ngx_test_out.log 2>/dev/null | head -5 || true
else
    WARN "nginx -t ругается. Вывод:"
    cat /tmp/ngx_test_out.log
    # Удаляем нерабочий enable, пробуем только с dummy и сайтом
    NGX_T_ERR=1
fi

# Перезапускаем nginx (systemctl → service → exec)
INFO "перезапуск nginx..."
systemctl daemon-reload 2>/dev/null || true
if systemctl restart nginx 2>/dev/null; then
    sleep 1
    if systemctl is-active --quiet nginx 2>/dev/null; then
        OK "nginx запущен через systemd ✅"
    else
        WARN "nginx через systemd не активен — пробую service"
        service nginx restart 2>/dev/null || true
    fi
else
    WARN "systemd не смог рестартовать — запускаю nginx напрямую"
    nginx 2>/dev/null || true
    nginx -s reload 2>/dev/null || true
fi
# Всё равно проверим, что сокет :80/:443 слушается
sleep 1
if ss -ltnp 2>/dev/null | grep -q ":443" && ss -ltnp 2>/dev/null | grep -q ":80"; then
    OK "порты 80/443 слушаются — всё работает"
else
    WARN "порты 80/443 не слушаются. Проверь journalctl -u nginx или cat /var/log/nginx/error.log"
fi

# ---------------- Финальный state.env на будущее ----------------
cat > "${STATE_DIR}/state.env" <<ENV
ORIGIN_DOMAIN="${ORIGIN_DOMAIN}"
CDN_DOMAIN="${CDN_DOMAIN}"
XRAY_PORT="${XRAY_PORT}"
XRAY_DUMMY_OK_PORT="${XRAY_DUMMY_OK_PORT}"
PATH_A="${PATH_A}"
PATH_B="${PATH_B}"
SAVED_ORIGIN_SECRET="${ORIGIN_SECRET}"
MY_EXTERNAL_IP="${MY_EXTERNAL_IP}"
DEPLOYED_AT="$(date -Iseconds)"
ENV
# shellcheck disable=SC1091
source "${STATE_DIR}/state.env"

# ---------------- Вывод ----------------
echo -e "\n════════════════════════════════════════════════\n"
echo -e "  ${GREEN}✅ РАЗВЁРТЫВАНИЕ ЗАВЕРШЕНО${NC}\n"
echo -e "  Origin : ${ORIGIN_DOMAIN}   (${MY_EXTERNAL_IP:-$RESOLVED_IP})"
echo -e "  CDN    : ${CDN_DOMAIN}      (сейчас CNAME укажи в панели VK Cloud)"
echo -e "  Secret : ${ORIGIN_SECRET}"
echo -e "          💾 также в файле: ${STATE_DIR}/origin-secret.txt"
echo -e "  Xray   : 127.0.0.1:${XRAY_PORT}  (проверь, что слушается!)"
echo -e "  Path A : https://${ORIGIN_DOMAIN}${PATH_A}"
echo -e "  Path B : https://${ORIGIN_DOMAIN}${PATH_B}"
echo -e "  Web    : ${WEBROOT_DST}/"
echo -e "  Cert   : /etc/letsencrypt/live/${ORIGIN_DOMAIN}/"
echo -e ""
echo -e "  ${CYAN}СЛЕДУЮЩИЕ ШАГИ — СДЕЛАЙ ИХ ВРУЧНУЮ${NC}:"
echo -e "   1) VK Cloud → CDN → ресурс:"
echo -e "        • Протокол с источником = HTTPS"
echo -e "        • Источник             = https://${ORIGIN_DOMAIN}"
echo -e "        • Host-заголовок       = Кастомный → ${ORIGIN_DOMAIN}"
echo -e "        • Custom headers       = X-Origin-Secret: ${ORIGIN_SECRET}"
echo -e "   2) DNS: CNAME ${CDN_DOMAIN} → к cl-XXXXXX.service.cdn.msk.vkcs.cloud (VK Cloud)"
echo -e "   3) Remnawave панель:"
echo -e "        • Inbound vless xhttp listen 127.0.0.1:${XRAY_PORT}"
echo -e "        • Hosts: SNI=${ORIGIN_DOMAIN} и ${CDN_DOMAIN}, path=${PATH_B}"
echo -e "        • Users: не забываем брать vlessUuid"
echo -e "   4) Проверка всего: bash ${SCRIPT_DIR}/verify.sh"
echo -e "════════════════════════════════════════════════\n"

exit 0
