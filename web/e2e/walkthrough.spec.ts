import { test, expect } from '@playwright/test'

test('walkthrough steps advance and render precomputed networks', async ({ page }) => {
  await page.goto('/walkthrough')

  await expect(page.getByRole('heading', { name: /How coordination detection works/ })).toBeVisible()

  // Steps 1-2 are text-only; step 3 loads the full russian network.
  await page.getByTestId('walkthrough-next').click()
  await page.getByTestId('walkthrough-next').click()
  await expect(page.locator('canvas').first()).toBeVisible({ timeout: 30_000 })

  // Step 4: coordinated core.
  await page.getByTestId('walkthrough-next').click()
  await expect(page.locator('text=/Edge-weight percentile/')).toBeVisible()

  // Jump to the final fast-network step.
  await page.getByTestId('walkthrough-next').click()
  await page.getByTestId('walkthrough-next').click()
  await expect(page.getByTestId('walkthrough-next')).toBeDisabled()
  await expect(page.locator('canvas').first()).toBeVisible({ timeout: 30_000 })
})
