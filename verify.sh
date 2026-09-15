#!/usr/bin/env bash
# ==========================================================================
#  AniManga.SU — Origin+CDN Bridge Verifier (универсальный)
#  Работает с ЛЮБЫМ доменом. Сначала читает state.env из /animanga-cdn/state
#  который пишет deploy.sh.
# ==========================================================================
set -o pipefail
umask 022

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
OK()    { echo -e "  ${GREEN}✅${NC} $1"; }
WARN()  { echo -e "  ${YELLOW}⚠️${NC}  $1"; }
FAIL()  { echo -e "  ${RED}❌${NC} $1"; }
INFO()  { echo -e "  ${CYAN}ℹ️${NC}  $1"; }
step()  { echo -e "\n══════════════════════════════════════════\n  $1\n══════════════════════════════════════════\n"; }
check() {
    local label="$1" exp="$2" got="$3" show="$4"
    if [[ "$got" == "$exp" ]]; then
        OK  "${label} -> HTTP ${got}"
    else
        WARN "${label} -> HTTP ${got} (ожидали ${exp})${show:+ — ${show}}"
    fi
}

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null; echo "$PWD"; )"
STATE_DIR="${SCRIPT_DIR}/state"
STATE_FILE="${STATE_DIR}/state.env"

# -------------- читаем state.env — ВСЕ переменные оттуда --------------
if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1091
    source "${STATE_FILE}"
fi

# Если чего-то нет — задаём дефолты (чтобы не падало, если deploy ещё не запускали или руками правили)
ORIGIN_DOMAIN="${ORIGIN_DOMAIN:-video-quality.animanga.su}"
CDN_DOMAIN="${CDN_DOMAIN:-video-fast.animanga.su}"
XRAY_PORT="${XRAY_PORT:-5448}"
XRAY_DUMMY_OK_PORT="${XRAY_DUMMY_OK_PORT:-20080}"
PATH_A="${PATH_A:-/stream/v2/chapters/segments}"
PATH_B="${PATH_B:-/cdn/v3/media/hls/fragments}"
ORIGIN_SECRET="${SAVED_ORIGIN_SECRET:-}"

# Если секрет пустой (state ещё нет) — берём из origin-secret.txt или генерируем временный
if [[ -z "$ORIGIN_SECRET" ]]; then
    ORIGIN_SECRET="$(cat "${STATE_DIR}/origin-secret.txt" 2>/dev/null | head -c 56)"
fi
if [[ -z "$ORIGIN_SECRET" ]]; then
    # Временный — только для проверок (nginx в этом случае тоже должен был иметь этот же; но лучше deploy.sh запускать)
    ORIGIN_SECRET="c6da03b9dbfd03c72813edb7d4791f3180a1da03f372c358"
fi

# Секрет header:
SECRET_HDR=(-H "X-Origin-Secret: ${ORIGIN_SECRET}")

# ------------------------------------------------------------------------
#  ШАПКА
# ------------------------------------------------------------------------
echo -e "\n══════════════════════════════════════════"
echo -e "  ${CYAN}ENVIRONMENT${NC}"
echo -e "══════════════════════════════════════════"
echo -e "  Origin : ${ORIGIN_DOMAIN}"
echo -e "  CDN    : ${CDN_DOMAIN}"
echo -e "  Secret : ${ORIGIN_SECRET:0:10}...${ORIGIN_SECRET: -10}"
echo -e "  Origin A: :443${PATH_A} → 127.0.0.1:${XRAY_PORT}"
echo -e "  Origin B: :443${PATH_B} → 127.0.0.1:${XRAY_PORT}"
echo -e "  Fallback dummy OK :127.0.0.1:${XRAY_DUMMY_OK_PORT}"

# ------------------------------------------------------------------------
#  БЛОК 1. NGINX
# ------------------------------------------------------------------------
step "1. NGINX STATUS"
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
        OK "nginx service active"
    else
        WARN "nginx inactive — systemctl status nginx чтобы посмотреть почему"
    fi
fi
nginx -t 2>&1 | tail -3
echo

# ------------------------------------------------------------------------
#  БЛОК 2. ЛОКАЛЬНЫЕ ПРОВЕРКИ (127.0.0.1)
# ------------------------------------------------------------------------
step "2. LOCAL CHECKS (127.0.0.1)"

# --- :80 redirect
R=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://127.0.0.1/" 2>/dev/null)
check ":80 redirect -> :443" "301" "${R}"

echo
echo "  -- HTTPS :443 site homepage (self-signed allowed) --"
R=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://127.0.0.1/" 2>/dev/null)
check ":443 / -> 200" "200" "${R}"

