# qr_check

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Docker Deployment (Web)

Project ini telah dikonfigurasi dengan multi-stage Docker build untuk menjalankan versi Flutter Web menggunakan Nginx.

### Jalankan dengan Docker Compose:
```bash
docker compose up -d --build
```
Aplikasi akan dapat diakses di `http://localhost:8080`.

### Jalankan manual dengan Docker CLI:
```bash
# Build Docker image
docker build -t qr-check-web .

# Jalankan Container
docker run -d -p 8080:80 --name qr-check-app qr-check-web
```
