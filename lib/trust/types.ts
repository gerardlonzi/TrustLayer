export type RiskLevel = "LOW" | "MEDIUM" | "HIGH"

export interface IpInfo {
  country?: string
  country_code?: string
  timezone?: string
  latitude?: number
  longitude?: number
  vpn?: boolean
  proxy?: boolean
  tor?: boolean
  hosting?: boolean
}

export interface UserSignals {
  ip: string
  timezone?: string
  latitude?: number
  longitude?: number
  ipInfo?: IpInfo
}

export interface TrustResult {
  score: number
  risk: RiskLevel
  reasons: string[]
}