echo "  -- HTTPS :443 static asset (/css/style.css) --"
R=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://127.0.0.1/css/style.css" 2>/dev/null)
check ":443 /css/style.css -> 200" "200" "${R}"

echo
echo "  -- HTTPS :443 ${PATH_A} (БЕЗ секрета) --"
R=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://127.0.0.1${PATH_A}" 2>/dev/null)
check "Bridge A БЕЗ секрета -> 403" "403" "${R}"

echo "  -- HTTPS :443 ${PATH_A} (С СЕКРЕТОМ) --"
R=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "${SECRET_HDR[@]}" "https://127.0.0.1${PATH_A}" 2>/dev/null)
# Ожидаем либо 200 (dummy OK сработал), либо 404 (Xray отвечает, это нормально на голый curl)
# Делаем универсальную проверку — 200 ИЛИ 404 = ОК, остальное = WARN
case "${R}" in
    404|200) OK  "Bridge A с секретом -> ${R} (Xray отвечает или dummy OK fallback. HTTP 200 = fallback сработал!)" ;;
    502) FAIL "Bridge A с секретом -> 502 (Xray не слушает :${XRAY_PORT}. Запусти Remnawave + inbound на ${XRAY_PORT})" ;;
    *)   WARN "Bridge A с секретом -> ${R} (неожиданно, ожидаем 200/404)" ;;
esac

echo
echo "  -- HTTPS :443 ${PATH_B} (БЕЗ секрета) --"
R=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://127.0.0.1${PATH_B}" 2>/dev/null)
check "Bridge B БЕЗ секрета -> 403" "403" "${R}"

echo "  -- HTTPS :443 ${PATH_B} (С СЕКРЕТОМ) --"
R=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "${SECRET_HDR[@]}" "https://127.0.0.1${PATH_B}" 2>/dev/null)
case "${R}" in
    404|200) OK  "Bridge B с секретом -> ${R} (Xray отвечает или dummy OK fallback)" ;;
    502) FAIL "Bridge B с секретом -> 502 (Xray не слушает :${XRAY_PORT})" ;;
    *)   WARN "Bridge B с секретом -> ${R} (неожиданно)" ;;
esac

# ------------------------------------------------------------------------
#  БЛОК 3. DNS
# ------------------------------------------------------------------------
step "3. DNS RESOLUTION"
ORIGIN_IP="$(dig +short "${ORIGIN_DOMAIN}" A 2>/dev/null | grep -Eo "^[0-9.]+" | head -n1)"
CDN_IP="$(dig +short "${CDN_DOMAIN}" A    2>/dev/null | grep -Eo "^[0-9.]+" | head -n1)"
CDN_CNAME="$(dig +short "${CDN_DOMAIN}" CNAME 2>/dev/null | sed 's/\.$//' | head -n1)"
MY_IP="$(curl -4 -s -m 8 ifconfig.me 2>/dev/null || curl -4 -s -m 8 ipinfo.io/ip 2>/dev/null || true)"

[ -z "${ORIGIN_IP}" ]  && ORIGIN_IP="(не резолвится)"
[ -z "${CDN_IP}" ]     && CDN_IP="(не резолвится)"
[ -z "${MY_IP}" ]      && MY_IP="(curl недоступен)"

echo "  Origin A record     : ${ORIGIN_IP}"
echo "  CDN A record        : ${CDN_IP}"
echo "  CDN CNAME record    : ${CDN_CNAME:-нет CNAME (A-only или ошибка DNS)}"
echo "  This server external IP: ${MY_IP}"
echo

if [[ "${ORIGIN_IP}" =~ ^[0-9]+\. ]] && [[ "${MY_IP}" =~ ^[0-9]+\. ]] && [[ "${ORIGIN_IP}" == "${MY_IP}" ]]; then
    OK "Origin DNS совпадает с IP этого сервера"
elif [[ "${ORIGIN_IP}" =~ ^[0-9]+\. ]] && [[ "${MY_IP}" =~ ^[0-9]+\. ]]; then
    WARN "Origin DNS = ${ORIGIN_IP}, этот сервер = ${MY_IP}. certbot не сработает, пока DNS не переключишь."
fi
if [[ -n "${CDN_CNAME}" ]]; then
    OK "CDN CNAME уже настроен -> ${CDN_CNAME}"
else
    WARN "CDN CNAME не найден. Создай CNAME ${CDN_DOMAIN} → cl-XXXXXX.service.cdn.msk.vkcs.cloud (VK Cloud)"
fi

# ------------------------------------------------------------------------
#  БЛОК 4. ORIGIN напрямую (через интернет)
# ------------------------------------------------------------------------
step "4. ORIGIN DOMAIN DIRECTLY (через интернет)"

