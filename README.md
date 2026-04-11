# nmap-unprivileged

Форк [nmap](https://github.com/nmap/nmap) для air-gapped Linux-систем (RHEL, Astra Linux, Debian).

**Отличия от upstream:**
- Сборка полностью офлайн — все зависимости бандлированы (libpcap, libdnet, libpcre, lua, OpenSSL 3.4.1)
- Сканирование сырыми сокетами (`-sS`, `-sU`, `-O`) заблокировано — работа без `root` и `CAP_NET_RAW`
- TCP connect (`-sT`), определение сервисов (`-sV`), NSE-скрипты — работают
- Не собираются: nping, ncat, ndiff, zenmap

---

## Как билдить

### Требования

| Пакет | Зачем | Обязателен |
|-------|-------|------------|
| `gcc`, `g++`, `make` | компиляция C и C++ кода | да |
| `perl` | сборка OpenSSL (его `./Configure`) | да |
| `libtext-template-perl` / `perl-Text-Template` | perl-модуль, нужен OpenSSL 3.x | да |
| `linux-libc-dev` / `kernel-headers` | заголовки ядра Linux (`linux/limits.h` и др.) | да |
| `javac` (JDK) | компиляция JDWP NSE-классов | нет |

На RHEL/CentOS:
```sh
yum install gcc gcc-c++ make perl perl-Text-Template kernel-headers
```

На Debian/Ubuntu/Astra Linux:
```sh
apt-get install build-essential perl libtext-template-perl linux-libc-dev
```

### Сборка

```sh
git clone https://github.com/chemrid/nmap-unprivileged.git
cd nmap-unprivileged
sh build-offline.sh
```

Скрипт выполняет:
1. Очистку предыдущих артефактов (`make distclean`)
2. Правку CRLF-окончаний строк (если источники клонированы на Windows)
3. Компиляцию JDWP `.class`-файлов из `.java` (если есть `javac`)
4. Сборку OpenSSL 3.4.1 как статической библиотеки → `openssl-build/`
5. `./configure` + `make`

### Артефакт после сборки

После `build-offline.sh` готовый бинарник находится в корне репозитория:

```
nmap-unprivileged/
└── nmap          ← готовый бинарник
```

Бинарник статически слинкован с OpenSSL — внешних `.so`-зависимостей нет.

---

## Установка

### Вариант 1 — `make install` (в `/usr/local`)

```sh
make install
```

Устанавливает:
- `/usr/local/bin/nmap`
- `/usr/local/share/nmap/` — data-файлы (`nmap-services`, `nmap-os-db`, скрипты и др.)

### Вариант 2 — кастомный prefix

```sh
./configure --prefix=/opt/nmap-unpriv \
  --without-nping --without-ndiff --without-zenmap --without-ncat \
  --without-libssh2 \
  --with-openssl="$(pwd)/openssl-build" \
  --with-libpcap=included \
  --with-libdnet=included \
  --with-lua=included
make -j$(nproc)
make install
```

Результат: всё в `/opt/nmap-unpriv/`.

### Вариант 3 — ручное копирование бинарника

Если нужна минимальная установка без `make install`:

```sh
cp nmap /usr/local/bin/
mkdir -p /usr/local/share/nmap
cp nmap-services nmap-os-db nmap-protocols nmap-rpc nmap-mac-prefixes \
   nmap-service-probes /usr/local/share/nmap/
cp -r scripts/ /usr/local/share/nmap/scripts/
```

Либо запускать с явным `--datadir`:
```sh
nmap --datadir /path/to/nmap-unprivileged <target>
```

---

## Проверка

```sh
./nmap -sT -sV localhost        # TCP connect + определение сервисов
./nmap --script=http-title localhost -p 80
./nmap -sS localhost            # должно вернуть: "requires root"
```

---

## Лицензия

Nmap распространяется под собственной лицензией (на основе GPLv2).
OpenSSL 3.4.1 — Apache License 2.0.
Подробнее: [nmap.org/book/man-legal.html](https://nmap.org/book/man-legal.html)
