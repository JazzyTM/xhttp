# AniManga.SU Origin + CDN xHTTP Bridge · Быстрый деплой на НОВЫЙ сервер 🚀

> Универсальный шаблон: работает на **Ubuntu 22.04 / 24.04 / Debian 12**.
> Настройка **за 5 минут**, все скрипты zero-error (fallback на self-signed cert, fallback web-root если сайт-шаблон не найден).

---

## 📦 Шаг 1 · Клонируй (или скопируй) репозиторий

### ✅ Способ 1 — Git clone (если запушил на GitHub)
```bash
cd /root
apt update && apt install -y git rsync
git clone https://github.com/TВОЙ-НИКНЕЙМ/animanga-cdn.git /root/animanga-cdn
```

### ✅ Способ 2 — c текущего сервера архивируем + переносим на новый
```bash
# АРХИВ на ТЕКУЩЕМ сервере:
cd /root
tar -czf animanga-cdn-repo.tgz animanga-cdn
# СКОПИРУЙ на НОВЫЙ сервер (scp):
scp animanga-cdn-repo.tgz root@IP_НОВОГО_СЕРВЕРА:/root/
# НА НОВОМ:
cd /root
tar -xzf animanga-cdn-repo.tgz
```

---

## ⚙️ Шаг 2 · Отредактируй **ТОЛЬКО 7 строк конфига** в `deploy.sh`

```bash
nano /root/animanga-cdn/deploy.sh
```

Найди блок в самом начале (строки 20–30) и замени **под свой новый домен**:

```bash
# ==========================================================
#  ЕДИНСТВЕННОЕ ЧТО НУЖНО ПОМЕНЯТЬ НА НОВОМ СЕРВЕРЕ — ВСЁ!
# ==========================================================
ORIGIN_DOMAIN="video-quality.animanga.su"   # ← твой origin домен
CDN_DOMAIN="video-fast.animanga.su"          # ← твой CDN домен (CNAME → VK Cloud)
XRAY_PORT="5448"                             # ← порт Remnawave inbound (127.0.0.1)
XRAY_DUMMY_OK_PORT="20080"                   # ← dummy OK сервер HTTP 200 JSON
PATH_A="/stream/v2/chapters/segments"        # ← Bridge path A (маскировка глав)
PATH_B="/cdn/v3/media/hls/fragments"         # ← Bridge path B (маскировка HLS)
ORIGIN_SECRET=""   # ← ОСТАВЬ ПУСТЫМ = сгенерит РАНДОМНЫЙ, или пропиши свой статический 56-символ
# ==========================================================
```

> 💡 **На новом сервере оставь `ORIGIN_SECRET=""` — скрипт сам сгенерирует уникальный 56-символ и сохранит в `state/origin-secret.txt` + `state/state.env`**.
> На ТЕКУЩЕМ рабочем сервере у нас уже прописан статический `c6da03b9...358` — он не перегенерируется.

---

## 🚀 Шаг 3 · Запусти деплой! (одна команда)

```bash
cd /root/animanga-cdn
chmod +x deploy.sh verify.sh
sudo bash deploy.sh
```

**Что сделает скрипт (ШАГИ 1–7):**
1. 🔧 Починит `dpkg / apt` (локи + broken install)
2. 📦 Поставит нужные пакеты: `nginx ssl-cert ufw curl ca-certificates python3 coreutils dnsutils rsync`
3. 🛡️ `ufw` — откроет **ТОЛЬКО 22 / 80 / 443** (закроет все лишние, включая порты 10065–10066)
4. 📄 **Деплой сайта-заглушки AniManga.SU**: копирует ВСЕ 8 HTML страниц + CSS/JS/favicon в `/var/www/<ORIGIN_DOMAIN>/` (если web-root пустой — создаст fallback, чтобы nginx не падал)
5. 🧱 Соберёт **nginx origin config**:
   - `:80` → redirect 301 HTTPS + ACME `/.well-known/acme-challenge/` для certbot
   - `:443` TLS http2 + root `/var/www/<ORIGIN_DOMAIN>`
   - Два upstream-моста: `Path A + Path B` → Xray 127.0.0.1:5448 с **backup** 127.0.0.1:20080 (dummy OK JSON 200 если Xray упал → CDN край **никогда не увидит 502/503**!)
   - Безопасные заголовки HSTS, X-Content-Type, X-Powered-By: AniMangaCDN/3.4, server_tokens: off