echo "  -- \`https://${ORIGIN_DOMAIN}/\` (сайт-заглушка) --"
R=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "https://${ORIGIN_DOMAIN}/" 2>/dev/null)
case "${R}" in
    200) OK "Origin сайт открывается напрямую по HTTPS (HTTP ${R})" ;;
    301|302) OK "Origin редиректит (HTTP ${R})" ;;
    000) FAIL "Origin НЕДОСТУПЕН (Connection refused / таймаут). 80/443 закрыты?" ;;
    *)   WARN "Origin вернул ${R}" ;;
esac

echo "  -- \`https://${ORIGIN_DOMAIN}${PATH_A}\` (Bridge A с секретом НАПРЯМУЮ origin, БЕЗ CDN!) --"
OUT=$(curl -s -o /tmp/verify_a_body.txt -w "HTTP %{http_code} | server: %header{server}" --max-time 15 "${SECRET_HDR[@]}" "https://${ORIGIN_DOMAIN}${PATH_A}" 2>/dev/null)
R=$(echo "$OUT" | grep -oE "HTTP [0-9]+" | awk '{print $2}')
echo "  $OUT"
case "${R}" in
    200|404) OK "Bridge A НАПРЯМУЮ origin = ${R} — XRAY работает от мира. Мост 100% исправен." ;;
    403) FAIL "Bridge A напрямую = 403 — СЕКРЕТ в nginx origin НЕ СОВПАДАЕТ с тем, что в verify.sh. Перезапусти deploy.sh чтобы синхронизировать." ;;
    502) FAIL "Bridge A напрямую = 502 — Xray :${XRAY_PORT} не слушает. Remnawave inbound подними." ;;
    *)   WARN "Bridge A напрямую вернул ${R}" ;;
esac

echo "  -- \`https://${ORIGIN_DOMAIN}${PATH_B}\` (Bridge B с секретом НАПРЯМУЮ origin) --"
OUT=$(curl -s -o /tmp/verify_b_body.txt -w "HTTP %{http_code} | server: %header{server}" --max-time 15 "${SECRET_HDR[@]}" "https://${ORIGIN_DOMAIN}${PATH_B}" 2>/dev/null)
R=$(echo "$OUT" | grep -oE "HTTP [0-9]+" | awk '{print $2}')
echo "  $OUT"
case "${R}" in
    200|404) OK "Bridge B НАПРЯМУЮ origin = ${R} — XRAY работает" ;;
    403) FAIL "Bridge B напрямую = 403 — СЕКРЕТ не совпадает" ;;
    502) FAIL "Bridge B напрямую = 502 — Xray :${XRAY_PORT} не слушает" ;;
    *)   WARN "Bridge B напрямую вернул ${R}" ;;
esac

# ------------------------------------------------------------------------
#  БЛОК 5. CDN (через video-fast.animanga.su — ВЕРХНЯЯ ПРОВЕРКА!)
# ------------------------------------------------------------------------
step "5. EXTERNAL (through CDN domain — ИТОГОВАЯ ПРОВЕРКА)"

echo "  -- \`https://${CDN_DOMAIN}/\` (главная заглушка через CDN) --"
OUT=$(curl -s -o /dev/null -w "HTTP %{http_code} | server: %header{server}" --max-time 20 "https://${CDN_DOMAIN}/" 2>/dev/null)
echo "  $OUT"
if echo "$OUT" | grep -qE "HTTP 200"; then
    OK "CDN отдаёт сайт-заглушку — это хорошо, CDN→origin работает по сайту"
fi

echo
echo "  -- \`https://${CDN_DOMAIN}${PATH_A}\` (🔥 ОСНОВНОЙ XHTTP мост через CDN!) --"
OUT=$(curl -s -o /tmp/verify_a_cdn.txt -w "HTTP %{http_code} | server: %header{server}" --max-time 20 "https://${CDN_DOMAIN}${PATH_A}" 2>/dev/null)
R=$(echo "$OUT" | grep -oE "HTTP [0-9]+" | awk '{print $2}')
echo "  $OUT"
case "${R}" in
    200|404)
        OK "✅ BRIDGE A (CDN → origin → Xray) РАБОТАЕТ! HTTP ${R} = ОК." ;;
    403)
        WARN "HTTP 403 — ORIGIN_SECRET не долетел от CDN до origin."
        echo "     Проверь в VK Cloud CDN -> Custom headers -> X-Origin-Secret: ${ORIGIN_SECRET}" ;;
    502|503|504)
        FAIL "HTTP ${R} — CDN край не смог достучаться до origin OR origin не ответил."
        echo "     → Проверь: Протокол с источником = HTTPS (не HTTP!)"
        echo "     → Источник          = https://${ORIGIN_DOMAIN} (без порта! порт 443 default)"
        echo "     → Host-заголовок    = Кастомный → ${ORIGIN_DOMAIN}" ;;
    000)
        FAIL "CDN НЕДОСТУПЕН по https://${CDN_DOMAIN}/. DNS CNAME не настроен? Или SSL сертификат на CDN-е ещё не выпущен?" ;;
    *)
        WARN "Неожиданный ответ ${R}. См. тело в /tmp/verify_a_cdn.txt" ;;
