import { AccessToken, TrackSource } from 'livekit-server-sdk';
import { ErrorHttp } from './errores.js';

export function livekitConfigurado() {
  return Boolean(process.env.LIVEKIT_URL && process.env.LIVEKIT_API_KEY && process.env.LIVEKIT_API_SECRET);
}

export function origenesLivekit() {
  const direccion = process.env.LIVEKIT_URL;
  if (!direccion) return [];
  const { host } = new URL(direccion);
  return [`wss://${host}`, `https://${host}`, `ws://${host}`, `http://${host}`];
}

export async function tokenDeOperador(sala, personalId) {
  if (!livekitConfigurado()) throw new ErrorHttp(503, 'La llamada en vivo no está configurada');
  const token = new AccessToken(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, {
    identity: `op-${personalId}`,
    ttl: '10m',
  });
  token.addGrant({
    roomJoin: true,
    room: sala,
    canSubscribe: true,
    canPublishData: true,
    canPublishSources: [TrackSource.MICROPHONE],
  });
  return { url: process.env.LIVEKIT_URL, token: await token.toJwt() };
}
