# FinFlow iOS — SwiftUI

Aplicación financiera **nativa para iPhone e iPad**, desarrollada en SwiftUI. Comparte el backend `WS_FINFLOW` (Java/Spring Boot, Render, Neon) con FinFlow Web. **No es un WebView ni una copia de Angular.**

## Requisitos

- Xcode compatible con el proyecto, iOS/iPadOS 17 o posterior y Swift 6.
- Para probar en simulador no se necesitan certificados de Apple Developer.
- Para distribuir mediante TestFlight/App Store se requieren firma, provisioning, Team ID y credenciales de App Store Connect.

## Funciones

| Área | Estado |
|---|---|
| Login/registro; Keychain; recuperar sesión con `/auth/me` | Implementado |
| Dashboard, gráficos, movimientos, PDF y CSV | Implementado |
| Metas, aportaciones y validación del saldo pendiente | Implementado |
| Gastos planificados | Implementado |
| Categorías propias y categorías globales de solo lectura | Implementado |
| Presupuestos mensuales, límites, alertas a partir del 80% | Implementado |
| Administración mediante rol ADMIN | Implementado |
| Chat del asesor IA | Implementado; depende del servicio externo |
| Cuentas/billeteras | Pendiente: requiere contrato de API |
| Push y TestFlight/App Store | Pendiente: requiere configuración de distribución |

## Privacidad y seguridad

- API fija en `https://finflow-backend-yqhi.onrender.com`; no se permite cambiarla a hosts arbitrarios desde Ajustes.
- Todas las operaciones se autorizan con `Authorization: Bearer`; **nunca** se usa `X-User-Id` como fuente de identidad.
- El servidor valida el JWT y confirma el rol con `GET /auth/me`; la app no se autentica por los datos guardados localmente.
- Token en Keychain. Las credenciales de Apple y de Neon/Render no van al repositorio.
- La app nativa utiliza la API compartida, no abre conexiones directas a Neon.

## GitHub Actions: compilación real sin Mac propio

`.github/workflows/ios-ci.yml` compila con Xcode sobre `macos-15`, instala la aplicación en un simulador iPhone, ejecuta el launch smoke test y sube una captura de pantalla (si la prueba termina bien). Se ejecuta en push a main y en PR.

Ve a [GitHub Actions](https://github.com/LuisJose713/Finflow_Swift/actions), abre **FinFlow iOS CI**, consulta los resultados o descarga la captura desde *Artifacts*.

El archivo generado con una compilación **para simulador** no es un IPA distribuible. Se necesitan credenciales y firma de distribución para TestFlight.

## Abrir localmente

1. Abre `FinFlow.xcodeproj` en un Mac con Xcode.
2. Selecciona el esquema `FinFlow` y un iPhone Simulator.
3. Ejecuta con **Run**.

## Sincronización y limitaciones

La caché offline actual es específica de cada usuario y tiene una cola de reintentos para movimientos. **Los reintentos de creación aún no tienen garantía de idempotencia del servidor**; ese punto debe resolverse antes de prometer sincronización financiera offline libre de duplicados.

Consulta [la matriz de paridad web-iOS](docs/WEB_IOS_PARITY_2026-11-07.md) y el [contrato de API](BACKEND_CONTRACT.md) para estado y pendientes. La validación manual con cuentas de prueba sigue siendo necesaria, y el backend debe tener los endpoints nuevos desplegados.
