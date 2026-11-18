# Google Play Billing — PRO Lifetime (Qristal)

Panduan setup & operasional pembelian **PRO sekali bayar (lifetime)** lewat Google Play.
Implementasi di repo ini sudah siap; yang tersisa adalah konfigurasi di Play Console + Supabase.

---

## 1. Model monetisasi

| Item | Nilai |
| :--- | :--- |
| Jenis produk | **One-time product (managed product) / non-consumable** |
| Product ID | `pro_lifetime` (konstanta `kProLifetimeProductId` di `lib/services/play_billing_service.dart`) |
| Efek | `profiles.is_pro = true`, `profiles.pro_source = 'play'` (permanen) |
| Distribusi | Android/Play → Google Play Billing. iOS/Web/Desktop → QRIS manual (tetap ada) |

> Catatan kebijakan: Google Play **mewajibkan** Play Billing untuk penjualan digital
> (fitur PRO, bebas iklan). Karena itu di Android seluruh tombol "Beli PRO" sekarang
> diarahkan ke Play Billing — bukan QRIS. QRIS tetap dipakai untuk distribusi non-Play
> (APK langsung, web, iOS).

---

## 2. Alur teknis (server-authoritative)

```
Flutter (Android)
  └─ PlayBillingService.purchase()            lib/services/play_billing_service.dart
       └─ MethodChannel "com.qrcheck.app/billing"
            └─ PlayBillingBridge.kt           (Billing 8.3.0, launchBillingFlow)
                 └─ purchaseToken
                      └─ Supabase Edge Function verify-play-purchase
                           ├─ Play Developer API productsv2 (cek state + productId)
                           ├─ purchases.products.acknowledge (wajib ≤ 3 hari)
                           └─ RPC grant_pro_from_play()  → is_pro = true

Google Play ──RTDN──> Pub/Sub (push, OIDC) ──> Edge Function play-rtdn
                           ├─ PURCHASED  → verify + acknowledge + grant/inbox
                           ├─ CANCELED   → revoke_pro_from_play()
                           └─ VOIDED     → revoke_pro_from_play()
```

Client **tidak pernah** menulis `is_pro`. Token yang sudah diklaim akun lain ditolak
(`purchase_token_already_claimed`) sebagai proteksi replay/sharing akun.

File terkait:

| File | Fungsi |
| :--- | :--- |
| `android/app/src/main/kotlin/.../PlayBillingBridge.kt` | Native bridge (Billing 8.3.0) |
| `lib/services/play_billing_service.dart` | Wrapper Dart + verifikasi server + retry token |
| `lib/services/monetization_service.dart` | `openProPurchase()`, bottom sheet PRO, restore |
| `supabase/migrations/20261117090000_play_billing.sql` | Tabel + RPC grant/revoke |
| `supabase/functions/verify-play-purchase/index.ts` | Verifikasi + acknowledge + grant |
| `supabase/functions/play-rtdn/index.ts` | Penerima RTDN (Pub/Sub push, OIDC) |
| `supabase/functions/_shared/play.ts` | Helper service account + Play Developer API |
| `supabase/functions/_shared/oidc.ts` | Verifikasi token OIDC Pub/Sub (JWKS Google) |
| `supabase/functions/_shared/rtdn.ts` | Parsing & klasifikasi notifikasi RTDN |
| `supabase/functions/tests/` | Test Deno (OIDC + klasifikasi RTDN) |

---

## 3. Setup Play Console

1. **Buat aplikasi** di Play Console (jika belum), package `com.qrcheck.app.qr_check`.
2. **Upload build yang sudah berisi Billing Library** ke *Internal testing* (build dari repo ini).
   Fitur billing (menu produk) baru aktif setelah ada build dengan library billing ter-upload.
3. **Monetize → Products → One-time products → Create product**
   - Product ID: `pro_lifetime`
   - Name/Description: "Qristal PRO (Lifetime)"
   - Price: Rp 15.000 (atau sesuai keputusan bisnis)
   - Status: **Active**
4. **License testing**: Settings → License testing → tambahkan email Google penguji.
   Pembelian mereka memakai kartu uji (tidak ditagih).
5. **API access** (Settings → API access):
   - Buat **service account** di Google Cloud, aktifkan **Google Play Android Developer API**.
   - Di Play Console: *Invite new users* → masukkan email service account → permission
     **View financial data** + **Manage orders and subscriptions** (minimal untuk verifikasi & acknowledge).
   - Buat **JSON key** untuk service account tersebut → isi dipakai sebagai secret di langkah 4.
