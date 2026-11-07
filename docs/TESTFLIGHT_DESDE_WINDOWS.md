# FinFlow — Compilar y subir a TestFlight sin tener Mac

Esta guía se usa con **GitHub Actions + Xcode en macOS alojado por GitHub**. El proyecto es SwiftUI, la app no contiene secretos de Apple ni conecta directamente a Neon.

## Estado verificado

- El workflow `.github/workflows/ios-ci.yml` ya compiló y abrió la app en un iPhone Simulator.
- El nuevo workflow `.github/workflows/ios-testflight.yml` permite validar un archivo iOS **sin firma** en un PR o ejecutar manualmente un archivo firmado y subirlo a TestFlight.
- **No es posible instalar un archivo sin firma en un iPhone ni enviarlo a App Store Connect.**
- La opción `testflight` no se ejecuta automáticamente: debes seleccionarla expresamente, y falla sin sus secretos.

## 1. Preparar la app en Apple

1. En https://developer.apple.com/account/ crea/confirma el **App ID** para FinFlow y conserva su identificador real (ej. `com.finflow.ios` si está disponible).
2. En https://appstoreconnect.apple.com/ crea la ficha de FinFlow con ese Bundle ID, plataforma iOS, nombre y SKU. No intentes enviar una IPA si la ficha/App ID no existen.
3. Localiza el **Team ID** del equipo Apple. Es distinto del Apple ID personal.
4. Para liberar una app en iPhone necesitas un certificado **Apple Distribution** y un perfil de aprovisionamiento para **App Store Connect / App Store** asociado al App ID.

## 2. Crear certificado de distribución sin Mac (Windows + OpenSSL)

Usa OpenSSL local en Windows (Git Bash que incluya OpenSSL o WSL). En una carpeta **privada y fuera de Git**:

```bash
openssl genrsa -out finflow-distribution.key 2048
openssl req -new -key finflow-distribution.key -out finflow-distribution.csr -subj "/CN=FinFlow Distribution/C=CO"
```

En el portal Apple Developer, registra el certificado Apple Distribution proporcionando solo el `CSR`, descarga el certificado firmado `.cer`. Luego:

```bash
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey finflow-distribution.key -in distribution.pem -out distribution.p12
```

Apple te pedirá utilizar ese certificado en un perfil de distribución válido para el App ID. Descarga el archivo `.mobileprovision`.

**Guarda la contraseña del `.p12` y la llave privada en un administrador de contraseñas. Nunca publiques ni compartas estos archivos en un chat, repositorio, issue o PR.**

## 3. Crear clave de App Store Connect

En App Store Connect → Usuarios y acceso → Integraciones → API de App Store Connect, genera una **Team API Key** con permisos suficientes para subir builds. Guarda el archivo **AuthKey_*.p8**, el **Key ID** y el **Issuer ID**. El archivo `.p8` suele descargarse una sola vez; protégelo.

## 4. Configurar GitHub Actions Secrets

En https://github.com/LuisJose713/Finflow_Swift/settings/secrets/actions → **New repository secret**, configura estos valores:

| Secret | Valor |
|---|---|
| `APPLE_TEAM_ID` | Team ID oficial |
| `APPLE_BUNDLE_ID` | Bundle ID registrado, idéntico al perfil |
| `IOS_DISTRIBUTION_CERT_BASE64` | Contenido del `distribution.p12` codificado en base64 |
| `IOS_DISTRIBUTION_CERT_PASSWORD` | Contraseña del `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | Contenido del `.mobileprovision` codificado en base64 |
| `APP_STORE_CONNECT_KEY_ID` | ID de la clave API de Apple |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID de App Store Connect |
| `APP_STORE_CONNECT_API_KEY_P8_BASE64` | Contenido del `.p8` codificado en base64 |

En PowerShell de Windows puedes convertir **cada archivo** a base64 sin imprimir datos confidenciales a la consola compartida:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\\ruta\\distribution.p12")) | Set-Content -NoNewline "C:\\ruta\\distribution.base64.txt"
```

Haz lo mismo para el perfil y `.p8`. Copia el contenido **directamente** al campo del secreto de GitHub y elimina luego los archivos de texto base64. Los secretos no se deben incluir en `README`, mensajes de GitHub ni ChatGPT.

## 5. Ejecutar publicación controlada

1. Abre https://github.com/LuisJose713/Finflow_Swift/actions
2. Selecciona **FinFlow iOS - Device Archive and TestFlight**.
3. **Run workflow** → `main`.
4. Elige `unsigned-archive` para validar la compilación de dispositivo sin firma.
5. Cuando todos los secretos, certificado y perfil estén listos, selecciona `testflight` para compilar, firmar, exportar IPA y **subirlo a App Store Connect TestFlight**.

La opción `testflight` **solo sube la compilación a Apple**. No la envía a revisión de App Store ni invita testers automáticamente. Apple puede tardar en procesar el archivo; verifica su estado en App Store Connect.

## Alcance y precauciones

- El CI del simulador no prueba inicio de sesión, roles, metas o movimientos con cuentas reales; aún falta QA funcional.
- Si un perfil no corresponde al App ID o al certificado, Xcode rechazará la firma; el pipeline fallará sin hacer una publicación.
- No compartas claves, passwords, p12, p8, tokens o URLs completas con credenciales para resolver errores. Comparte solamente el mensaje de error sin secretos.
- El build de TestFlight debe apuntar al backend oficial actualizado en Render. Antes de distribuir, resolver las tareas P1 de https://github.com/LuisJose713/WS_FINFLOW/issues/22.
- Los números de build se incrementan con `github.run_number`; la versión comercial permanece en `1.0.0` hasta el siguiente cambio.
