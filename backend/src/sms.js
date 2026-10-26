import { spawn } from 'node:child_process';
import { ErrorHttp } from './errores.js';

/**
 * Envío de SMS para el registro (HU01). Antes vivía en backend/sms_backend.py (Python);
 * ahora es parte de la API única. SMS_MODO en .env elige cómo se manda el código:
 *
 *   consola   (por defecto) NO manda nada: el código se imprime en la terminal de `npm run dev`.
 *             Es el modo probado de principio a fin.
 *   twilio    con Twilio (claves TWILIO_* en .env). Con TWILIO_VERIFY_SID usa Twilio Verify
 *             (Twilio genera y revisa el código; no hace falta comprar número); si no, manda un
 *             SMS normal desde TWILIO_FROM. La cuenta de prueba de Twilio no envía a celulares
 *             de México.
 *   mensajes  con la app Mensajes de la Mac donde corre el backend (solo macOS). Sale como SMS si
 *             el iPhone tiene "Reenvío de mensajes de texto" para esa Mac. Sin comprobar.
 */

export function modoSms() {
  return (process.env.SMS_MODO || 'consola').toLowerCase();
}

export function usaTwilioVerify() {
  return modoSms() === 'twilio' && Boolean(process.env.TWILIO_VERIFY_SID);
}

/** Manda `mensaje` al teléfono (formato +52...). Lanza ErrorHttp si no se pudo. */
export async function enviarSms(telefono, mensaje) {
  const modo = modoSms();
  if (modo === 'consola') {
    console.log(`[SMS a ${telefono}] ${mensaje}`);
    return;
  }
  if (modo === 'mensajes') {
    await enviarPorMensajes(telefono, mensaje);
    console.log(`[Mensaje enviado a ${telefono}]`);
    return;
  }
  if (modo === 'twilio') {
    await enviarPorTwilio(telefono, mensaje);
    console.log(`[SMS enviado a ${telefono}]`);
    return;
  }
  throw new ErrorHttp(503, 'Envío de SMS no configurado en el servidor');
}

// ── Twilio ───────────────────────────────────────────────────────────────────

async function twilioPost(url, datos) {
  const sid = process.env.TWILIO_ACCOUNT_SID ?? '';
  const token = process.env.TWILIO_AUTH_TOKEN ?? '';
  let respuesta;
  try {
    respuesta = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString('base64')}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams(datos),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    console.error('[Twilio] sin conexión:', error.cause?.code ?? error.message);
    throw new ErrorHttp(502, 'No se pudo conectar con el proveedor de SMS');
  }
  const cuerpo = await respuesta.json().catch(() => ({}));
  // El detalle de Twilio se queda en el log; al cliente solo le llega un mensaje genérico.
  if (!respuesta.ok) console.error(`[Twilio ${respuesta.status}] ${cuerpo.message ?? ''}`);
  return { estado: respuesta.status, cuerpo };
}

async function enviarPorTwilio(telefono, mensaje) {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const origen = process.env.TWILIO_FROM ?? '';
  if (!sid || !process.env.TWILIO_AUTH_TOKEN || !origen) {
    throw new ErrorHttp(503, 'Envío de SMS no configurado en el servidor');
  }
  const datos = { To: telefono, Body: mensaje };
  // TWILIO_FROM puede ser un número (+1...) o un Messaging Service (MG...).
  datos[origen.startsWith('MG') ? 'MessagingServiceSid' : 'From'] = origen;
  const { estado } = await twilioPost(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, datos);
  if (estado >= 300) throw new ErrorHttp(502, 'No se pudo enviar el SMS. Intenta más tarde.');
}

function urlVerify(ruta) {
  return `https://verify.twilio.com/v2/Services/${process.env.TWILIO_VERIFY_SID}/${ruta}`;
}

/** Twilio Verify genera el código y lo manda desde sus propios números. */
export async function enviarConVerify(telefono) {
  const { estado } = await twilioPost(urlVerify('Verifications'), { To: telefono, Channel: 'sms', Locale: 'es' });
  if (estado === 429) throw new ErrorHttp(429, 'Demasiados intentos. Espera unos minutos.');
  if (estado >= 300) throw new ErrorHttp(502, 'No se pudo enviar el SMS. Intenta más tarde.');
  console.log(`[SMS de Twilio Verify enviado a ${telefono}]`);
}

export async function revisarConVerify(telefono, codigo) {
  const { estado, cuerpo } = await twilioPost(urlVerify('VerificationCheck'), { To: telefono, Code: codigo });
  // Twilio responde 404 si ya no hay un código pendiente (venció, ya se usó o hubo muchos intentos).
  if (estado === 404 || (estado < 300 && cuerpo.status !== 'approved')) {
    throw new ErrorHttp(400, 'Código incorrecto o expirado');
  }
  if (estado >= 300) throw new ErrorHttp(502, 'No se pudo revisar el código. Intenta más tarde.');
}

// ── App Mensajes de la Mac (solo macOS) ──────────────────────────────────────

// Usa SMS si el iPhone reenvía SMS a esta Mac; si no, iMessage.
const GUION_MENSAJES = `
on run {telefono, texto, primero}
    if primero is "iMessage" then
        set tipos to {"iMessage", "SMS"}
    else
        set tipos to {"SMS", "iMessage"}
    end if
    tell application "Messages"
        set cuenta to missing value
        repeat with tipo in tipos
            repeat with c in every account
                try
                    if ((service type of c) as text) is (tipo as text) and (enabled of c) then
                        set cuenta to contents of c
                        exit repeat
                    end if
                end try
            end repeat
            if cuenta is not missing value then exit repeat
        end repeat
        if cuenta is missing value then error "Mensajes no tiene una cuenta de SMS o iMessage activa"
        send texto to participant telefono of cuenta
    end tell
end run
`;

function enviarPorMensajes(telefono, mensaje) {
  // SMS_MENSAJES_SERVICIO=imessage para probar con tu propio número (un SMS a ti mismo no llega).
  const primero = (process.env.SMS_MENSAJES_SERVICIO ?? '').toLowerCase() === 'imessage' ? 'iMessage' : 'SMS';
  return new Promise((resolve, reject) => {
    const fallo = () => reject(new ErrorHttp(502, 'No se pudo enviar con la app Mensajes de la Mac'));
    const proceso = spawn('osascript', ['-', telefono, mensaje, primero], { timeout: 30_000 });
    let errores = '';
    proceso.stderr.on('data', (d) => { errores += d; });
    proceso.on('error', (error) => { console.error('[Mensajes]', error.message); fallo(); });
    proceso.on('close', (codigo) => {
      if (codigo === 0) return resolve();
      console.error('[Mensajes]', errores.trim());
      fallo();
    });
    proceso.stdin.end(GUION_MENSAJES);
  });
}
