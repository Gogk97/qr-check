# GO-LIVE: Google Play Billing `pro_lifetime` — Runbook

Panduan eksekusi manual, urut. Kerjakan dari atas ke bawah; setiap fase punya
titik verifikasi supaya kalau gagal, Anda tahu persis di mana.

**Sudah selesai di repo (jangan diulang):**
- Native bridge Billing 8.3.0 + Dart service + bottom sheet PRO + restore
- Edge functions `verify-play-purchase` & `play-rtdn` (+ 29 unit test, type-check bersih)
- Migrasi `20261117090000_play_billing.sql` & `20261117120000_play_rtdn.sql`
- Upload keystore + signing config + AAB release: `build/app/outputs/bundle/release/app-release.aab`

**Yang belum (butuh akun/kredensial Anda):** Fase 1–6 di bawah.

---

## Fase 0 — Sebelum mulai (5 menit)

- [ ] **Backup kredensial keystore.** Buka `android/KEYSTORE_BACKUP.txt`, simpan
      password + SHA-256 ke password manager, lalu hapus file itu.
      Tanpa ini Anda tidak bisa merilis update.
- [ ] Pastikan **akun Play Developer sudah aktif** (biaya sekali $25 + verifikasi
      identitas). Kalau belum, selesaikan dulu di
      https://play.google.com/console/signup
- [ ] Siapkan **Privacy Policy URL** (wajib untuk app dengan login).
      Bisa pakai GitHub Pages / Notion publik. Contoh isi minimal: data apa yang
      dikumpulkan (email, foto galeri diproses lokal), tidak dijual ke pihak ketiga.

---

## Fase 1 — Buat app + upload build (Play Console)

1. https://play.google.com/console → **Create app**
   - App name: `Qristal` (maks 30 karakter)
   - Default language: `Indonesian (id-ID)`
   - App or game: **App** · Free or paid: **Free**
   - Centang 2 deklarasi (Play policies + US export laws) → **Create app**
2. **Dashboard → "Set up your app"** — isi yang wajib untuk internal testing:
   - **App access**: pilih "All or some functionality is restricted" → isi cara
     reviewer login (akun demo/guest). App Anda punya login Google + guest.
   - **Ads**: "No, my app does not contain ads"
   - **Content rating**: isi kuesioner (kategori: Utility) → dapat rating
   - **Target audience**: 18+ (atau sesuai), tidak untuk anak
   - **Data safety**: deklarasikan email + foto (diproses lokal, tidak diunggah)
   - **Privacy policy**: tempel URL
3. **Testing → Internal testing → Create new release**
   - Upload `build/app/outputs/bundle/release/app-release.aab`
   - Release notes: `Versi pertama dengan pembelian PRO via Google Play`
   - **Next → Save → Review release → Start rollout to Internal testing**
4. **Testers** tab → **Create email list** → masukkan `gekaogenk@gmail.com`
   (dan email penguji lain) → Save → centang list → **Save changes**
5. Salin **opt-in URL** (tombol "Copy link"). Ini link instalasi untuk testing.

**Verifikasi:** build muncul di Internal testing dengan status "Available to internal testers".

> Catatan: menu produk billing (Fase 2) baru muncul setelah ada build dengan
> permission BILLING ter-upload — jadi Fase 1 harus selesai dulu.

---

## Fase 2 — Produk & pembayaran

1. **Setup → Payments profile** (kalau belum ada): isi data bisnis/pribadi + pajak.
   Tanpa ini produk berbayar tidak bisa dibuat.
2. **Monetize → Products → One-time products → Create product**
   - Product ID: **`pro_lifetime`** ← permanen, tidak bisa diubah. Harus sama
     persis dengan `kProLifetimeProductId` di app.
   - Name: `Qristal PRO (Lifetime)` · Description: `Akses PRO permanen: hapus massal tanpa batas & bebas iklan.`
   - Price: **Rp 15.000** → **Activate**
3. **Settings → License testing** → tambahkan `gekaogenk@gmail.com`
   → License response: **RESPOND_NORMALLY** → Save.
   (Akun ini bisa beli tanpa ditagih.)

**Verifikasi:** produk berstatus **Active** dan muncul di daftar One-time products.

---

## Fase 3 — Service account (Google Cloud + Play Console)

1. https://console.cloud.google.com → **Create project** → nama `qristal-play`
2. **APIs & Services → Library** → cari **Google Play Android Developer API** → **Enable**
3. **IAM & Admin → Service accounts → Create service account**
   - Name: `play-billing-verifier` → Create and continue → skip role → Done
4. Klik service account itu → tab **Keys** → **Add key → Create new key → JSON**
   → file terunduh. Rename jadi `service-account.json`, simpan ke
   `qr-check/secrets/service-account.json` (`secrets/` sudah gitignored).
5. **Play Console → Setup → API access** → link ke project `qristal-play`
6. **Play Console → Users and permissions → Invite new users**
   - Email: alamat service account (`play-billing-verifier@qristal-play.iam.gserviceaccount.com`)
   - App permissions: pilih app `Qristal`
   - Account permissions: centang **View financial data** + **Manage orders and subscriptions**
   - **Invite user** (service account langsung aktif, tanpa email konfirmasi)

**Verifikasi:** service account muncul di daftar Users and permissions dengan status aktif.

---

## Fase 4 — Backend Supabase

