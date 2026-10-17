# FinFlow iOS — SwiftUI

Frontend nativo de FinFlow migrado desde Flutter a SwiftUI y conectado al backend Spring Boot `WS_FINFLOW`.

## Requisitos

- Xcode compatible con iOS 17 o posterior.
- Swift 6 language mode (el toolchain exacto lo determina la versión de Xcode instalada).
- Una cuenta Apple Developer solo es necesaria para ciertos flujos de firma/distribución; para ejecutar en simulador basta configurar Xcode.

## Abrir

1. Descomprime el ZIP en macOS.
2. Abre `FinFlow.xcodeproj` en Xcode.
3. Selecciona el esquema `FinFlow` y un simulador de iPhone o un dispositivo.
4. Configura `Signing & Capabilities` con tu equipo.
5. Ejecuta con **Run**.

La URL inicial de API es `https://finflow-backend-yqhi.onrender.com`; se puede cambiar desde Ajustes.

## Funcionalidades

- Registro e inicio de sesión con JWT y `X-Client-Type: mobile`.
- Token almacenado en Keychain.
- Dashboard con balance, ingresos, gastos, tasa de ahorro, movimientos y evolución mensual.
- Movimientos: crear, eliminar, buscar, filtrar por tipo/mes/año/categoría y exportar PDF/CSV.
- Caché local y cola de reintentos para crear/eliminar movimientos sin conexión.
- Metas financieras: listar, crear, editar, eliminar y aportar fondos.
- Gastos planificados conectados al backend: listar, crear, editar, ejecutar, cancelar y eliminar; los recordatorios/fechas y la categoría se envían al servidor.
- Asesor IA mediante `/ai/chat`.
- Ajustes de conexión y apariencia.

## Estado de validación

Se realizó parseo sintáctico de los archivos Swift y pruebas de decodificación JSON con muestras que reflejan las entidades del backend. **Este entorno no dispone de Xcode ni del SDK de iOS**, por lo que todavía se debe abrir y compilar el proyecto en Xcode y ejecutar pruebas integradas contra Render. No se declara compilación de iOS ni prueba de extremo a extremo completada.

## Limitaciones del backend actual

- La entidad `Transaction` y `TransactionRequest` no tienen campo `notes`; la app no presenta notas en el formulario de movimientos porque el backend no las persiste.
- `Goal` no contiene campo `icon`; el icono de meta se presenta con un valor visual predeterminado y no se sincroniza.
- `TransactionStats.categoryData` actualmente se devuelve vacío desde el servicio Java; el frontend no inventa esos datos.
- La sincronización offline implementada cubre operaciones de crear y eliminar movimientos; no se afirma que todas las funciones estén disponibles sin conexión.
