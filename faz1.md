![TAI-OS ARM 64 İşletim Sistemi](https://media.licdn.com/dms/image/v2/D4D12AQGhvPaLtR_JzQ/article-cover_image-shrink_720_1280/B4DZkeN7UnH4AM-/0/1757148592669?e=1759968000&v=beta&t=3Yjh5pFzsqBFfHbP4RtIFOo26Ocf9Zh79_uhRSF9XY0)

TAI-OS ARM 64 İşletim Sistemi

Sıfırdan ARM64 İşletim Sistemi Geliştirme - Faz 1
=================================================

> Bu çok uzun bir yolculuğun ilk adımı. Fakat önce şunu izah etmek istiyorum. Bu projeyi Apple Internals'i daha iyi anlamak için FreeBSD kaynak kodundan yararlanarak başladığım işletim sisteminin nasıl ve neden geliştirdiğimi anlatan bir eğitim serisi olacak.

2009 yılından bu yana Apple ekosistemi içindeyim, XCode, LLVM ve sistem tarafıyla mecburen çok fazla muhattap olmak durumunda kaldım. Bunların bir kaç sebebi vardı, anlatırsam uzar gider. Başınızı ağrıtmaya gerek yok.

Apple Internals her zaman ilgimi çekti, çünkü Linux bana toplama bir işletim sistemi geliyordu. Her zaman bir olmamışlık hissi beni çok rahatsız ediyordu. Ama FreeBSD bir sanatçıcının ustalık eseri olarak, zümrüt gibi orada parlıyordu. Ve bu BSD üzerine kurulmuş, dünyayı sarsan ve bir çok saçmalığı da olsa, yerini kimsenin dolduramadığı bir işletim sistemi Apple vardı. Ve bu işletim sistemine hakim olamamak, ayağımı bastığım yeri sağlam hissedememek beni rahatsız ediyordu. Bu sebeple bir çok kaynak ve kitap okudum. Ayrıca Apple'ın open source kaynak kodlarını uzun uzun inceledim. Ve sonucunda bir çok kavram kafamda oturmaya başladı.

Bu şunu getirdi; **Darwin, XNU, Mach** (bunların hepsini Apple Internals eğitim serisinde anlatacağım inşallah) seviyesine inip anlamaya başlayınca, Apple internals ile uğraşmanın ödülü geliyor:

1.  **EXC\_BAD\_ACCESS (SIGSEGV)** logunda, backtrace’te **objc\_release** mi, **swift\_retain mi**, **CFArrayGetValueAtIndex** mi patladı, artık daha iyi görmeye başlıyorsun.
2.  **mach\_exception** kodlarını **0x8 = EXC\_BAD\_INSTRUCTION** gibi çözüp, crash’in pointer mı, alignment mı, illegal instruction mı olduğunu ayırmaya başlıyorsun.
3.  Xcode’un kendi crash’lerinde bile **_"burada NSMutableArray out of bounds, bunu debug etmeden 20 senedir nasıl devam edebiliyorlar"_** diyebiliyorsun.

Ayrıca başka başka faydaları da var, öncelikle niş bir alan. Apple Internals ile ilgilenen developer sayısı çok çok azdır. O yüzden söz sahibi olma şansı da doğuyor her neyse :D

> Bazen Apple'da çalışmak dışarıdan çalışmak çok havalı gözüküyor ama içeride mühendisler muhtemelen, **dyld\_shared\_cache** **dump edip**, **objc\_methname** section’da string arıyor, sonra **mach\_header** offsetiyle uğraşıyor, crashlog çözüp **malloc\_zone\_t** pointer leak’lerini kovalamakla günü geçiyor. Fen'de çok ilerledik bir yerde durmamız gerekiyor :D

Apple'a ara sıra **Eşşek Apple** dememin sebebi aslında buralar. Dışarıdan boyalı içerisi böcük dolu, hani böyle bir taşı kaldırırsın altında bir sürü böcük sağa sola kaçışır ya :D İşte Apple O. Ama normal ya. Her neyse Apple magazini sonraya bırakalım, orada anlatılacak çok eğlenceli yerler var biz şimdi sıkıcı kısma geçelim :D

* * *

boot.S, Başlangıç noktası
-------------------------

![Makale içeriği](https://media.licdn.com/dms/image/v2/D4D12AQHaxAkndxSPaA/article-inline_image-shrink_1500_2232/B4DZkeTnqeIEAY-/0/1757150089850?e=1759968000&v=beta&t=cMspHug6V6t3jAMX3oze0JtpB6BGdpDxpVYuhmokGGI)

boot.S başlangıç noktası

boot.S Nedir? Neden Var?
------------------------

boot.S, TAI-OS çekirdeğinin **ilk çalışan** (entry-stage) kodudur. Bu dosya:

*   CPU’yu **tanımlı bir başlangıç durumuna** getirir (interrupt maskeleri, istisna vektör tablosu vb.),
*   Mimariye özel ARM64 **donanım kayıtlarını** ayarlar,
*   Sonraki aşamada C koduna kernel güvenle geçişe zemin hazırlar.

Bu seviyede C çalışma zamanı henüz hazır değil**.** (stack, .bss temizliği, global init vs. yapılmamıştır). Bu yüzden boot aşamasında **assembly** tercih edilir. boot.S ayrıca **linker script** ile yakından ilişkilidir: kodun hangi bellek bölümüne yerleşeceğini, vektör tablosunun hizalamasını ve giriş sembolünü \_start linker belirler.

> Kısaca CPU’yu deterministik hale getir, minimum gereklileri kur, sonra C’ye bırak.

* * *

1.  Dosya uzantısının .S **(büyük S)** olması GNU as’ın **C-önişlemcisini** de cpp çalıştırmasına izin verir ki böylelikle macro ve #define önişlemcileri kullanabilelim
2.  ARM64 için aarch64-none-elf- veya aarch64-linux-gnu- toolchain’ler yaygındır.
3.  Linker, ENTRY(\_start) ile giriş noktasını \_start sembolüne bağlar;

Normal de tüm boot.S i anlatacaktım ama bu kısma olanı anlatacağım ki, çok sıkıcı olmasın ki zaten yeterince sıkıcı oldu :D

* * *

Boot Entry’ye Kadar, Satır Satır Açıklama
-----------------------------------------

### 1) Dosya üst bilgisi

    // boot.S - ARM64 bootloader

*   Yalnızca bilgilendirme amaçlı bir yorum.

* * *

### 2) Özel kod bölümü seçimi

    .section .text.boot

Bu direktif, derleyiciye ve linker'e bu kodun .text.boot isimli **ayrı bir kod bölümüne** konulacağını söyler.

Peki neden ayrı bir bölüm? Cevap: Linker script’te genelde şöyle bir blok olur:

### Giriş sembolünü dışa açma

    .global _start

*   \_start etiketini **global** görünür yapar.
*   Linker, ENTRY(\_start) ile program girişini bu sembole bağlar.

* * *

### Exception Vektör Tablosu Başlığı

    // Exception Vector Table
    .align 11
    exception_vector_table: 

*   **Amaç:** ARM64’te istisna (exception) vektör tablosu, **2048 bayt hizalı** bir adreste olmalıdır.
*   exception\_vector\_table: etiketi, tablonun **başlangıç adresini** belirler.

Not: Bazı platformlarda .align 2^n hizalama iken bazılarında n bayt hizalama davranabilir. ARM64 tarafında 2^n olarak çalışır; **en güvenlisi** .balign 2048 kullanmaktır. Eğitim metninde .align 11 yeterli, ama üretimde: .balign 2048 olmalı.

Ayrıca;

### Bu tabloyu .vectors gibi ayrı bir bölüme koyup linker’da

    .vectors ALIGN(2048) : { KEEP(*(.vectors)) }

ile **çöp toplayıcıdan korunmuş** ve zorunlu hizalanmış hale getirmek iyi pratiktir. Bu örnekte tablo .text.boot içindedir; yine de hizalama garantili olduğu sürece sorun yok.

### 16 Adet Vektör Slotu Üretme

    .rept 16
        .align 7
           b hang
    .endr

Bu blok, **16 adet** vektör girişini minimal bir “iskele” ile üretir:

**.rept 16, .endr:** İçerideki talimatları 16 kez tekrarlar. ARMv8-A, AArch64 vektör tablosunun 16 slotu vardır:

![Makale içeriği](https://media.licdn.com/dms/image/v2/D4D12AQFyo-kfCI60Ew/article-inline_image-shrink_1000_1488/B4DZkeXNm0IYAQ-/0/1757151031824?e=1759968000&v=beta&t=tkxHRFMaGlxQ8gR_7GC9rAdddXJKJTFUeqHmzHqUrn0)

boot.S Vektör Tablosu

**.align 7 → 2^7 = 128 bayt hizalama:** ARM64’te her vektör girişi 128 baytlık bir slot kabul edilir. Burada her tekrarın başında hizalama ile bir sonraki 128 bayt sınırına atlanır.

**b hang:** Her slotun ilk talimatı, şimdilik basitçe hang fonksiyonuna dalan bir branch. Bu minimalist yaklaşım şunları garanti eder:

1.  Her istisna, geçici olarak aynı "bekleme" döngüsüne yönlendirilir _(sistem donmaz, kontrol sizde kalır)_.
2.  Slotların geri kalan padding alanı, .align sayesinde otomatik doldurulur; böylece bir sonraki slot tam 128 bayt sınırında başlar

> _Not:_ **_“128 bayt slot = 128 bayt kod yazmak zorundasın”_** _demek değildir. İlk komut (branch) fiilen birkaç bayt; kalan alan_ **_hizalama dolgusu_**_. Donanım,_ **_slot başlangıcındaki_** _kodu yürütür; içeride daha sonra ister ayrıntılı handler, ister kayıt dökümü koyabilirsiniz._

Bu tarz doldurmalar genelde kriptografide de vardır ama konumuz bu değil. Konu bu değil olm, konu bu değil :D

### Bu Noktada Ne Oldu?

*   **Vektör tablosu** 2048B hizayla belleğe yerleştirildi.
*   İçinde **16 adet**, 128B hizalı **slot** üretildi.
*   Tüm slotlar, şimdilik güvenli bir yere (sonsuz bekleme döngüsü hang) **branch** ediyor.
*   Henüz **VBAR\_EL1, EL2, EL3** gibi kayıtlar **ayarlanmadı** (bu, Boot Entry’den sonra yapılacak iş). Yani tabloyu **oluşturduk**, ama CPU’ya "**vektör tabanın bu"** demedik. O kısım \_start sonrasındaki init aşamasında.

Gördüğünüz gibi, **BOOT ENTRY** kısmına anca gelebildik. Ama burada duralım onu diğer makaleye bırakalım. Eğer ikinci makaleye geçerseniz, bu işi sevdiniz demektir. Bırakırsanız da çok normal, çünkü çok sıkıcı :D

Boot Entry kısmı da şu şekilde gözükecek en azından fikir olması açısından;

![Makale içeriği](https://media.licdn.com/dms/image/v2/D4D12AQHCV0nsDuCBLQ/article-inline_image-shrink_1500_2232/B4DZkedoiOJgAU-/0/1757152725986?e=1759968000&v=beta&t=xTjll_dmvjryflTmbX_8ZxUYk8OpKglKoupfOL0-r5E)

boot.S Entry