```bash
cd /Users/yudibaidillah/Documents/projects/outside/qr-check

npx supabase login                     # buka browser Anda, tempel kode verifikasi
mkdir -p secrets && cp ~/Downloads/service-account.json secrets/

# satu perintah untuk migrasi + secrets + deploy + health check:
SUPABASE_PROJECT_REF=oljiqzttttxjrbwtfzze ./scripts/deploy-play-billing.sh
```

Script menjalankan: `link` → `db push` (3 migrasi: billing, RTDN, security
hardening) → `secrets set` → deploy `verify-play-purchase` → health check.

**Verifikasi:**
```bash
curl -s https://oljiqzttttxjrbwtfzze.supabase.co/functions/v1/verify-play-purchase
# {"ok":true,"function":"verify-play-purchase","package":"com.qrcheck.app.qr_check"}
```

---

## Fase 5 — RTDN (refund otomatis mencabut PRO)

1. **Cloud Console → Pub/Sub → Topics → Create topic** → ID `play-rtdn`
2. Topic → **Permissions → Add principal**
   - Principal: `google-play-developer-notifications@system.gserviceaccount.com`
   - Role: **Pub/Sub Publisher** → Save
3. **IAM & Admin → Service accounts → Create service account** → `play-rtdn-push`
   (tanpa role) → buat **key JSON**? Tidak perlu — cukup untuk OIDC.
4. **Pub/Sub → Subscriptions → Create subscription**
   - ID `play-rtdn-push` · Topic `play-rtdn` · Delivery type **Push**
   - Endpoint URL: `https://oljiqzttttxjrbwtfzze.supabase.co/functions/v1/play-rtdn`
   - Centang **Enable authentication** → Service account: `play-rtdn-push`
   - **Audience**: `https://oljiqzttttxjrbwtfzze.supabase.co/functions/v1/play-rtdn`
   - Create
5. Set secret + deploy RTDN:
```bash
npx supabase secrets set \
  RTDN_AUDIENCE="https://oljiqzttttxjrbwtfzze.supabase.co/functions/v1/play-rtdn" \
  RTDN_SERVICE_ACCOUNT_EMAIL="play-rtdn-push@qristal-play.iam.gserviceaccount.com"
npx supabase functions deploy play-rtdn     # verify_jwt=false sudah di config.toml
```
6. **Play Console → Monetize → Monetization setup → Real-time developer notifications**
   - Topic name: `projects/qristal-play/topics/play-rtdn`
   - Centang **Get all notifications for subscriptions and one-time products**
   - **Save** → **Send test message**
7. Cek log: `npx supabase functions logs play-rtdn` → harus ada `test_ok`.

---

## Fase 6 — Uji end-to-end

1. Buka **opt-in URL** dari Fase 1 → terima undangan → install dari Play Store.
   (Jangan sideload APK — produk tidak akan muncul.)
2. Login app → tombol **Beli PRO** → Play sheet harus menampilkan **harga asli**
   (bukan tombol "Muat Ulang Harga").
3. Bayar pakai kartu uji → tunggu beberapa detik.
4. Cek database:
```sql
select is_pro, pro_source, pro_activated_at from public.profiles where id = '<uid>';
select purchase_token, product_id, purchase_state, acknowledged, is_test
  from public.play_purchases order by created_at desc limit 5;
select event_type, purchase_token, processed_at
  from public.play_rtdn_events order by processed_at desc limit 5;
```
5. **Uji restore:** uninstall → install ulang → buka sheet PRO → harus otomatis
   memulihkan (sheet tertutup sendiri dengan PRO aktif).
6. **Uji refund:** Play Console → Order management → refund order →
   tunggu RTDN → `is_pro` harus kembali `false`, dan
   `play_purchases.purchase_state = 'CANCELLED'`.

---

## Troubleshooting

| Gejala | Penyebab | Solusi |
| :--- | :--- | :--- |
| Tombol jadi "Muat Ulang Harga", produk null | Build belum di track / produk belum Active / akun bukan license tester | Cek Fase 1 & 2, lalu clear cache Play Store di HP |
| `purchase_not_completed` | Pembayaran pending (mis. bayar di gerai) | Tunggu; RTDN akan meng-acknowledge otomatis |
| `grant_failed` / `missing_GOOGLE_SERVICE_ACCOUNT_JSON` | Secret belum diset | `npx supabase secrets set ...` lalu deploy ulang |
| Play API 401/403 | SA belum di-invite / permission kurang / API belum enable | Ulangi Fase 3 nomor 5–6 |
| RTDN balas 401 `RTDN_AUDIENCE_not_configured` | Secret audience belum ada | Fase 5 nomor 5 |
| RTDN balas 401 `invalid_audience` | Audience subscription ≠ URL function | Samakan persis (termasuk `https://` dan tanpa slash akhir) |
| `purchase_token_already_claimed` | Token sudah dipakai akun lain | Normal — proteksi anti-sharing |
| Upload ditolak "debug certificate" | `android/key.properties` hilang | Buat ulang dari `key.properties.example`, rebuild AAB |
| Upload ditolak "version code already used" | versionCode sama | Naikkan `version: 1.0.0+2` di `pubspec.yaml`, rebuild |

---

## Perintah harian setelah go-live

```bash
# build rilis baru
flutter build appbundle --release

# deploy backend setelah ubah function
./scripts/deploy-play-billing.sh

# log RTDN real-time
npx supabase functions logs play-rtdn

# test lokal (tanpa kredensial)
npx deno test --allow-net --allow-env supabase/functions/tests/
```
