import { expect, test } from 'vitest';

test('passing arithmetic', () => {
  expect(2 + 2).toBe(4);
});

test('intentional outcome', () => {
  expect(process.env.NVIM_WORKFLOW_FAIL).not.toBe('1');
});
