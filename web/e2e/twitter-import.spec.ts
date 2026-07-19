import { test, expect } from '@playwright/test'

// UI-level regression test for the Twitter import flow. The API is stubbed via
// route interception with the EXACT response shapes the R backend produces —
// including `"params": []` on import-job status (empty R list serializes as an
// array), which once broke the client's zod schema and made the whole flow
// unusable despite a green backend test.
test('twitter import wizard path advances on backend-shaped responses', async ({ page }) => {
  const jobId = '11111111-2222-4333-8444-555555555555'
  const datasetId = '99999999-8888-4777-8666-555555555555'

  await page.route('**/api/v1/twitter/import', (route) =>
    route.fulfill({
      status: 202,
      contentType: 'application/json',
      body: JSON.stringify({ job_id: jobId, dataset_id: datasetId, status: 'queued' }),
    }),
  )
  let polls = 0
  await page.route(`**/api/v1/jobs/${jobId}`, (route) => {
    polls += 1
    const body =
      polls < 2
        ? // exactly what the R API returns for a running import job
          { status: 'running', stage: 'fetching', job_id: jobId, type: 'import', dataset_id: datasetId, params: [] }
        : {
            status: 'succeeded',
            stage: 'done',
            job_id: jobId,
            type: 'import',
            dataset_id: datasetId,
            params: [],
            result: { dataset_id: datasetId, n_rows: 6, n_tweets_fetched: 6 },
          }
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) })
  })

  await page.goto('/')
  await page.getByRole('button', { name: 'Import from X/Twitter' }).click()
  await page.getByPlaceholder('AAAA…').fill('fake-token-for-ui-test')
  await page.getByPlaceholder(/election2026/).fill('#test')
  await page.getByRole('button', { name: 'Fetch and map' }).click()

  // The wizard must reach the parameters step with the imported row count.
  await expect(page.getByTestId('validation-report')).toContainText('6 rows', {
    timeout: 15_000,
  })
  await expect(page.getByTestId('run-analysis')).toBeVisible()
})
