# GSP766 - GKE Multi-tenant Cluster with Namespaces

Script bash otomatis untuk lab **GSP766: Managing a GKE Multi-tenant Cluster with Namespaces** di Google Cloud Skills Boost.

Credit: **Jutapen**

## Cara pakai

1. Mulai lab, lalu buka **Cloud Shell** dengan akun student lab.
2. Tunggu pesan "Provisioning Lab Resources" hilang.
3. Jalankan:

```bash
curl -sL https://raw.githubusercontent.com/<USERNAME>/gsp766-gke-multitenant/main/gsp766.sh -o gsp766.sh && bash gsp766.sh
```

4. Script berhenti di Task 2, 3, 4, dan 5. Di setiap jeda, klik **Check my progress** di halaman lab, lalu tekan ENTER.

## Langkah manual (Task 5)

Data source Looker Studio tidak bisa dibuat lewat bash:

1. Buka https://lookerstudio.google.com/datasources dengan akun student lab.
2. **Create > Data Source > BigQuery > Authorize**.
3. Ubah nama menjadi `GKE Usage`.
4. Pilih **CUSTOM QUERY**, pilih project lab, lalu paste query yang ditampilkan di akhir script.
5. Klik **CONNECT**, lalu **Check my progress**.

## Yang normal terjadi

- `Forbidden` saat `team-a-dev` mengakses namespace `team-b`: memang diharapkan.
- `exceeded quota` pada `app-server-3`: memang diharapkan.
- Script aman dijalankan ulang; resource yang sudah ada dilewati.
- `kubectl edit` pada lab diganti `kubectl patch` dengan hasil yang sama.
- Muncul link otorisasi saat `bq query --schedule`: klik, login, lalu paste `version_info`.

## Disclaimer

Script ini hanya membantu mengikuti instruksi lab dan tidak membuat resource di luar lab. Pahami tiap langkahnya, jangan hanya menjalankan tanpa membaca. Tidak berafiliasi dengan Google. Gunakan hanya di akun student lab, bukan akun pribadi.
