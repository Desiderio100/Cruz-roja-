import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { ErrorHttp } from '../errores.js';
import {
  exigirRol, exigirSesion, mismoOrigen, ponerCookieSesion, quitarCookieSesion,
} from './sesion.js';

/**
 * Sitio de administración de pedidos (para el personal de Cruz Roja).   Dueño: Sebastián
 *   POST   /admin/api/sesion                    iniciar sesión (usuario + contraseña de la tabla `personal`)
 *   DELETE /admin/api/sesion                    cerrar sesión
 *   GET    /admin/api/yo                        quién soy y si los pagos con Stripe están activos
 *   GET    /admin/api/pedidos                   lista con filtros (estado, envío, búsqueda) y páginas
 *   GET    /admin/api/pedidos/:id               detalle completo (domicilio, teléfono, historial)
 *   POST   /admin/api/pedidos/:id/envio         avanzar el envío: preparando > enviado > entregado (+ guía)
 *   POST   /admin/api/pedidos/:id/reembolso     devolver el dinero por Stripe (solo rol "administrativo")
 *
 * REGLAS DE SEGURIDAD
 *   - La contraseña se compara contra un hash bcrypt; nunca se guarda ni se registra en ningún lado.
 *     Una cuenta sin contraseña (solo matrícula, para el panel de llamadas y citas) no entra aquí.
 *   - Bloqueo por intentos fallidos con los procedimientos que ya existen en la base
 *     (personal_login_fallido / personal_login_exitoso): 5 intentos = 15 minutos de bloqueo.
 *   - Un pedido tiene nombre, teléfono y domicilio: abrir el detalle de un pedido, cambiar el envío
 *     y reembolsar quedan en la `bitacora` (quién y cuándo). La bitácora solo se agrega, no se edita.
 *   - Roles: "operador" ve pedidos y avanza el envío; "administrativo" además reembolsa.
 *   - Todas las respuestas llevan Cache-Control: no-store (traen datos personales).
 */

