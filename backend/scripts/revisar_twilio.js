// Revisa la cuenta de Twilio del .env: tipo de cuenta, servicio de Verify y celulares autorizados.
// Uso:  npm run sms:revisar               (lista los celulares autorizados)
//       npm run sms:revisar -- 8112345678 (además dice si ese celular puede recibir el código)
// Solo lee; no manda SMS ni cambia nada en Twilio.
import { normalizar } from '../src/rutas/registro.js';

const sid = process.env.TWILIO_ACCOUNT_SID ?? '';
const token = process.env.TWILIO_AUTH_TOKEN ?? '';
const verifySid = process.env.TWILIO_VERIFY_SID ?? '';
if (!sid || !token) {
  console.error('Faltan TWILIO_ACCOUNT_SID o TWILIO_AUTH_TOKEN en backend/.env');
  process.exit(1);
}
const autorizacion = `Basic ${Buffer.from(`${sid}:${token}`).toString('base64')}`;

async function leer(url) {
  const respuesta = await fetch(url, { headers: { Authorization: autorizacion }, signal: AbortSignal.timeout(15_000) });
  const cuerpo = await respuesta.json().catch(() => ({}));
  if (!respuesta.ok) throw new Error(`Twilio respondió ${respuesta.status}: ${cuerpo.message ?? ''}`);
  return cuerpo;
}

const ocultar = (n) => n.slice(0, 3) + '•'.repeat(Math.max(0, n.length - 7)) + n.slice(-4);

try {
  const cuenta = await leer(`https://api.twilio.com/2010-04-01/Accounts/${sid}.json`);
  console.log(`Cuenta: ${cuenta.friendly_name} · tipo ${cuenta.type} · ${cuenta.status}`);

  if (verifySid) {
    const servicio = await leer(`https://verify.twilio.com/v2/Services/${verifySid}`);
    console.log(`Servicio de Verify: ${servicio.friendly_name}`);
  } else {
    console.log('Sin TWILIO_VERIFY_SID: el registro no usa Twilio Verify.');
  }

  const datos = await leer(`https://api.twilio.com/2010-04-01/Accounts/${sid}/OutgoingCallerIds.json?PageSize=50`);
  const autorizados = (datos.outgoing_caller_ids ?? []).map((c) => c.phone_number);
  console.log(`Celulares autorizados: ${autorizados.length ? autorizados.map(ocultar).join(', ') : 'ninguno'}`);

  if (process.argv[2]) {
    const telefono = normalizar(process.argv[2]);
    const formatoViejo = telefono.startsWith('+52') && !telefono.startsWith('+521') ? `+521${telefono.slice(3)}` : null;
    if (autorizados.includes(telefono)) {
      console.log(`✔ ${ocultar(telefono)} está autorizado: el código le debe llegar por SMS.`);
    } else if (formatoViejo && autorizados.includes(formatoViejo)) {
      console.log(`⚠ ${ocultar(telefono)} está autorizado, pero guardado con el formato viejo +521.`);
    } else if (cuenta.type === 'Trial') {
      console.log(`✘ ${ocultar(telefono)} NO está autorizado. Con la cuenta de prueba el código sale en la terminal.`);
      console.log('  Agrégalo en la consola de Twilio: Verify › Try it out › Send a verification › To (Recipient).');
    } else {
      console.log(`${ocultar(telefono)} no está en la lista, pero la cuenta no es de prueba: Twilio sí le debe mandar.`);
    }
  }
} catch (error) {
  console.error(error.message);
  if (/401/.test(error.message)) console.error('El Account SID y el Auth Token del .env no coinciden.');
  process.exit(1);
}
