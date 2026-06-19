import { UserSignals, TrustResult } from "./types"
import { geoDistancePenalty } from "./geo"
import { timezonePenalty } from "./timezone"
import { ipPenalty } from "./ip"

export function evaluateTrust(
  user: UserSignals
): TrustResult {
  let score = 100
  const reasons: string[] = []

  // IP reputation
  const ipResult = ipPenalty(user.ipInfo)
  score -= ipResult.penalty
  reasons.push(...ipResult.reasons)

  // Timezone consistency
  const tz = timezonePenalty(
    user.ipInfo?.timezone,
    user.timezone
  )
  score -= tz.penalty
  if (tz.reason) reasons.push(tz.reason)

  // Geo distance
  const geo = geoDistancePenalty(
    user.ipInfo?.latitude,
    user.ipInfo?.longitude,
    user.latitude,
    user.longitude
  )
  score -= geo.penalty
  if (geo.reason) reasons.push(geo.reason)

  score = Math.max(0, score)

  const risk =
    score > 70 ? "LOW" :
    score > 40 ? "MEDIUM" :
    "HIGH"

  return { score, risk, reasons }
}
