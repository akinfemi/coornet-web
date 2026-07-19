import { test, expect } from '@playwright/test'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// Full user flow against the real API (must be running on :8010 with the
// vite proxy pointing at it): upload fixture -> map -> params -> run ->
// network renders -> tables -> export.
const HERE = path.dirname(fileURLToPath(import.meta.url))
const FIXTURE = path.resolve(HERE, '../../api/tests/fixtures/russian_coord_tweets.csv')

test('upload → map → run → network renders → export', async ({ page }) => {
  await page.goto('/')

  await page.getByTestId('file-input').setInputFiles(FIXTURE)

  // Columns already match the schema, so the mapping is pre-guessed.
  for (const f of ['object_id', 'account_id', 'content_id', 'timestamp_share']) {
    await expect(page.getByTestId(`map-${f}`)).toHaveValue(f)
  }
  await page.getByRole('button', { name: 'Validate mapping' }).click()
  await expect(page.getByTestId('validation-report')).toContainText('Valid')

  await page.getByTestId('run-analysis').click()
  await page.waitForURL(/\/jobs\//)

  // Job runs in a worker process; wait for the network canvas.
  await expect(page.locator('canvas').first()).toBeVisible({ timeout: 150_000 })

  // Sigma renders several stacked canvases; nodes drawn means >= 1 canvas has pixels.
  const canvasCount = await page.locator('canvas').count()
  expect(canvasCount).toBeGreaterThan(0)

  // Percentile slider filters edges without reloading.
  await page.getByTestId('percentile-slider').fill('90')
  await expect(page.locator('text=/\\d+ \\/ \\d+ edges/')).toBeVisible()

  // Accounts table.
  await page.getByRole('button', { name: 'accounts' }).click()
  await expect(page.locator('table tbody tr').first()).toBeVisible()

  // Export tab lists GraphML.
  await page.getByRole('button', { name: 'export' }).click()
  const dl = page.waitForEvent('download')
  await page.getByRole('link', { name: /GraphML/ }).click()
  const download = await dl
  expect(download.suggestedFilename()).toContain('graphml')
})
