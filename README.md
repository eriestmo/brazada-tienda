# Emily Natación · Tienda y clases de natación

Sitio de Emily Duncan (marca Emily Natación): tienda en línea para vender equipo de natación en Costa Rica: gafas, gorras, tablas, manoplas, aletas, trajes de baño y accesorios.

- El cliente arma su carrito, elige talla y color, y escoge la entrega (en clase, mensajería GAM o Correos de Costa Rica).
- El pedido se confirma por WhatsApp y se paga con SINPE Móvil.
- Es un solo archivo, `index.html`, sin servidor ni base de datos. Se publica con GitHub Pages.

## Configuración

Al inicio del `<script>` en `index.html` está el bloque `CONFIG`:

- `whatsapp`: número de la profe con código de país (por ejemplo `5068XXXXXXX`).
- `sinpe`: número y nombre para el pago por SINPE Móvil.
- `entregas`: formas de entrega y sus costos.

Los productos están en la lista `PRODUCTS` del mismo archivo.

> Prototipo para revisión: los productos, precios y números son de ejemplo.

## Clases y reservas (`clases.html`)

- Horario semanal, tipos de clase, planes y fecha de pago (el 5 de cada mes por SINPE Móvil).
- Cuentas de alumnos: reservar, cambiar fecha o cancelar hasta 12 horas antes, y ver el próximo pago y el historial.
- Panel de la profe: agenda del día, alumnos y confirmación de pagos.
- Datos en Supabase. El esquema, las reglas de seguridad (RLS) y las funciones están en `supabase/schema.sql`; se ejecuta en Supabase > SQL Editor.
- Para dar acceso de profe: `update public.profiles set role = 'profe' where email = '...';`

## Marca

Identidad según el brandbook de Emily Natación (`PRODUCT.md`): logos en `assets/` (`logo-emily` para fondos claros, `logo-emily-blanco` para oscuros, `emily-kids` para lo de niños), paleta celeste y morada, Poppins + Playfair Display. Instagram: [@emily.natacion](https://www.instagram.com/emily.natacion).

## Mantenimiento

- **Supabase activo:** `.github/workflows/mantener-supabase.yml` consulta la base cada 3 días para que el plan gratuito no la pause. Ojo: GitHub desactiva las tareas programadas si el repositorio pasa 60 días sin cambios; si llega un correo de GitHub avisando, se reactiva en la pestaña Actions.
- **Respaldo semanal:** `scripts/respaldo.sh` exporta las tablas a `~/Respaldos/emily-natacion/AAAA-MM-DD/` (JSON, solo lectura para el usuario, se guardan los 12 últimos). Lo ejecuta cada domingo a las 9:00 la tarea de macOS `~/Library/LaunchAgents/cr.emilynatacion.respaldo.plist`; registro en `~/Respaldos/emily-natacion/respaldo.log`. Necesita la sesión de la CLI de Supabase (`supabase login`). Las contraseñas de los usuarios no se respaldan.
- **Privacidad:** `privacidad.html` (Ley 8968, cambios y cancelaciones). El registro pide aceptarla.
- **Productos:** viven en la tabla `products` de Supabase. Emily los edita en Panel → Productos (precio, textos, colores, tallas, etiqueta, agotado, visible, agregar nuevos). La tienda los lee al cargar; si no hay conexión usa la lista `PRODUCTS` de `index.html` como respaldo (puede quedar desactualizada, no es la fuente de verdad).
- **Asistencia:** en Panel → Agenda, las clases que ya empezaron muestran "Asistió" / "No vino" (y "Deshacer"). Las familias ven el registro en Mis clases → Anteriores.
- **App instalable:** `manifest.webmanifest` + íconos en `assets/` (Android: "Instalar app"; iPhone: "Agregar a pantalla de inicio").
