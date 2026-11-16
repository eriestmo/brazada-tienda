# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users
- Parents in Costa Rica whose children take (or will take) swimming lessons with Emily, buying gear for them and booking their classes, mostly from a phone.
- Adults and older adults who take lessons themselves.
- Emily Duncan, the swimming coach, who manages classes, students and payments from her phone (panel de la profe).

## Product Purpose
"Emily Natación" is Emily Duncan's own site: a small store of swimming gear (goggles, caps, kickboards, paddles, fins, swimsuits, accessories) as extra income, plus class booking with student accounts, reschedule/cancel, and monthly payment due dates. Success: families buy the gear Emily recommends and manage their classes without chasing her on WhatsApp.

## Positioning
The gear and the classes come from the same coach: every product is one Emily uses or recommends in class, and sizing help comes from someone who knows the child.

## Operating Context
- Orders are confirmed on Emily's WhatsApp (8330-7672) and paid by SINPE Móvil (8330-7672, Emily Duncan); no card payments.
- Delivery: hand-off at class, GAM courier, or Correos de Costa Rica.
- Classes are both private at-home lessons (babies, kids, adults, older adults) and group classes with a fixed schedule and capacity at a pool. Monthly plans are due on the 5th.

## Capabilities and Constraints
- Static site on GitHub Pages (`index.html` store, `clases.html` classes); data and auth in Supabase (`supabase/schema.sql`, RLS + RPCs). No build step.
- Spanish from Costa Rica, "usted".
- Open: real product list and prices, real schedule, plan prices, pool location, how at-home private lessons are scheduled (address and travel zone are coordinated by WhatsApp for now).

## Brand Commitments
- Name: Emily Natación (replaces the earlier working name "Brazada"). Kids sub-brand: Emily Kids (mascot: girl in a shark hoodie), used for everything aimed at children.
- Brandbook: `~/Downloads/Brandbook Emily Natacion.pdf` (logos, safe areas, misuse, palette, typography Poppins + Playfair, wave elements). Logo font Ziclets is for the logo only.
- Instagram: https://www.instagram.com/emily.natacion
- Voice: warm, encouraging, educational coach ("ya estás en el top de personas que dominan un medio acuático").

## Evidence on Hand
- Logos extracted from the brandbook (`assets/`). No real product photos, testimonials or student counts yet: do not fabricate them.

## Product Principles
- Recommended by the coach: trust comes from Emily, not from a catalog.
- Phone first: parents act from WhatsApp and Instagram on a phone.
- No dead ends: every order and booking ends in a clear next step (WhatsApp, SINPE).
