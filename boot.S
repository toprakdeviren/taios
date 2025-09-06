// boot.S - ARM64 bootloader

.section .text.boot        // Bu kodu .text.boot isimli özel bir bölüme koyar
.global _start             // _start etiketini global yapar (linker giriş noktası olacak)

// Exception Vector Table
.align 11                  // 2^11 = 2048 bayt hizalama (ARM64 şartı)
exception_vector_table:    // Exception vector tablosu başlangıcı
    .rept 16               // 16 adet exception vektörü (her biri 128 bayt)
        .align 7           // 2^7 = 128 bayt hizalama
        b hang             // Şimdilik tüm exception’lar "hang" fonksiyonuna gider
    .endr

// --------------------- BOOT ENTRY ------------------------
_start:
    // Interrupt’ları kapat (DAIF = Debug, SError, IRQ, FIQ)
    msr daifset, #0xf      // DAIF registerındaki tüm mask bitlerini set et

    // Mevcut Exception Level’ı oku
    mrs x0, CurrentEL      // CurrentEL register’ını x0’a al
    and x0, x0, #0xC       // Sadece [3:2] bitlerini maskele (EL seviyesi)
    cmp x0, #0x8           // EL2 (0b1000) mi?
    b.eq init_el2          // Evetse init_el2’ye git
    cmp x0, #0x4           // EL1 (0b0100) mi?
    b.eq init_el1          // Evetse init_el1’e git
    b init_el3             // Değilse EL3 kabul et, init_el3’e git

// --------------------- EL3 → EL2 -------------------------
init_el3:
    // EL3’ten EL2’ye geçiş
    mov x0, #0x80000000    // SCR_EL3: RW=1 → alt seviye AArch64 çalışacak
    msr scr_el3, x0
    mov x0, #0x3c9         // SPSR_EL3: Hedef = EL2h, interrupt’lar maskeli
    msr spsr_el3, x0
    adr x0, init_el2       // init_el2 adresini al
    msr elr_el3, x0        // ELR_EL3’e yaz (eret sonrası PC buraya gider)
    eret                   // Exception return → EL2’ye atla

// --------------------- EL2 → EL1 -------------------------
init_el2:
    // EL2’den EL1’e geçiş
    mov x0, #0x80000000    // HCR_EL2: RW=1 → alt seviye AArch64 çalışacak
    msr hcr_el2, x0
    mov x0, #0x3c5         // SPSR_EL2: Hedef = EL1h, interrupt’lar maskeli
    msr spsr_el2, x0
    adr x0, init_el1       // init_el1 adresini al
    msr elr_el2, x0        // ELR_EL2’ye yaz
    eret                   // Exception return → EL1’e atla

// --------------------- EL1 INIT --------------------------
init_el1:
    // Artık EL1’deyiz (kernel modu)

    // Exception vector tablosunu ayarla
    adr x0, exception_vector_table // Tablonun adresini al
    msr vbar_el1, x0               // VBAR_EL1’e yaz

    // Stack pointer’ı ayarla
    ldr x0, =_stack_top   // Linker script’ten stack top sembolünü al
    mov sp, x0            // sp register’ına yaz

    // Floating Point / SIMD kullanımını aç
    mrs x0, cpacr_el1     // CPACR_EL1 register’ını oku
    orr x0, x0, #(3 << 20)// FPEN bitlerini 11 yap (FP/SIMD serbest)
    msr cpacr_el1, x0     // Geri yaz
    isb                   // Instruction barrier (etkin olsun diye)

    // C tarafındaki kernel girişine zıpla
    bl kernel_main        // kernel_main() fonksiyonunu çağır

// --------------------- HANG LOOP -------------------------
hang:
    wfe                   // Wait For Event (düşük güç bekleme)
    b hang                // Sonsuz döngü