6. 🔐 **Let's Encrypt certbot** webroot (если сертификат есть и действителен — пропускает; если нет — получает; если нет DNS/wan → fallback self-signed snakeoil → nginx **всё равно стартанёт!**)
7. ✅ `nginx -t` → `systemctl restart nginx` → проверяет что `:80` и `:443` слушаются, + показывает баннер с **Origin / CDN / Secret + Hosts VK Cloud + Remnawave + 4 следующих шага** для ручной настройки.

---

## ☁️ Шаг 4 · VK Cloud CDN Панель

1. Идём в **VK Cloud → CDN → Ресурсы → (твой ресурс animanga.su) → Настройки**
2. Настраиваем **ТОЧНО В ТАКОМ ЖЕ ПОРЯДКЕ**:
   | Параметр | Значение |
   |---|---|
   | **Протокол с источником** | **HTTPS** — ОБЯЗАТЕЛЬНО! (HTTP на 443 не ходит) |
   | **Источник (Origin)** | `https://<ORIGIN_DOMAIN>` — **БЕЗ ПОРТА** (default :443) |
   | **Host-заголовок** | ✅ **Кастомный → `<ORIGIN_DOMAIN>`** |
   | **Добавление заголовков запросов** | **ON** (переключатель вверху вкладки) |
   | Заголовок: `X-Origin-Secret` | Значение = `<значение из state/origin-secret.txt>` (56 символов) |

3. **DNS** (Cloudflare / Reg.RU / VK DNS):
   ```
   ORIGIN_DOMAIN  →  A  →  публичный IP ТВОЕГО сервера
   CDN_DOMAIN     →  CNAME  →  cl-XXXXXX.service.cdn.msk.vkcs.cloud  (скопируй из VK Cloud!)
   ```

---

## 📡 Шаг 5 · Remnawave / Remnanode Panel

