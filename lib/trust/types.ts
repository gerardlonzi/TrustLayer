
export type RiskLevel = "LOW" | "MEDUIM" | "HIGH" 

export interface TrustResult {
    score : number,
    risk : RiskLevel
}