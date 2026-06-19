
import { IpInfo } from "./types"

export function ipPenalty(
  ipInfo?: IpInfo
): { penalty: number; reasons: string[] } {
  if (!ipInfo) return { penalty: 0, reasons: [] }

  let penalty = 0
  const reasons: string[] = []

  if (ipInfo.vpn || ipInfo.proxy || ipInfo.tor) {
    penalty += 25
    reasons.push("VPN_OR_PROXY")
  }

  if (ipInfo.hosting) {
    penalty += 15
    reasons.push("HOSTING_IP")
  }

  return { penalty, reasons }
}
