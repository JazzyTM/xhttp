# xhttp

> AniManga.SU — Origin + CDN xHTTP Bridge Template
> Универсальный zero-error деплой на **Ubuntu 22.04 / 24.04, Debian 12** за 5 минут.
> Реалистичный аниме-стриминг OPSEC-сайт + Nginx мост до Remnanode/xray-core inbound через VK Cloud CDN.

---

## ✅ Фичи

| Фича | Статус |
|---|---|
| **Nginx 1.24.x compatible** | ✅ Без `http_400/http_404` в proxy_next_upstream — нет `invalid value emerg` |
| **2 URL пути моста** (Path A + B) | ✅ `/stream/v2/chapters/segments` + `/cdn/v3/media/hls/fragments` |
| **X-Origin-Secret auth** | ✅ 56-символьный статический или авто-генерируемый unique |
| **Upstream backup dummy OK JSON 200** | ✅ Если Xray упал или не отвечает → CDN край **не видит 502/503**, вместо этого HTTP 200 `{"status":"ok","service":"animanga-cdn-bridge"...}` |
| **Реалистичный аниме-сайт** | ✅ 8 HTML-страниц (главная + каталог + расписание + манга + о проекте + правообл + соглашение + приватность), 3759 строк, OPSEC clean (0 упоминаний xhttp/xray/vless/tunnel) |
| **Универсальный CSS + JS** | ✅ `style.css` 3892 строки, `app.js` 1120 строк — тема/поиск/слайдер/фильтры/формы/toast/scroll-top/scroll-spy |
| **Let's Encrypt certbot webroot** | ✅ Авто-получение сертификата, fallback self-signed snakeoil (nginx **всегда стартанёт**, даже без DNS/wan) |
| **UFW firewall** | ✅ Открыто **ТОЛЬКО 22 / 80 / 443**. Все остальные порты (10065, 10066) — закрыты. |
| **Remnanode JSON конфиги** | ✅ Inbound `vkcdn-germany:5448` VLESS xHTTP packet-up, routing direct+block geoip:private, host xhttp extra params (`scMaxEachPostBytes=1052672-2105344`, `hMaxRequestTimes=600-900`, `hMaxReusableSecs=1800-3000` и мн.др.) |
| **Скрипты zero-error** | ✅ `deploy.sh` (601 строка, 7 шагов) + `verify.sh` (288 строк, 6 блоков). Идемпотентны, never fail hard |
| **Git safe** | ✅ `.gitignore` — state/, секреты, .env, .key НИКОГДА не попадают в репозиторий |

---

## 🚀 Быстрый деплой на новый сервер

Полная пошаговая инструкция: [QUICKDEPLOY.md](./QUICKDEPLOY.md) (200 строк).

**7 шагов сокращённо:**

```bash
# 1. Клонируем
apt update && apt install -y git rsync
git clone https://github.com/JazzyTM/xhttp.git /root/animanga-cdn
cd /root/animanga-cdn

# 2. Редактируем ТОЛЬКО 7 строк в deploy.sh (строки 20-30)
nano deploy.sh
# ORIGIN_DOMAIN="video-quality.yourdomain.su"
# CDN_DOMAIN   ="video-fast.yourdomain.su"
# XRAY_PORT="5448"
# XRAY_DUMMY_OK_PORT="20080"
# PATH_A="/stream/v2/chapters/segments"
# PATH_B="/cdn/v3/media/hls/fragments"
# ORIGIN_SECRET=""   ← оставь пустым, сгенерит уникальный сам

# 3. Запускаем деплой (одна команда — ВСЁ СДЕЛАЕТ САМ!)
chmod +x deploy.sh verify.sh
sudo bash deploy.sh

# 4. VK Cloud CDN панель: Protocol = HTTPS, origin = https://<ORIGIN_DOMAIN>,
#    Host header = <ORIGIN_DOMAIN>, custom header X-Origin-Secret = значение из state/origin-secret.txt

# 5. Remnanode Hosts → ДВА ХОСТА (Origin SNI + CDN SNI), оба xhttp extra params = configs/host-xhttp-extra-portB.json
#    → SAVE → RELOAD NODE!

# 6. Клиент (NekoBox/V2rayN/Matsuri): Address/SNI/Host = <CDN_DOMAIN> (через CDN!),
#    UUID = vlessUuid из Remnanode Users (НЕ обычный uuid!), xhttp Extra = ТОТ ЖЕ JSON!

# 7. Проверка ВСЕХ 6 блоков
bash verify.sh
```

---

## 📁 Структура репозитория

