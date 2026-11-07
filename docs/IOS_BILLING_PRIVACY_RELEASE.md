# FinFlow iOS — paridad con web (sin Beta Estudiante)

## Nuevo flujo iOS

- Registro: política obtenida de GET /privacy/policy, aceptación expresa, marketing opcional. El backend asigna el mes gratis de Pro.
- Usuarios existentes: GET /privacy/status, y si corresponde POST /privacy/consent. La app no permite entrar a finanzas sin autorización confirmada por servidor.
- Derechos: POST /privacy/rights-request para acceso, rectificación, eliminación o revocación.
- Precios: GET /billing/catalog, /billing/me y /billing/quote; los precios, descuentos y acceso Pro son autoridad del backend.
- Administración: gestión de planes, campañas y concesiones manuales de Pro con API protegida por ADMIN, sin acceso a finanzas de terceros.
- Perfil: cambio de nombre con contraseña y cambio de correo solamente tras código temporal enviado a la nueva dirección.
- Diseño: SwiftUI nativo usa Form, ScrollView y VStack para mantener los campos apilados en pantallas pequeñas.
- Donaciones y compras de Pro: INFORMACIÓN SOLAMENTE, sin cobros en iOS. Su publicación requiere StoreKit 2 y recibos verificados en backend según la política de la App Store.

## Publicación

La integración del backend y la web aún se encuentra en PRs pendientes. Deben completarse identidad legal real del responsable del tratamiento, revisión de la política, configuración SMTP, QA de consentimiento, autorización, suscripciones, administración y pruebas en simulador. Compilar no equivale a publicar.

**Beta Estudiante no está incluida.** El programa permanece separado del release web y del código iOS.