**Config Profile** (Node → Config Profiles → редактируй твой профиль в vkcdn-germany):
1. **Inbounds** → Вставь содержимое файла [config-profile-inbound.json](file:///root/animanga-cdn/configs/config-profile-inbound.json)
2. **Outbounds** → Вставь содержимое [routing-outbound-direct.json](file:///root/animanga-cdn/configs/routing-outbound-direct.json)
3. **Routing** → тоже из того же файла выше
4. **SAVE**

**Hosts (Node → Hosts → + СОЗДАТЬ ДВА ХОСТА):**

| Параметр | Host 1 · Origin | Host 2 · CDN |
|---|---|---|
| **SNI** | `<ORIGIN_DOMAIN>` | `<CDN_DOMAIN>` |
| **Path** | `/cdn/v3/media/hls/fragments` | `/cdn/v3/media/hls/fragments` |
| **Слой безопасности (Security)** | TLS | TLS |
| **Fingerprint** | Chrome (рекомендуется) | Chrome |
| **ALPN** | `h2, http/1.1` | `h2, http/1.1` |
| **Inbound tag** | `vkcdn-germany` (5448) | `vkcdn-germany` (5448) |
| **xHTTP Extra params JSON** (обязательно!) | Вставь содержимое [host-xhttp-extra-portB.json](file:///root/animanga-cdn/configs/host-xhttp-extra-portB.json) | ТО ЖЕ САМОЕ JSON! |

5. ⚠️ **SAVE**, потом нажми **RELOAD NODE** (кнопка перезагрузки узла). **Без релоада изменения не применяются!**

**Users (Node → Users → создать svc-cdn-bridge):**
- Ник: `svc-cdn-bridge`
- Protocol: `VLESS`
- ⚠️ **ИСПОЛЬЗУЙ `vlessUuid` (не обычный uuid!)** — его берём в клиенте.

---

## 💻 Шаг 6 · Клиент (NekoBox / V2rayN / Streisand / Matsuri)

В outbound настроить:
- `Protocol: VLESS`
- `Address: <CDN_DOMAIN>` (важно! ЧЕРЕЗ CDN, не напрямую origin!)
- `Port: 443`
- `UUID: <значение vlessUuid из Remnawave Users>` (НЕ обычный uuid!)
- `Transport: xHTTP`
  - `Security: TLS`
  - `SNI: <CDN_DOMAIN>`
  - `Host: <CDN_DOMAIN>`
  - `xHTTP Path: /cdn/v3/media/hls/fragments` (ТОЧНО как в Hosts!)
  - **Extra params JSON → ВСТАВЬ ТОТ ЖЕ JSON** из [host-xhttp-extra-portB.json](file:///root/animanga-cdn/configs/host-xhttp-extra-portB.json) (`scMaxEachPostBytes: 1052672-2105344`, `hMaxRequestTimes: 600-900`, `hMaxReusableSecs: 1800-3000` и т.д.)
- `Flow: пусто (none)` для xhttp packet-up

---

## ✅ Шаг 7 · Проверка ВСЕГО (verify.sh)

```bash
bash /root/animanga-cdn/verify.sh
```

**6 блоков диагностики:**
1. **NGINX status + syntax** → green OK
2. **Local curl tests** → 80 redirect 301; 443 / 200 OK; Bridge A+B **без секрета** = HTTP 403 ✅ (секрет работает!), с секретом → 200 или 404 OK
3. **DNS** → origin A=public IP, CDN CNAME指向 cl-*.vkcs.cloud
4. **Origin direct hits** → origin domain 200 OK, bridges 200/404 OK (reachable from world)
5. **CDN (final check)** → CDN domain 200 OK, bridges 200/404 OK (**НЕ 502/503/403!**)
6. **Ports listening** → 22/80/443/5448/20080 listening ✅

Если блок 5 CDN Bridge = `HTTP 404` или `200` — **ВСЁ РАБОТАЕТ!** 🔥 Если `502 / 503 / 504` — проверь Шаг 4 VK Cloud protocol HTTPS, если `403` — проверь X-Origin-Secret заголовок точное значение без пробелов.

---

## 🆘 Частые проблемы / Как починить за 1 минуту

| Проблема | Причина / Фикс |
|---|---|
| `nginx: [emerg] invalid value "http_400"` | ✅ Старый deploy (до фикса). Уже исправлено — удаляем `rm -f /etc/nginx/sites-enabled/animanga*` и запускаем `sudo bash deploy.sh` повторно. |
| Главная страница «Страница готовится. Загляните через час» | ✅ web-root не скопировался — исправлено в новом deploy шаг 4 (ВСЕГДА копирует все HTML). Или руками `cp -a /root/animanga-cdn/web-root/. /var/www/<ORIGIN_DOMAIN>/` |
| `CDN Bridge HTTP 403` | ✅ В VK Cloud X-Origin-Secret header НЕВЕРНЫЙ (слишком короткий, или пробел в конце, или не тот секрет). Перекопируй точный из `state/origin-secret.txt`. |
| `CDN Bridge HTTP 502/504` | ✅ В VK Cloud Protocol с источником стоит **HTTP вместо HTTPS** или указан порт в источнике. Поставь HTTPS, без порта, origin host = `<ORIGIN_DOMAIN>`. |
| Client «пинга нет вообще» | ✅ 1) Заменить `uuid` на **`vlessUuid`** из Remnawave Users. 2) В клиенте Address / SNI / Host → `<CDN_DOMAIN>`, не `<ORIGIN_DOMAIN>`. 3) JSON xhttp extra params — **ТОЧНО как в хосте Remnawave**. |
| nginx не стартует с `emerg cannot load certificate` | ✅ LE cert не получил — использует self-signed fallback. Убедись что 80 порт открыт снаружи (ufw allow 80), DNS A-запись указывает на сервер, затем перезапусти `sudo bash deploy.sh`. |

---

## 🔐 Безопасность / OPSEC

- ✅ **В state/origin-secret.txt и state.env — ТВОЙ уникальный секрет!** Никогда не публикуй файлы из `/state/` в интернет и не закоммить в Git (уже в `.gitignore`).
- ✅ Сайт-заглушка 100% OPSEC: **НИКАКИХ** упоминаний `xhttp / xray / vless / tunnel / vpn / remna / warden / bridge / secret` ни в одном статическом HTML файле.
- ✅ Nginx `server_tokens: off; X-Powered-By: AniMangaCDN/3.4` — не палится версия nginx.
- ✅ Два порта только публичные **80/443** (5448 inbound + 20080 dummy слушают ТОЛЬКО 127.0.0.1 → world недоступны).

---

## 🎯 Как запушить этот репозиторий на GitHub

```bash
# 1. Создай пустой репозиторий на github.com/new — НЕ add README, НЕ add .gitignore
# 2. Вернись на сервер:
cd /root/animanga-cdn
git remote add origin https://github.com/TВОЙ-НИКНЕЙМ/animanga-cdn.git
git branch -M main
git push -u origin main
# 3. Вводи GitHub username + password/token (Fine-grained token if 2FA)
```

Готово. Теперь на **ЛЮБОМ** новом сервере достаточно склонировать реп, отредактировать 7 строк в deploy.sh → запустить → работает.
