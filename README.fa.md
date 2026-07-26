# نصب حرفه‌ای Tailscale روی Ubuntu

[![Ubuntu 20.04+](https://img.shields.io/badge/Ubuntu-20.04%2B-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![ShellCheck](https://img.shields.io/badge/lint-ShellCheck-4EAA25?logo=gnu-bash&logoColor=white)](https://www.shellcheck.net/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) | **فارسی**

این پروژه یک نصب‌کنندهٔ امن، قابل تکرار و مناسب محیط عملیاتی برای نصب و
راه‌اندازی Tailscale روی Ubuntu Server است. نصب از مخزن رسمی APT انجام می‌شود
و خبری از اجرای مستقیم `curl | sh` نیست.

> این یک پروژهٔ مستقل جامعه‌محور است و وابستگی یا تأیید رسمی از طرف
> Tailscale Inc. ندارد.

## قابلیت‌ها

- تشخیص Ubuntu و codename نسخه
- استفاده از مخزن رسمی و اختصاصی همان نسخهٔ Ubuntu
- نصب idempotent؛ اجرای دوباره باعث ایجاد تنظیمات تکراری نمی‌شود
- فعال‌سازی و کنترل سلامت سرویس `tailscaled`
- ورود تعاملی یا provision خودکار با auth key
- عبور امن‌تر کلید با `--auth-key=file:...` به‌جای قرار دادن مقدار کلید در
  آرگومان پردازش
- پشتیبانی از hostname، tag، Tailscale SSH، subnet routes و operator محلی
- اعتبارسنجی فایل مخزن، کلید OpenPGP، hostname، tag و سطح دسترسی فایل secret
- حالت dry-run و پیام خطای قابل پیگیری
- تست خودکار، ShellCheck، CI، قالب Issue/PR، سیاست امنیتی و ساخت Release
- مستندات کامل انگلیسی و فارسی

## پیش‌نیازها

- Ubuntu 20.04 یا جدیدتر
- وجود codename نسخه در
  [مخزن رسمی Tailscale](https://pkgs.tailscale.com/stable/)
- `systemd`
- دسترسی root
- دسترسی HTTPS خروجی به mirrorهای Ubuntu و `pkgs.tailscale.com`

نسخه‌های هدف اصلی Ubuntu 22.04 LTS و 24.04 LTS هستند. نسخه‌های جدیدتر پشتیبانی
شده نیز به‌صورت پویا از `VERSION_CODENAME` استفاده می‌کنند.

## شروع سریع

بعد از استخراج ZIP، ابتدا اسکریپت را مرور و سپس اجرا کنید:

```bash
chmod +x install.sh
sudo ./install.sh --login
```

اگر فقط نصب می‌خواهید و ورود را بعداً انجام می‌دهید:

```bash
sudo ./install.sh
sudo tailscale up
```

اسکریپت به‌صورت پیش‌فرض کل سیستم را upgrade نمی‌کند. این تصمیم از تغییرات
ناخواسته و reboot احتمالی روی سرور جلوگیری می‌کند.

## راه‌اندازی خودکار سرور

در پنل Tailscale یک auth key ترجیحاً tagged، pre-authorized و یک‌بارمصرف
بسازید. سپس آن را داخل فایلی با دسترسی محدود قرار دهید:

```bash
sudo install -m 600 /dev/null /run/tailscale-authkey
sudoedit /run/tailscale-authkey

sudo ./install.sh \
  --auth-key-file /run/tailscale-authkey \
  --hostname app-01 \
  --advertise-tags tag:server \
  --ssh
```

پس از راه‌اندازی موفق، اگر secret manager چرخهٔ عمر فایل را مدیریت نمی‌کند،
فایل کلید را حذف کنید.

## چند مثال کاربردی

مشاهدهٔ عملیات بدون تغییر پایدار سیستم:

```bash
sudo ./install.sh --dry-run --no-color
```

پذیرش routeهای منتشرشده توسط subnet routerها:

```bash
sudo ./install.sh --login --accept-routes
```

اجازهٔ مدیریت Tailscale به کاربر محلی `ubuntu`:

```bash
sudo ./install.sh --login --operator ubuntu
```

استفاده از کانال unstable:

```bash
sudo ./install.sh --channel unstable --login
```

upgrade کامل بسته‌های سیستم پیش از نصب:

```bash
sudo ./install.sh --upgrade-system --login
```

## گزینه‌ها

| گزینه | کاربرد |
| --- | --- |
| `--login` | شروع ورود تعاملی با URL مرورگر |
| `--no-login` | فقط نصب؛ رفتار پیش‌فرض |
| `--auth-key-file PATH` | ورود خودکار با فایل کلید محافظت‌شده |
| `--hostname NAME` | تعیین نام دستگاه در Tailscale و MagicDNS |
| `--advertise-tags TAGS` | انتشار tagهایی مانند `tag:server,tag:linux` |
| `--ssh` | فعال‌کردن Tailscale SSH؛ policy شبکه همچنان تعیین‌کننده است |
| `--accept-routes` | پذیرش routeهای subnet |
| `--operator USER` | اجازهٔ مدیریت daemon به یک کاربر محلی موجود |
| `--channel TRACK` | انتخاب `stable` یا `unstable` |
| `--upgrade-system` | فعال‌کردن اختیاری `apt-get upgrade` |
| `--dry-run` | نمایش دستورات بدون تغییر پایدار |
| `--no-color` | حذف رنگ‌های ANSI |
| `--help` | نمایش راهنما |
| `--version` | نمایش نسخهٔ installer |

## نکات امنیتی مهم

- مقدار auth key در خروجی چاپ نمی‌شود.
- فایل auth key نباید برای group یا other قابل خواندن باشد؛ `chmod 600`
  پیشنهاد می‌شود.
- متغیر `TS_AUTHKEY` برای سازگاری با CI قابل استفاده است، اما secret file
  mount شده گزینهٔ بهتری است.
- گزینهٔ `--ssh` به‌تنهایی دسترسی ایجاد نمی‌کند؛ policyهای Tailnet همچنان
  باید اجازهٔ اتصال را بدهند.
- غیرفعال‌کردن key expiry را فقط برای دستگاه قابل اعتماد و با پذیرش ریسک
  انجام دهید؛ این installer آن را خودکار غیرفعال نمی‌کند.
- قبل از اجرای production، فایل
  [نکات امنیتی](docs/SECURITY-NOTES.md) را مطالعه کنید.

## توسعه و تست

اجرای همهٔ بررسی‌های محلی:

```bash
make check
```

ساخت ZIP قابل انتشار:

```bash
make package
```

برای جزئیات بیشتر فایل‌های
[راهنمای استفاده](docs/USAGE.md)،
[رفع اشکال](docs/TROUBLESHOOTING.md) و
[مشارکت](CONTRIBUTING.md) را ببینید.

## منابع رسمی

- [نصب Tailscale روی Linux](https://tailscale.com/docs/install/linux)
- [بسته‌های stable رسمی](https://pkgs.tailscale.com/stable/)
- [مرجع tailscale up](https://tailscale.com/docs/reference/tailscale-cli/up)
- [راه‌اندازی سرور Tailscale](https://tailscale.com/docs/how-to/set-up-servers)
- [مرجع CLI](https://tailscale.com/docs/reference/tailscale-cli)

## مجوز

این پروژه تحت [مجوز MIT](LICENSE) منتشر شده است.
