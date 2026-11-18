import { AccessToken, TrackSource } from 'livekit-server-sdk';
import { ErrorHttp } from './errores.js';

function configuracion() {
  const url = process.env.LIVEKIT_URL;
  const clave = process.env.LIVEKIT_API_KEY;
  const secreto = process.env.LIVEKIT_API_SECRET;
  if (!url || !clave || !secreto) {
    throw new ErrorHttp(503, 'la llamada en vivo no está disponible por ahora');
  }
  return { url, clave, secreto };
}

export async function tokenDeTelefono(sala, dispositivoId) {
  const { url, clave, secreto } = configuracion();
  const token = new AccessToken(clave, secreto, { identity: `tel-${dispositivoId}`, ttl: '10m' });
  token.addGrant({
    roomJoin: true,
    room: sala,
    canSubscribe: true,
    canPublishData: true,
    canPublishSources: [TrackSource.MICROPHONE, TrackSource.CAMERA],
  });
  return { url, token: await token.toJwt() };
}
