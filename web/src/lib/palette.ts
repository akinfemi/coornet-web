// Categorical palette (validated 8-slot order — see dataviz reference palette).
// Communities beyond the 8 largest fold into the muted "Other" color.

const LIGHT = [
  '#2a78d6', '#008300', '#e87ba4', '#eda100',
  '#1baf7a', '#eb6834', '#4a3aa7', '#e34948',
]
const DARK = [
  '#3987e5', '#008300', '#d55181', '#c98500',
  '#199e70', '#d95926', '#9085e9', '#e66767',
]
const OTHER = '#898781'

export function isDarkMode(): boolean {
  const forced = document.documentElement.dataset.theme
  if (forced === 'dark') return true
  if (forced === 'light') return false
  return window.matchMedia('(prefers-color-scheme: dark)').matches
}

/**
 * Map community ids to colors: the 8 largest communities (by member count)
 * get the fixed categorical slots in order of size rank; the rest get "Other".
 */
export function communityColors(
  communitySizes: Map<number, number>,
): Map<number, string> {
  const slots = isDarkMode() ? DARK : LIGHT
  const ranked = [...communitySizes.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([id]) => id)
  const colors = new Map<number, string>()
  ranked.forEach((id, i) => {
    colors.set(id, i < slots.length ? slots[i] : OTHER)
  })
  return colors
}

export const OTHER_COLOR = OTHER
