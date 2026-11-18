import { createHash } from 'node:crypto';

export function huellaDeMatricula(matricula) {
  return createHash('sha256').update(matricula, 'utf8').digest('hex');
}