6. **Real-time developer notifications**: ikuti **bagian 7 (RTDN)** di bawah —
   tanpa RTDN, refund/chargeback tidak otomatis mencabut PRO dan pembelian bisa
   di-refund Google jika user tidak membuka app dalam 3 hari.

---

## 4. Setup Supabase

Cara tercepat — satu perintah (butuh `npx supabase login` + file service account):

```bash
mkdir -p secrets && cp /path/service-account.json secrets/google-service-account.json
./scripts/deploy-play-billing.sh
```

Script itu menjalankan: link project → `db push` (migrasi) → set secrets → deploy
`verify-play-purchase` (+ `play-rtdn` bila env RTDN diisi) → health check.
Langkah manualnya:

Jalankan migrasi:

```bash
# via SQL editor Supabase (copy isi file) atau:
npx supabase db push
```

Deploy edge function + secrets:

```bash
npx supabase functions deploy verify-play-purchase --project-ref oljiqzttttxjrbwtfzze

npx supabase secrets set \
  GOOGLE_SERVICE_ACCOUNT_JSON="$(cat service-account.json)" \
  PLAY_PACKAGE_NAME="com.qrcheck.app.qr_check" \
  PLAY_PRODUCT_ID="pro_lifetime"
```

`GOOGLE_SERVICE_ACCOUNT_JSON` juga menerima nilai **base64** dari file JSON
(aman jika secret multi-baris ditolak).

Uji cepat:

```bash
curl -s "https://oljiqzttttxjrbwtfzze.supabase.co/functions/v1/verify-play-purchase"
# {"ok":true,"function":"verify-play-purchase","package":"com.qrcheck.app.qr_check"}
```

---

## 5. Testing end-to-end

1. Pastikan build di *Internal testing* dan akun penguji ada di **License testing**.
2. Install dari link internal testing (bukan sideload APK — signature harus sama).
3. Buka app → login → tombol "Beli PRO" → Play sheet muncul dengan harga asli.
4. Selesaikan pembelian (kartu uji) → app memanggil edge function →
   cek `profiles.is_pro = true` dan baris baru di `play_purchases`.
5. **Restore**: uninstall → install ulang → buka sheet PRO → otomatis memulihkan PRO.
6. **Pending**: aktifkan *pending purchases* di Play Console (test instrument) untuk
   memastikan UI menampilkan status "menunggu pembayaran".
7. **Refund**: refund lewat Play Console → panggil `revoke_pro_from_play` (atau RTDN handler)
   → `is_pro` kembali false.

---

## 6. Operasional & mitigasi

| Risiko | Penanganan |
| :--- | :--- |
| Pembelian tidak di-acknowledge ≤ 3 hari → auto refund | Edge function acknowledge otomatis setelah verifikasi |
| Verifikasi gagal (offline / function down) | Token disimpan di `SharedPreferences`, di-retry saat sheet PRO dibuka & tiap restore |
| User ganti device / reinstall | `restorePurchases` → `queryPurchasesAsync` → verifikasi ulang ke server |
| Token dipakai akun lain | `grant_pro_from_play` menolak token yang sudah diklaim |
| Refund / chargeback | `revoke_pro_from_play` mencabut PRO bila tidak ada pembelian aktif lain |
| Play service fee | 15% untuk USD 1 juta pertama/tahun (program reduced service fee), 30% setelahnya |

---

## 7. RTDN — otomatis acknowledge & cabut PRO saat refund

Edge Function `play-rtdn` menerima push Pub/Sub, **memverifikasi OIDC token** dari
Google, lalu memproses notifikasi:

| Event | Aksi |
| :--- | :--- |
| `ONE_TIME_PRODUCT_PURCHASED` (type 1) | Verifikasi ke Play API → **acknowledge** → grant PRO bila `obfuscatedAccountId` cocok dengan user; kalau belum bisa dipetakan, simpan di `play_purchase_inbox` |
| `ONE_TIME_PRODUCT_CANCELED` (type 2) | `revoke_pro_from_play()` |
| `VOIDED_PURCHASE` (refund/chargeback) | `revoke_pro_from_play()` |
| `TEST` | Dibalas `test_ok` (untuk verifikasi setup) |
| `PENDING_REFUND_REVIEW` | Dicatat di log (keputusan manual via `orders.reviewrefund`) |

