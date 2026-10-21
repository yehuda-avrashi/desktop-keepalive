import { test, expect } from 'claude-code/testing'

// Every prompt that is not the wake task's scheduled trigger must pass through untouched,
// so the plugin changes nothing in normal sessions.
test('a normal prompt passes through unchanged', async ($, on) => {
  on('prompt.submit', ($, e) => ({ text: e.text }))
  const r = await $.prompt.submit({ text: 'hello' })
  expect(r).toEqual({ text: 'hello' })
})

test('a prompt with the marker that is not a scheduled trigger passes through', async ($, on) => {
  on('prompt.submit', ($, e) => ({ text: e.text }))
  const r = await $.prompt.submit({ text: 'test [[desktop-keepalive]]' })
  expect(r).toEqual({ text: 'test [[desktop-keepalive]]' })
})
