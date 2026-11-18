# Testing Play Billing & AdMob — Runbook

Panduan operasional untuk menguji pembayaran Google Play dan iklan AdMob
secara nyata. Kode kedua fitur **sudah terpasang**; yang tersisa adalah
konfigurasi di Play Console / AdMob dan verifikasi server.

---

## 0. Kepatuhan teknis (sudah diverifikasi)

| Syarat Play (per Nov 2026) | Status |
| :--- | :--- |
| `targetSdk` ≥ **36** untuk app baru (sejak 31 Agu 2026) | ✅ `targetSdk 36`, `compileSdk 36` |
| 16 KB page size (wajib sejak 1 Nov 2025 untuk targetSdk ≥ 35) | ✅ `libflutter.so` & `libapp.so` align `0x10000`, lib lain `0x4000` |
| Play Billing Library ≥ 8 | ✅ `billing:8.3.0` |
| Package name | `com.qrcheck.app.qr_check` |
| Signing | upload keystore `CN=Qristal` |

> Toolchain: AGP 8.9.1 · Gradle 8.11.1 · Kotlin 2.0.21 · NDK 27.0.12077973.

---

## A. Prasyarat Play Console (UI, sekali saja)

1. **Payments profile** — Setup → Payments profile. Tanpa ini menu
   *Monetize → Products* tidak bisa dipakai.
2. **App sudah dibuat** (Create app → App details).
3. **Upload AAB ke Internal testing**
   - Testing → Internal testing → Create new release
   - Upload `build/app/outputs/bundle/release/app-release.aab`
   - Isi release notes, lalu **Save → Review → Start rollout**
4. **Tambahkan license tester**
   - Setup → License testing → tambahkan email Google akun uji
     (`gekaogenk@gmail.com`) dan pilih *Responses: RESERVED (purchase successful)*
5. **Buat produk in-app**
   - Monetize → Products → **In-app products** → Create product
   - Product ID: **`pro_lifetime`** (harus persis, sama dengan `kProLifetimeProductId`)
   - Name: `Qristal PRO Lifetime`
   - Harga: **Rp 5.000**
   - Status: **Active**
6. **Salin link opt-in** dari Internal testing, buka di HP, install dari Play
   Store (bukan sideload APK — Play Billing menolak build sideload).

---

## B. Verifikasi server (Play Developer API)

`verify-play-purchase` memverifikasi purchase token ke Google. Tanpa service
account, setiap pembelian akan gagal dengan `missing_GOOGLE_SERVICE_ACCOUNT_JSON`.

1. Google Cloud Console → buat **Service Account** (project yang sama dengan
   yang menautkan Play, atau project baru + aktifkan **Google Play Android
   Developer API**).
2. Buat **key JSON** → simpan ke `qr-check/secrets/google-service-account.json`
   (sudah gitignored). Jangan taruh di repo.
3. Play Console → **Users and permissions** → Invite users → masukkan email
   service account → beri permission:
   - *View financial data, orders, and cancellation survey responses*
   - *Manage orders and subscriptions* (untuk acknowledge/refund)
4. Set secret di Supabase:
   ```bash
   npx supabase secrets set --env-file .env.play \
     --project-ref oljiqzttttxjrbwtfzze
   # isi .env.play:
   # GOOGLE_SERVICE_ACCOUNT_JSON=<isi JSON satu baris>
   ```
   atau via dashboard: Project Settings → Edge Functions → Secrets.
5. Deploy ulang:
   ```bash
   bash scripts/deploy-play-billing.sh
   ```

---

## C. Uji pembelian (end-to-end)

| Langkah | Yang diharapkan |
| :--- | :--- |
| Buka app hasil install dari Play (akun license tester) | Modal PRO menampilkan harga dari Play (`Rp 5.000`) |
| Tap **Beli PRO** | Bottom sheet Play muncul, tandai "Test card" |
| Selesaikan pembelian | Muncul pesan sukses, `is_pro` jadi true |
| Cek database | `select * from play_purchases;` → 1 baris `state=purchased` |
| Cek profil | `select is_pro, pro_source from profiles where id='<uid>';` |
| Restore | Uninstall → install ulang → tombol *Pulihkan Pembelian* mengaktifkan PRO |

Catatan: license tester **tidak dikenai biaya**. Untuk uji refund, refund
manual dari Play Console → Order management, lalu cek RTDN (butuh
`RTDN_AUDIENCE` + Pub/Sub, lihat `docs/GO-LIVE.md`).

---

## D. AdMob produksi

1. <https://admob.google.com> → **Apps → Add app → Android** →
   `com.qrcheck.app.qr_check`.
2. Buat 3 ad unit: rewarded (`qristal_rewarded_quota`), interstitial
   (`qristal_interstitial_delete`), banner (`qristal_banner_home`).
3. Build produksi:
   ```bash
   flutter build appbundle --release \
     --dart-define=ADMOB_TEST_MODE=false \
     --dart-define=ADMOB_REWARDED_ID=ca-app-pub-XXX/111 \
     --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-XXX/222 \
     --dart-define=ADMOB_BANNER_ID=ca-app-pub-XXX/333 \
     -PadmobAppId=ca-app-pub-XXX~444
   ```
4. Uji di **HP fisik** (emulator tanpa Play Services tidak menayangkan iklan).
   - Banner muncul di atas bottom bar (kecuali akun PRO)
   - "+1 Kuota" → rewarded selesai → kuota bertambah
   - Hapus 3× berturut-turut → interstitial muncul (jeda ≥ 2 menit)
5. Verifikasi di AdMob → *Ad units* setelah 1–3 hari ada impressions.

> **Jangan pernah klik iklan sendiri pada unit produksi** — risiko suspend.
> Selalu uji dengan `ADMOB_TEST_MODE=true` (default).

---

## E. Checklist sebelum rilis

- [ ] `versionCode` dinaikkan setiap upload
- [ ] AAB ditandatangani upload keystore (`CN=Qristal`)
- [ ] Produk `pro_lifetime` **Active** dan harganya benar
- [ ] `GOOGLE_SERVICE_ACCOUNT_JSON` terpasang di Supabase
- [ ] Data safety & privacy policy terisi (ada AdMob + login)
- [ ] Deklarasi "App contains ads" = Yes
- [ ] Uji di HP fisik: billing, restore, banner, rewarded, interstitial
- [ ] Uji edge-to-edge Android 16 (status bar tidak menimpa konten)
