# Android USB Camera — önsürüm

Android ekranını USB üzerinden Mac'te bir video yakalama aygıtına aktarır. Pencere yakalama kullanmaz.

1. Android cihazında USB hata ayıklamayı aç, Mac'e bağla ve cihaz ekranındaki yetkilendirmeyi onayla.
2. Android USB Camera uygulamasını aç. Bağlı ve yetkili cihazlar otomatik algılanır. Birden fazla cihaz varsa listeden seç.
3. OBS'de Video Yakalama Aygıtı kaynağı ekle ve OBS Virtual Camera aygıtını seç.
4. OBS'nin Sanal Kamerayı Başlat düğmesi kapalı kalmalı. Bu aygıta görüntüyü köprü gönderir.
5. Stop/Start düğmeleriyle durdurup yeniden başlatabilirsin. USB bağlantısı değiştiğinde Refresh devices ile cihazları yenileyebilirsin.

Gereksinimler: Apple Silicon Mac, macOS 13 veya sonrası hedefi; etkin OBS Virtual Camera uzantısı; Android'de bildirilen H.264 donanım kodlayıcısı. Fiziksel testler Astra ve S24 Ultra ile yapıldı. Yazılımda model kısıtlaması yok; bütün Android cihazlarının uyumluluğu henüz doğrulanmadı.

Tek kamera aygıtı ve tek aktif cihaz destekleniyor. Çıkış 1920×1080; görüntü oranı siyah kenarlarla korunur. Kamera saniyede 60 kare gönderirken sabit görüntüyü tekrar kullanabilir; bu 60 farklı Android karesi anlamına gelmez. Ses ve HDR yok.

Bu önsürüm Apple tarafından notarize edilmedi. Diğer Mac'lerde sorunsuz kurulabilen genel dağıtım paketi için Developer ID imzalama ve Apple noter onayı gerekir. Ayrıntılar README.md ve RELEASE.md içindedir.

Çalışan eski sürüm ayrı tarihli yedekte korunmuştur. Yedekteki kişisel OBS sahne dosyasını herkese açık kaynak deposuna ekleme.