esac

echo
echo "  -- \`https://${CDN_DOMAIN}${PATH_B}\` (BACKUP XHTTP мост через CDN) --"
OUT=$(curl -s -o /tmp/verify_b_cdn.txt -w "HTTP %{http_code} | server: %header{server}" --max-time 20 "https://${CDN_DOMAIN}${PATH_B}" 2>/dev/null)
R=$(echo "$OUT" | grep -oE "HTTP [0-9]+" | awk '{print $2}')
echo "  $OUT"
case "${R}" in
    200|404) OK "Bridge B (CDN) работает!" ;;
    403) WARN "403 — секрет не долетел" ;;
    502|503|504) FAIL "CDN-край не достучался. Настройки VK Cloud смотри выше." ;;
    *)   WARN "Ответ ${R} — смотри /tmp/verify_b_cdn.txt" ;;
esac

# ------------------------------------------------------------------------
#  БЛОК 6. PORTS LISTENING
# ------------------------------------------------------------------------
step "LISTENING PORTS ON HOST"
if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | grep -E ":(80|443|22|${XRAY_PORT}|${XRAY_DUMMY_OK_PORT})\b" | sort || \
    ss -ltnp 2>/dev/null | head -20
elif command -v netstat >/dev/null 2>&1; then
    netstat -ltnp 2>/dev/null | grep -E ":(80|443|22|${XRAY_PORT}|${XRAY_DUMMY_OK_PORT})\b" | sort
else
    WARN "ss/netstat не найдены — пропускаем"
fi

# ------------------------------------------------------------------------
#  БЛОК 7. QUICK REMINDER
# ------------------------------------------------------------------------
step "QUICK REMINDER — ЧТО ЕСЛИ ЧТО-ТО НЕ РАБОТАЕТ"

echo -e "  ${YELLOW}502 через CDN/с секретом локально${NC} -> Xray-инбаунд :${XRAY_PORT} не слушает"
echo -e "    → Панель Remnawave → Config Profiles:"
echo -e "       • Добавь в inbounds: ${SCRIPT_DIR}/configs/config-profile-inbound.json"
echo -e "       • Добавь outbounds+routing: ${SCRIPT_DIR}/configs/routing-outbound-direct.json"
echo -e "       • СОХРАНИ И ОБЯЗАТЕЛЬНО НАЖМИ RELOAD/RESTART НОДЫ (без этого изменения не применятся!)"
echo
echo -e "  ${YELLOW}403 через CDN, но локально с секретом работает${NC} -> CDN не отправляет заголовок"
echo -e "    → VK Cloud CDN → Ресурс → Настройки → Custom headers / Заголовки к источнику:"
echo -e "       X-Origin-Secret: ${ORIGIN_SECRET}"
echo
echo -e "  ${YELLOW}502 от CDN-края (заголовки server: CDN edge, не nginx)${NC} -> неверный протокол/источник"
echo -e "    → VK Cloud CDN: Протокол с источником = HTTPS (не HTTP!)"
echo -e "    → Источник: \`https://${ORIGIN_DOMAIN}\` (НЕ ЗАБЫВАЙ HTTPS://, порт не нужен)"
echo -e "    → Host-заголовок: Кастомный → ${ORIGIN_DOMAIN}"
echo
echo -e "  ${YELLOW}invalid request user id в error.log remnanode${NC} -> не тот UUID"
echo -e "    → Бери vlessUuid служебного пользователя svc-cdn-bridge, не uuid аккаунта!"
echo

# ------------------------------------------------------------------------
#  БЛОК 8. Финальный резюме
# ------------------------------------------------------------------------
echo -e "\n══════════════════════════════════════════\n"
echo -e "  💾 State-файл:    ${STATE_FILE}"
echo -e "  🎯 Origin Secret: ${ORIGIN_SECRET}"
echo -e "  🚀 Деплой скрипт: ${SCRIPT_DIR}/deploy.sh"
echo -e "  🖥️  Site root:    /var/www/${ORIGIN_DOMAIN}/"
echo -e "══════════════════════════════════════════\n"

exit 0
