# Probar FinFlow en una Mac prestada

## Preparar Xcode

La Mac debe poder ejecutar una versión de Xcode que incluya soporte para el iOS instalado en tu iPhone. El proyecto usa Swift 6 y admite iOS/iPadOS 17 o posterior.

1. Instala y abre Xcode. Acepta su licencia y deja que instale sus componentes.
2. En Terminal descarga `main` y abre el proyecto:

```bash
git clone https://github.com/LuisJose713/Finflow_Swift.git
cd Finflow_Swift
open FinFlow.xcodeproj
```

Si ya lo habías descargado, entra a su carpeta y ejecuta `git pull --ff-only origin main`.

## Instalar en el iPhone

1. En **Xcode > Settings > Accounts**, agrega tu Apple Account. Para probar en tu propio teléfono puedes usar el equipo personal de la cuenta; TestFlight utiliza otro proceso de distribución.
2. Selecciona el proyecto azul **FinFlow**, luego el target **FinFlow** y **Signing & Capabilities**.
3. Activa **Automatically manage signing** y selecciona tu **Team**. Si Apple indica que `com.finflow.ios` no está disponible para tu equipo, cambia solo en tu copia el **Bundle Identifier** a uno propio y único.
4. Conecta tu iPhone por cable, desbloquéalo y acepta **Confiar en este ordenador**.
5. Si Xcode lo solicita, habilita **Modo de desarrollador** en **Ajustes > Privacidad y seguridad** del iPhone y completa el reinicio.
6. En Xcode selecciona el esquema **FinFlow** y tu iPhone como destino. Pulsa **Run** (`⌘R`). Si iOS solicita confiar en el desarrollador de la app, completa esa verificación en sus ajustes.

La compilación de CI para simulador no es un archivo que puedas instalar directamente en el iPhone. La firma de tu Team se aplica al ejecutar desde Xcode.

## Primera apertura

- Inicia sesión con tu cuenta de FinFlow. La app utiliza el mismo backend de la Web.
- Autoriza Face ID cuando iOS lo solicite. La protección está activada por defecto si hay autenticación local configurada; el código del dispositivo sirve como respaldo.
- La política de datos se consulta al servidor. Un aviso informativo no equivale a un consentimiento registrado.
- Los avisos de las 10:00 y 16:00 necesitan permiso de notificaciones. Son recordatorios locales y funcionan sin APNs.

## Comprobaciones en el teléfono físico

1. Cancela Face ID: los movimientos deben seguir ocultos. Pulsa **Desbloquear** y completa Face ID o el código.
2. Cambia a otra app y regresa: debe solicitar autenticación otra vez. Comprueba también el selector de apps con un formulario abierto.
3. En **Ajustes > Contraseña y sesiones**, comprueba el control de protección y **Bloquear FinFlow ahora**.
4. En Inicio alterna **Lineal/Circular**. Toca o arrastra el gráfico y revisa los importes. La opción de ocultar importes debe ocultar también los gráficos.
5. Comprueba movimiento, billetera, presupuesto, meta, gasto planificado y recurrencia con una cuenta de prueba. Revisa sus resultados en la Web.
6. Exporta PDF/Excel y abre el archivo compartido. Verifica títulos, categorías, importes y filtros.
7. Revisa modo claro/oscuro, letra grande, giro de pantalla y teclado. Para los avisos reales, habilítalos en Ajustes y revisa que al tocarlos se abra su destino tras desbloquear.
8. Prueba eliminación de cuenta únicamente con una cuenta de prueba creada para ese propósito. Debe pedir contraseña y confirmación; cancelar debe conservarla.

## Ejecutar las pruebas automáticas

En Xcode usa **Product > Test** (`⌘U`) con el esquema **FinFlow**. Las pruebas utilizan datos ficticios. Para uso normal pulsa **Run**; no agregues `FINFLOW_UI_TESTING` al esquema de ejecución.

Los resultados remotos están en [GitHub Actions](https://github.com/LuisJose713/Finflow_Swift/actions/workflows/ios-ci.yml). El artefacto `finflow-ios-qa` contiene resultados y capturas de iPhone/iPad.

Al terminar con la Mac prestada, cierra sesión en FinFlow, elimina tu Apple Account de Xcode y retira los archivos de tu copia si no deseas dejarlos allí.

Referencias: [ejecutar desde Xcode](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device), [cuenta de desarrollo y pruebas en dispositivos](https://developer.apple.com/help/account/basics/about-your-developer-account), [LocalAuthentication](https://developer.apple.com/documentation/localauthentication).
