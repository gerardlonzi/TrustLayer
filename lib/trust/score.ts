import { UserSignals, TrustResult } from "./types"

export function calculateTrustScore(signals: UserSignals): TrustResult {
  let score = 0

  // 1️⃣ IP Reputation
  switch (signals.ip_reputation) {
    case "LOW":
      score += 30
      break
    case "MEDIUM":
      score += 20
      break
    case "HIGH":
      score += 5
      break
  }

  // 2️⃣ Timezone Consistency
  score += signals.timezone_consistency ? 20 : 5

  // 3️⃣ Device Risk
  switch (signals.device_risk) {
    case "LOW":
      score += 20
      break
    case "MEDIUM":
      score += 10
      break
    case "HIGH":
      score += 0
      break
  }

  // 4️⃣ Bot Probability (inversement)
  const botFactor = 20 * (1 - signals.bot_probability)
  score += botFactor

  // 5️⃣ Clamp score entre 0 et 100
  if (score > 100) score = 100
  if (score < 0) score = 0

  // 6️⃣ Déterminer le niveau de risque
  let risk: TrustResult["risk"]
  if (score >= 70) risk = "LOW"
  else if (score >= 40) risk = "MEDIUM"
  else risk = "HIGH"

  return { score, risk }
}