const ESTADOS = ['pendiente', 'pagado', 'cancelado', 'reembolsado'];
const ESTADOS_ENVIO = ['por_preparar', 'preparando', 'enviado', 'entregado'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TAMANO_PAGINA = 25;
const MAX_INTENTOS = 5;      // RNF07
const BLOQUEO_MINUTOS = 15;

// Para tardar lo mismo cuando el usuario no existe (no revelar qué usuarios hay).
const HASH_FALSO = bcrypt.hashSync(randomBytes(16).toString('hex'), 12);

const GUIA = /^[A-Za-z0-9][A-Za-z0-9 -]{2,39}$/;

const esquemaLogin = z.object({
  usuario: z.string().trim().min(3).max(60),
  contrasena: z.string().min(1).max(128),
});

const esquemaLista = z.object({
  estado: z.enum(ESTADOS).optional(),
  envio: z.array(z.enum(ESTADOS_ENVIO)).min(1).max(4).optional(),
  q: z.string().trim().max(60).optional(),
  pagina: z.coerce.number().int().min(1).max(10_000).default(1),
});

const esquemaEnvio = z.object({
  estado_envio: z.enum(['preparando', 'enviado', 'entregado'], { message: 'el estado del envío no es válido' }),
  guia: z.string().trim().regex(GUIA, 'la guía debe tener de 3 a 40 letras, números, espacios o guiones').optional(),
});

const esquemaReembolso = z.object({
  motivo: z.string().trim().max(200, 'el motivo es muy largo')
    .regex(/^[^\u0000-\u001F\u007F]*$/, 'el motivo no es válido').optional(),
}).default({});

function idPedido(req) {
  if (!UUID.test(req.params.id)) throw new ErrorHttp(404, 'el pedido no existe');
  return req.params.id.toLowerCase();
}

async function anotar(conexion, personalId, accion, pedidoId, detalle) {
  await conexion.query(
    'INSERT INTO bitacora (personal_id, accion, entidad, entidad_id, detalle) VALUES (?, ?, ?, ?, ?)',
    [personalId, accion, pedidoId ? 'pedido' : null, pedidoId ?? null, detalle ? JSON.stringify(detalle) : null]);
}

// Lo que se muestra en la lista: sin teléfono ni domicilio (eso solo sale en el detalle, y queda en la bitácora).
const COLUMNAS_LISTA = `id, folio, producto_nombre, cantidad, total_mxn, estado, estado_envio, nombre,
                        creado_en, pagado_en`;

const COLUMNAS_DETALLE = `id, folio, estado, estado_envio, guia_envio, producto_nombre, cantidad,
  precio_unitario_mxn, envio_mxn, total_mxn, nombre, telefono, calle_numero, colonia, ciudad, entidad,
  codigo_postal, referencias, creado_en, pagado_en, enviado_en, entregado_en, reembolsado_en,
  reembolso_motivo, stripe_payment_intent_id, stripe_refund_id`;

/**
 * @param pool    pool de MySQL (el único de la API)
 * @param pagos   lo que devuelve configuracionPagos() de src/stripe.js
 * @param config  lo que devuelve configuracionAdmin() de src/admin/sesion.js
 */
export function rutasAdmin(pool, pagos, config) {
  const router = Router();
  const sesion = exigirSesion(pool, config);

  router.use((_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
  router.use(mismoOrigen);

  // ── Sesión ────────────────────────────────────────────────────────────────
  const limiteLogin = rateLimit({
    windowMs: 15 * 60_000, limit: config.limiteLoginPorQuinceMin ?? 10,
    standardHeaders: 'draft-7', legacyHeaders: false,
    message: { error: 'Demasiados intentos. Espera unos minutos e intenta de nuevo.' },
  });

  router.post('/sesion', limiteLogin, async (req, res) => {
    const lectura = esquemaLogin.safeParse(req.body || {});
    if (!lectura.success) throw new ErrorHttp(400, 'Escribe tu usuario y tu contraseña');
    const usuario = lectura.data.usuario.toLowerCase();

    const [filas] = await pool.query(
      'SELECT id, hash_contrasena, rol, activo, bloqueado_hasta FROM personal WHERE usuario = ?', [usuario]);
    const persona = filas[0];
    // Las cuentas que solo entran con matrícula (panel de llamadas y citas, 10_modo_personal.sql) no
    // tienen contraseña: aquí cuentan como "usuario o contraseña incorrectos", igual que si no existieran.
    const valida = Boolean(persona?.activo && persona.hash_contrasena);

    if (valida && persona.bloqueado_hasta && new Date(persona.bloqueado_hasta) > new Date()) {
      throw new ErrorHttp(429, 'Demasiados intentos fallidos. Espera unos minutos e intenta de nuevo.');
    }

    const coincide = await bcrypt.compare(lectura.data.contrasena, valida ? persona.hash_contrasena : HASH_FALSO);
    if (!valida || !coincide) {
      if (valida) {
        await pool.query('CALL personal_login_fallido(?, ?, ?, @zz_bloqueada_hasta)', [usuario, MAX_INTENTOS, BLOQUEO_MINUTOS]);
        await anotar(pool, persona.id, 'login_fallido', null, null);
      }
      throw new ErrorHttp(401, 'Usuario o contraseña incorrectos');
    }

    await pool.query('CALL personal_login_exitoso(?)', [persona.id]);
    await anotar(pool, persona.id, 'login_ok', null, null);
    ponerCookieSesion(res, config, persona.id);
    res.json({ usuario, rol: persona.rol });
  });

  router.delete('/sesion', (_req, res) => {
    quitarCookieSesion(res, config);
    res.status(204).end();
  });

  router.get('/yo', sesion, (req, res) => {
    res.json({
      usuario: req.personal.usuario,
      rol: req.personal.rol,
      pagos: { disponible: Boolean(pagos.stripe), modo: pagos.modo },
      panel_personal: config.panelPersonal || null,   // enlace al panel de llamadas y citas (opcional)
    });
  });

  // ── Lista de pedidos ──────────────────────────────────────────────────────
  router.get('/pedidos', sesion, async (req, res) => {
    // Los parámetros vacíos se ignoran; "envio" admite varios separados por coma.
    const crudo = {};
    for (const [clave, valor] of Object.entries(req.query)) {
      if (typeof valor === 'string' && valor !== '') crudo[clave] = valor;
    }
    if (crudo.envio) crudo.envio = crudo.envio.split(',');
    const lectura = esquemaLista.safeParse(crudo);
    if (!lectura.success) throw new ErrorHttp(400, 'los filtros no son válidos');
    const { estado, envio, q, pagina } = lectura.data;

    const condiciones = [];
    const parametros = [];
    if (estado) { condiciones.push('estado = ?'); parametros.push(estado); }
    if (envio) { condiciones.push('estado_envio IN (?)'); parametros.push(envio); }
    if (q) {
      const patron = `%${q.replace(/[\\%_]/g, '\\$&')}%`;
      condiciones.push('(folio LIKE ? OR nombre LIKE ? OR telefono LIKE ? OR producto_nombre LIKE ?)');
      parametros.push(patron, patron, patron, patron);
    }
    const donde = condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '';

    const [[{ total }]] = await pool.query(`SELECT COUNT(*) AS total FROM pedido ${donde}`, parametros);
    const [pedidos] = await pool.query(
      `SELECT ${COLUMNAS_LISTA} FROM pedido ${donde} ORDER BY creado_en DESC, id LIMIT ? OFFSET ?`,
      [...parametros, TAMANO_PAGINA, (pagina - 1) * TAMANO_PAGINA]);

    // Conteos para los filtros de arriba (no dependen de lo que se esté filtrando).
    const [conteos] = await pool.query('SELECT estado, estado_envio, COUNT(*) AS n FROM pedido GROUP BY estado, estado_envio');
    const resumen = { pendiente: 0, pagado: 0, cancelado: 0, reembolsado: 0, por_enviar: 0, enviado: 0, entregado: 0 };
    for (const c of conteos) {
      resumen[c.estado] += c.n;
      if (c.estado !== 'pagado') continue;
      if (['por_preparar', 'preparando'].includes(c.estado_envio)) resumen.por_enviar += c.n;
      else resumen[c.estado_envio] += c.n;   // enviado o entregado
    }

    res.json({ pedidos, total, pagina, paginas: Math.max(1, Math.ceil(total / TAMANO_PAGINA)), resumen });
  });

  // ── Detalle de un pedido ──────────────────────────────────────────────────
  async function detalle(id, personal, { registrarVista }) {
    const [filas] = await pool.query(`SELECT ${COLUMNAS_DETALLE} FROM pedido WHERE id = ?`, [id]);
    if (filas.length === 0) throw new ErrorHttp(404, 'el pedido no existe');
    const pedido = filas[0];
    // Ver los datos personales de un cliente queda anotado. Si no se pudo anotar, no se muestran.
    if (registrarVista) await anotar(pool, personal.id, 'ver_pedido', id, { folio: pedido.folio });

    const [historial] = await pool.query(
      `SELECT b.accion, b.detalle, b.creada_en AS fecha, p.usuario
         FROM bitacora b LEFT JOIN personal p ON p.id = b.personal_id
        WHERE b.entidad = 'pedido' AND b.entidad_id = ?
          AND b.accion IN ('actualizar_envio', 'reembolsar_pedido', 'reembolso_confirmado_stripe')
        ORDER BY b.id`, [id]);

    return {
      ...pedido,
      historial: historial.map((h) => ({
        accion: h.accion,
        usuario: h.usuario ?? null,                    // null = lo avisó Stripe
        fecha: h.fecha,
        detalle: typeof h.detalle === 'string' ? JSON.parse(h.detalle) : (h.detalle ?? {}),
      })),
      puede_reembolsar: personal.rol === 'administrativo' && Boolean(pagos.stripe)
        && pedido.estado === 'pagado' && Boolean(pedido.stripe_payment_intent_id),
    };
  }

  router.get('/pedidos/:id', sesion, async (req, res) => {
    res.json(await detalle(idPedido(req), req.personal, { registrarVista: true }));
  });

  // ── Avanzar el envío ──────────────────────────────────────────────────────
  router.post('/pedidos/:id/envio', sesion, async (req, res) => {
    const id = idPedido(req);
    const lectura = esquemaEnvio.safeParse(req.body || {});
    if (!lectura.success) throw new ErrorHttp(400, lectura.error.issues[0].message);
    const { estado_envio: nuevo, guia } = lectura.data;

    const conexion = await pool.getConnection();
    try {
      await conexion.beginTransaction();
      const [filas] = await conexion.query(
        'SELECT folio, estado, estado_envio, guia_envio FROM pedido WHERE id = ? FOR UPDATE', [id]);
      if (filas.length === 0) throw new ErrorHttp(404, 'el pedido no existe');
      const p = filas[0];
      if (p.estado === 'reembolsado') throw new ErrorHttp(409, 'Este pedido fue reembolsado: ya no se puede cambiar su envío');
      if (p.estado !== 'pagado') throw new ErrorHttp(409, 'Solo se puede dar seguimiento al envío de pedidos pagados');

      const de = ESTADOS_ENVIO.indexOf(p.estado_envio);
      const a = ESTADOS_ENVIO.indexOf(nuevo);
      const soloGuia = a === de && nuevo === 'enviado' && guia && guia !== p.guia_envio;
      if (a <= de && !soloGuia) throw new ErrorHttp(409, 'El pedido ya está en ese estado o más adelante');

      await conexion.query(
        `UPDATE pedido
            SET estado_envio = ?,
                guia_envio   = COALESCE(?, guia_envio),
                enviado_en   = IF(? IN ('enviado', 'entregado'), COALESCE(enviado_en, UTC_TIMESTAMP(3)), enviado_en),
                entregado_en = IF(? = 'entregado', COALESCE(entregado_en, UTC_TIMESTAMP(3)), entregado_en)
          WHERE id = ?`,
        [nuevo, guia ?? null, nuevo, nuevo, id]);
      await anotar(conexion, req.personal.id, 'actualizar_envio', id,
        { folio: p.folio, de: p.estado_envio, a: nuevo, ...(guia ? { guia } : {}) });
      await conexion.commit();
    } catch (error) {
      await conexion.rollback().catch(() => {});
      throw error;
    } finally {
      conexion.release();
    }
    res.json(await detalle(id, req.personal, { registrarVista: false }));
  });

  // ── Reembolso por Stripe ──────────────────────────────────────────────────
  router.post('/pedidos/:id/reembolso', sesion, exigirRol('administrativo'), async (req, res) => {
    const id = idPedido(req);
    const lectura = esquemaReembolso.safeParse(req.body ?? {});
    if (!lectura.success) throw new ErrorHttp(400, lectura.error.issues[0].message);
    const motivo = lectura.data.motivo || null;
    if (!pagos.stripe) throw new ErrorHttp(503, 'Los pagos con Stripe no están activos en el servidor');

    const [filas] = await pool.query(
      'SELECT folio, estado, total_mxn, stripe_payment_intent_id FROM pedido WHERE id = ?', [id]);
    if (filas.length === 0) throw new ErrorHttp(404, 'el pedido no existe');
    const p = filas[0];
    if (p.estado === 'reembolsado') throw new ErrorHttp(409, 'Este pedido ya fue reembolsado');
    if (p.estado !== 'pagado' || !p.stripe_payment_intent_id) {
      throw new ErrorHttp(409, 'Solo se pueden reembolsar pedidos que ya están pagados');
    }

    // Reembolso TOTAL. La llave de idempotencia evita devolver dos veces el dinero si le dan clic dos veces.
    let reembolso;
    let sincronizado = false;
    try {
      reembolso = await pagos.stripe.refunds.create({
        payment_intent: p.stripe_payment_intent_id,
        reason: 'requested_by_customer',
        metadata: { pedido_id: id, folio: p.folio },
      }, { idempotencyKey: `reembolso-${id}` });
    } catch (error) {
      if (error.code === 'charge_already_refunded') {
        // Ya se había devuelto desde el Dashboard de Stripe: solo se pone al día el pedido.
        const lista = await pagos.stripe.refunds.list({ payment_intent: p.stripe_payment_intent_id, limit: 1 });
        reembolso = lista.data[0];
        sincronizado = true;
      }
      if (!reembolso) {
        console.error('POST /admin/api/pedidos/:id/reembolso: Stripe no hizo el reembolso:', error.code ?? error.type ?? error.message);
        throw new ErrorHttp(502, 'Stripe no pudo hacer el reembolso. Revisa el pedido en el Dashboard de Stripe antes de intentar otra vez.');
      }
    }
    if (!['succeeded', 'pending'].includes(reembolso.status)) {
      console.error(`Stripe: el reembolso ${reembolso.id} del pedido ${p.folio} quedó en estado ${reembolso.status}`);
      throw new ErrorHttp(502, 'Stripe no pudo completar el reembolso. Revisa el pedido en el Dashboard de Stripe.');
    }

    // Se anota en la base. Si esto fallara, el aviso de Stripe (charge.refunded) pone al día el pedido.
    const conexion = await pool.getConnection();
    try {
      await conexion.beginTransaction();
      const [r] = await conexion.query(
        `UPDATE pedido
            SET estado = 'reembolsado', stripe_refund_id = ?, reembolso_motivo = COALESCE(?, reembolso_motivo),
                reembolsado_en = COALESCE(reembolsado_en, UTC_TIMESTAMP(3))
          WHERE id = ? AND estado IN ('pagado', 'reembolsado') AND stripe_refund_id IS NULL`,
        [reembolso.id, motivo, id]);
      if (r.affectedRows > 0) {
        await anotar(conexion, req.personal.id, 'reembolsar_pedido', id,
          { folio: p.folio, total_mxn: p.total_mxn, reembolso: reembolso.id, ...(motivo ? { motivo } : {}), ...(sincronizado ? { ya_estaba_en_stripe: true } : {}) });
      }
      await conexion.commit();
    } catch (error) {
      await conexion.rollback().catch(() => {});
      console.error(`Reembolso ${reembolso.id} hecho en Stripe pero no anotado en la base (pedido ${p.folio}):`, error.code ?? error.message);
      throw new ErrorHttp(500, 'El reembolso se hizo en Stripe, pero no se pudo anotar aquí. Avisa al equipo técnico: el pedido se pondrá al día cuando Stripe confirme.');
    } finally {
      conexion.release();
    }
    res.json(await detalle(id, req.personal, { registrarVista: false }));
  });

  return router;
}
