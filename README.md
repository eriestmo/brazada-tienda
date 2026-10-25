# Brazada · Tienda de natación

Prototipo de tienda en línea para vender equipo de natación en Costa Rica: gafas, gorras, tablas, manoplas, aletas, trajes de baño y accesorios.

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