```
animanga-cdn/
├── deploy.sh                    # 🚀 Главный скрипт деплоя (7 шагов)
├── verify.sh                    # ✅ Диагностический скрипт (6 блоков)
├── QUICKDEPLOY.md               # 📖 How-to деплой на новый сервер за 5 минут
├── .gitignore                   # 🔐 state/секреты/временные не в коммит
│
├── configs/                     # ⚙️ Remnanode + Nginx конфиги
│   ├── config-profile-inbound.json      # Inbound vkcdn-germany 5448 VLESS + xHTTP packet-up
│   ├── host-xhttp-extra-portA.json      # xHTTP доп. параметры (маскировка Path A)
│   ├── host-xhttp-extra-portB.json      # xHTTP доп. параметры (маскировка HLS CDN Path B)
│   ├── routing-outbound-direct.json     # Outbounds direct freedom BBR+TFO + blackhole, routing
│   └── nginx-origin.conf                # Статический origin nginx (deploy.sh пишет динамический)
│
├── web-root/                    # 🌐 Реальный аниме-стриминг сайт OPSEC-clean
│   ├── index.html               # Главная (hero, статистика, каталог, расписание, манга, подписка, футер)
│   ├── projects.html            # Каталог 12 аниме + фильтры слева + сортировка + пагинация
│   ├── schedule.html            # Расписание 7 дней × 5–6 тайтлов с обложками и статусами
│   ├── manga.html               # Каталог 15 манги/манхв/ранобэ (прогресс, типы, рейтинги)
│   ├── about.html               # О проекте, команда, миссия, контакты
│   ├── copyright.html           # Правообладателям (DMCA-like + HTML форма)
│   ├── tos.html                 # Пользовательское соглашение (8 глав, ~40 абзацев)
│   ├── privacy.html             # Политика конфиденциальности (35 разделов, 152-ФЗ + GDPR)
│   ├── css/style.css            # 🎨 Универсальный CSS (3892 строки, 76 КБ)
│   ├── js/app.js                # 🧠 Универсальный JS (1120 строк, 40 КБ)
│   └── favicon.svg              # Favicon градиент фиолет→голуб + AM
│
├── remnanode/                   # 📡 Docker-compose опционально (если надо локальный remnanode)
│   └── docker-compose.yml
│
└── state/                       # 🔐 Сгенерированное состояние (НИКОГДА НЕ ПУШИТЬ!)
    ├── state.env                # SAVED_ORIGIN_SECRET + все параметры
    └── origin-secret.txt        # Чистый X-Origin-Secret (56 символов)
```

---

## 🐛 Частые фиксы (см. также QUICKDEPLOY → Частое проблемы)

| Ошибка | Фикс за 10 секунд |
|---|---|
| `nginx: invalid value "http_400" in sites-enabled/animanga:74` | `rm -f /etc/nginx/sites-enabled/animanga* /etc/nginx/sites-enabled/default; sudo bash deploy.sh` |
| Главная = "Страница готовится. Загляните через час" | `rm -rf /var/www/<ORIGIN_DOMAIN> && cp -a /root/animanga-cdn/web-root/. /var/www/<ORIGIN_DOMAIN>/; chown -R www-data:www-data /var/www/<ORIGIN_DOMAIN>; systemctl reload nginx` |
| CDN Bridge `HTTP 403` | В VK Cloud X-Origin-Secret **не совпадает** с `state/origin-secret.txt` — перекопируй без пробелов |
| CDN Bridge `HTTP 502/504` | В VK Cloud Protocol = **HTTP вместо HTTPS** → исправь на HTTPS, убирай номер порта из origin |
| Клиент «пинга нет вообще» | 1) Заменить uuid → **vlessUuid**, 2) Address/SNI/Host → `<CDN_DOMAIN>` (не origin!), 3) xhttp Extra params JSON → ТОЧНО как в Remnanode Hosts |

---

## 🔐 Безопасность

- ✅ `state/`, `*.env`, `*.key`, `privkey.pem` — **в .gitignore**, никогда не коммитятся.
- ✅ Все статические файлы веб-сайта сканированы: **НУЛЕВОЕ** количество запрещённых строк (`xhttp`, `xray`, `vless`, `tunnel`, `vpn`, `bridge`, `secret`, `remna`, `warden`, `socks`, `vmess`, `trojan`).
- ✅ Nginx `server_tokens: off`; `X-Powered-By: AniMangaCDN/3.4`; HSTS + CSP-friendly headers.
- ✅ Inbound 5448 / dummy OK 20080 → **listen 127.0.0.1 only** (не торчат наружу, ufw всё равно закрывает).

---

## 📄 Лицензия

Use-only-template. Держи форк, меняй домены, используй в своих проектах.
