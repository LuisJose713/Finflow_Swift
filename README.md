# FinFlow iOS — SwiftUI

Aplicación financiera **nativa para iPhone e iPad**, desarrollada en SwiftUI. Comparte el backend `WS_FINFLOW` (Java/Spring Boot, Railway, PostgreSQL) con FinFlow Web.

## Requisitos

- Xcode compatible con el proyecto, iOS/iPadOS 17 o posterior y Swift 6.
- Para probar en simulador no se necesitan certificados de Apple Developer.
- Para distribuir mediante TestFlight/App Store se requieren firma, provisioning, Team ID y credenciales de App Store Connect.

## Funciones

| Área | Estado |
|---|---|
| Login/registro; Keychain; recuperar sesión con `/auth/me` | Implementado |
| Face ID / Touch ID / código del dispositivo al entrar y al regresar de segundo plano | Implementado; activado por defecto si el dispositivo tiene autenticación disponible |
| Dashboard con gráfico lineal interactivo o circular con importes, categorías y meses | Implementado |
| Movimientos (crear/editar/eliminar), filtros, PDF, Excel y CSV | Implementado |
| Metas, aportaciones, historial, estados y validación del saldo pendiente | Implementado |
| Gastos planificados | Implementado |
| Categorías propias y categorías globales de solo lectura | Implementado |
| Presupuestos mensuales, límites, alertas a partir del 80% | Implementado |
| Administración mediante rol ADMIN | Implementado |
| Chat del asesor IA | Implementado; depende del servicio externo |
| Cuentas/billeteras COP y transferencias entre cuentas propias | Implementado |
| Movimientos recurrentes mensuales, pausa y ejecución | Implementado; backend idempotente |
| Cambiar contraseña, cerrar todas las sesiones y eliminar cuenta con contraseña | Implementado |
| Recordatorios locales a las 10:00 y 16:00; abrir destino al tocar el aviso | Implementado; requiere permiso de notificaciones |
| Push remoto APNs y TestFlight/App Store | Pendiente: requiere configuración de distribución |

## Privacidad y seguridad

- API fija en `https://finflow-backend-production.up.railway.app`.
- Todas las operaciones se autorizan con `Authorization: Bearer`; **nunca** se usa `X-User-Id` como fuente de identidad.
- El servidor valida el JWT y confirma el rol con `GET /auth/me`. Ante una interrupción de red se conserva el acceso local protegido a la caché; no se recuperan privilegios ADMIN sin confirmación del servidor.
- Face ID no sustituye la contraseña de la cuenta ni se envía al servidor. La cancelación mantiene el bloqueo; iOS ofrece su código como respaldo. Desactivar la protección también exige autenticación local.
- Token y clave AES-GCM en Keychain (solo dispositivo y con pantalla desbloqueada). La caché financiera se cifra con AES-GCM y solo se puede consultar si no hay conexión. Las credenciales de Apple y de Neon/Render no van al repositorio.
- La app nativa utiliza la API compartida, no abre conexiones directas a Neon.

## GitHub Actions: compilación real sin Mac propio

`.github/workflows/ios-ci.yml` usa Xcode sobre `macos-26`: valida proyecto, icono, importes y contratos; compila el simulador; ejecuta pruebas unitarias y de UI en iPhone e iPad; y compila Release para dispositivo sin firma. Publica resultados `.xcresult`, capturas y logs. Se ejecuta en push a `main` y en PR.

Las pruebas de UI utilizan datos ficticios interceptados por `URLProtocol`; no modifican producción. El transporte de pruebas está excluido de Release y solo se activa con `FINFLOW_UI_TESTING=1` en Debug.

Ve a [GitHub Actions](https://github.com/LuisJose713/Finflow_Swift/actions), abre **FinFlow iOS CI**, consulta los resultados o descarga la captura desde *Artifacts*.

El archivo generado con una compilación **para simulador** no es un IPA distribuible. Se necesitan credenciales y firma de distribución para TestFlight.

## Abrir localmente

1. Abre `FinFlow.xcodeproj` en un Mac con Xcode.
2. Selecciona el esquema `FinFlow` y un iPhone Simulator.
3. Ejecuta con **Run**.

Para instalar en tu iPhone desde una Mac prestada: [guía paso a paso](docs/PROBAR_EN_MAC.md).

## Sincronización y limitaciones

La caché offline de movimientos es específica de cada usuario y está cifrada. Las escrituras financieras se confirman por el servidor; no se reenvían automáticamente operaciones tras un timeout ambiguo. Las colas de versiones anteriores se conservan cifradas durante la sesión para revisión manual. Cerrar la sesión elimina la caché y los pendientes de ese usuario en el dispositivo.

Consulta [la matriz de funciones y verificación](docs/IOS_QA_2026-11-12.md) y el [contrato de API](BACKEND_CONTRACT.md). Compilar y probar con datos aislados no certifica el funcionamiento autenticado del backend ni el sensor físico Face ID.
