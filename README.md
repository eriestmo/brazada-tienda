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