Pengaman yang sudah terpasang: dedupe `message_id` (Pub/Sub bisa kirim ulang),
validasi `packageName`, fail-closed bila `RTDN_AUDIENCE` belum diset, dan
signature JWT diverifikasi ke JWKS Google (bukan hanya decode payload).

### Langkah setup

```bash
REF=<PROJECT_REF_SUPABASE>
GCP=<PROJECT_ID_GOOGLE_CLOUD>

# 1) Topic
gcloud pubsub topics create play-rtdn

# 2) Izinkan Google Play publish ke topic
gcloud pubsub topics add-iam-policy-binding play-rtdn \
  --member="serviceAccount:google-play-developer-notifications@system.gserviceaccount.com" \
  --role="roles/pubsub.publisher"

# 3) Service account untuk OIDC push
gcloud iam service-accounts create play-rtdn-push --display-name="Play RTDN push"

# 4) Push subscription (audience = URL function)
gcloud pubsub subscriptions create play-rtdn-push \
  --topic=play-rtdn \
  --push-endpoint="https://$REF.supabase.co/functions/v1/play-rtdn" \
  --push-auth-service-account="play-rtdn-push@$GCP.iam.gserviceaccount.com" \
  --push-auth-token-audience="https://$REF.supabase.co/functions/v1/play-rtdn"

# 5) Secrets function
npx supabase secrets set \
  RTDN_AUDIENCE="https://$REF.supabase.co/functions/v1/play-rtdn" \
  RTDN_SERVICE_ACCOUNT_EMAIL="play-rtdn-push@$GCP.iam.gserviceaccount.com"

# 6) Deploy — WAJIB --no-verify-jwt (Google yang menandatangani, bukan Supabase)
npx supabase functions deploy play-rtdn --no-verify-jwt
```

7. Play Console → **Monetize → Monetization setup → Real-time developer notifications**:
   isi `projects/$GCP/topics/play-rtdn`, centang
   **"Get all notifications for subscriptions and one-time products"**, Save,
   lalu **Send test message**.

### Verifikasi

```bash
# health check
curl -s "https://$REF.supabase.co/functions/v1/play-rtdn"
# {"ok":true,"function":"play-rtdn","package":"com.qrcheck.app.qr_check"}

# log function (harus muncul test_ok setelah Send test message)
npx supabase functions logs play-rtdn
```

Pembelian yang sudah dibayar tapi belum masuk akun mana pun bisa dipantau:

```sql
select * from public.play_unclaimed_purchases order by created_at desc;
```

### Test lokal (tanpa kredensial)

```bash
npx deno test --allow-net --allow-env supabase/functions/tests/
npx deno check --allow-import supabase/functions/play-rtdn/index.ts \
  supabase/functions/verify-play-purchase/index.ts
```

---

## 8. Rilis ke Play (signing & upload)

Play **menolak** build yang ditandatangani debug key, jadi buat upload keystore dulu:

```bash
cd android
keytool -genkeypair -v -keystore upload-keystore.p12 -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp key.properties.example key.properties   # lalu isi password & alias
```

`key.properties` + `upload-keystore.p12` sudah masuk `.gitignore` — **jangan pernah di-commit**.
Simpan password di password manager; kalau hilang, harus reset upload key lewat Play Console.

Build & upload:

```bash
flutter build appbundle --release      # → build/app/outputs/bundle/release/app-release.aab
```

Naikkan `version: x.y.z+N` di `pubspec.yaml` setiap kali upload build baru
(`N` = versionCode, harus selalu lebih besar).

---

## 9. Batasan teknis yang perlu diketahui

- **minSdk dinaikkan 21 → 23** (syarat `com.android.billingclient:billing:8.3.0`).
  Dampak: Android 6.0 (API 23) ke atas. Distribusi per 2026 praktis tidak terpengaruh.
- **Google Play Billing 7 ke bawah sudah ditolak untuk update** (deadline 31 Agu 2026,
  extension 1 Nov 2026). Karena itu proyek ini memakai **8.3.0**, bukan plugin
  `in_app_purchase` terbaru (butuh Flutter 3.38+, sedangkan proyek masih Flutter 3.24).
- Jika nanti Flutter di-upgrade ≥ 3.44, bridge native ini bisa diganti `in_app_purchase`
  tanpa mengubah alur server (kontrak: kirim `purchaseToken` → edge function).
