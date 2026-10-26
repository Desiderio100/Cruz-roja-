import { randomInt, timingSafeEqual } from 'node:crypto';
import { Router } from 'express';
import { ErrorHttp } from '../errores.js';
import { enviarConVerify, enviarSms, revisarConVerify, usaTwilioVerify } from '../sms.js';

/**
 * HU01 — Registro con verificación por SMS.   (Antes backend/sms_backend.py, en Python.)
 *   POST /api/registro/codigo      { telefono }           manda un código de 6 dígitos por SMS
 *   POST /api/registro/verificar   { telefono, codigo }   revisa el código y guarda el teléfono
 *                                                         verificado en el dispositivo (X-Dispositivo-Id)
 * El código nunca se devuelve al cliente: solo llega por SMS (o a la consola en desarrollo).
 * El nombre NO se guarda en la base: se queda en el iPhone.
 */

const VIGENCIA_MS = 5 * 60_000;        // el código caduca a los 5 minutos
const ESPERA_REENVIO_MS = 60_000;      // tiempo mínimo entre dos envíos al mismo número
const MAX_INTENTOS = 5;                // intentos fallidos antes de invalidar el código
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// telefono -> { codigo, expira, enviado, intentos }. En memoria: se pierde al reiniciar el servidor.
const codigos = new Map();

/** Número en formato internacional (E.164), p. ej. +528112345678. */
export function normalizar(valor) {
  const texto = String(valor ?? '').trim();
  if (texto.length > 30 || !/^[+0-9()\- ]+$/.test(texto)) throw new ErrorHttp(400, 'Teléfono inválido');
  let digitos = texto.replace(/\D/g, '');
  if (digitos.length < 10 || digitos.length > 15) throw new ErrorHttp(400, 'Teléfono inválido');
  // Número nacional de 10 dígitos: se le pone la lada del país (52 = México).
  if (!texto.startsWith('+') && digitos.length === 10) digitos = (process.env.SMS_PAIS || '52') + digitos;
  return `+${digitos}`;
}

function idDispositivo(req) {
  const id = String(req.get('X-Dispositivo-Id') || '').toLowerCase();
  if (!UUID.test(id)) throw new ErrorHttp(401, 'falta el dispositivo');
  return id;
}

function iguales(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && timingSafeEqual(x, y);
}

function respaldoConsola() {
  return process.env.SMS_RESPALDO_CONSOLA === 'si' && process.env.NODE_ENV !== 'production';
}

function limpiarVencidos(ahora) {
  for (const [telefono, registro] of codigos) {
    if (ahora - registro.enviado > VIGENCIA_MS + ESPERA_REENVIO_MS) codigos.delete(telefono);
  }
}

export function rutasRegistro(pool) {
  const router = Router();

  // Manda el código. No pide dispositivo: se puede pedir antes de tener cuenta.
  router.post('/codigo', async (req, res) => {
    const telefono = normalizar(req.body?.telefono);
    const ahora = Date.now();
    limpiarVencidos(ahora);

    const previo = codigos.get(telefono);
    if (previo && ahora - previo.enviado < ESPERA_REENVIO_MS) {
      throw new ErrorHttp(429, 'Espera un minuto antes de pedir otro código');
    }

    if (usaTwilioVerify()) {
      await enviarConVerify(telefono);
      // Twilio guarda el código; aquí solo se anota la hora para la espera de reenvío.
      codigos.set(telefono, { codigo: null, expira: 0, enviado: ahora, intentos: 0 });
      return res.json({ ok: true });
    }

    const codigo = String(randomInt(0, 1_000_000)).padStart(6, '0');
    const mensaje = `Tu código de Cruz Roja es ${codigo}`;
    try {
      await enviarSms(telefono, mensaje);
    } catch (error) {
      // Solo en desarrollo (SMS_RESPALDO_CONSOLA=si y sin NODE_ENV=production): si el SMS falla
      // (p. ej. la cuenta de prueba de Twilio no envía a México), el código sale en esta terminal
      // para poder seguir probando. En producción el error llega a la app como siempre.
      if (!respaldoConsola()) throw error;
      console.warn(`[SMS falló, respaldo de desarrollo] [SMS a ${telefono}] ${mensaje}`);
    }
    codigos.set(telefono, { codigo, expira: ahora + VIGENCIA_MS, enviado: ahora, intentos: 0 });
    res.json({ ok: true });
  });

  // Revisa el código y guarda el teléfono verificado en el dispositivo de quien lo pide.
  router.post('/verificar', async (req, res) => {
    const dispositivo = idDispositivo(req);
    const telefono = normalizar(req.body?.telefono);
    const codigo = String(req.body?.codigo ?? '').trim();
    if (!/^\d{4,10}$/.test(codigo)) throw new ErrorHttp(400, 'Código incorrecto o expirado');

    // Primero el dispositivo: si no existe, la app se registra y reintenta sin gastar el código.
    const [filas] = await pool.execute('SELECT 1 FROM dispositivo WHERE id = ?', [dispositivo]);
    if (filas.length === 0) throw new ErrorHttp(400, 'dispositivo no registrado');

    if (usaTwilioVerify()) {
      await revisarConVerify(telefono, codigo);
    } else {
      const registro = codigos.get(telefono);
      if (!registro || Date.now() > registro.expira) throw new ErrorHttp(400, 'Código incorrecto o expirado');
      if (!iguales(registro.codigo, codigo)) {
        registro.intentos += 1;
        // Se invalida, pero se conserva para que siga aplicando la espera de reenvío.
        if (registro.intentos >= MAX_INTENTOS) registro.expira = 0;
        throw new ErrorHttp(400, 'Código incorrecto o expirado');
      }
    }
    codigos.delete(telefono); // cada código sirve una sola vez

    await pool.execute('UPDATE dispositivo SET telefono = ? WHERE id = ?', [telefono, dispositivo]);
    res.json({ ok: true, telefono });
  });

  return router;
}
